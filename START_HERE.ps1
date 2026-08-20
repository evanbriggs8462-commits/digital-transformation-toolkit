[CmdletBinding()]
param(
    [string]$PbixName,
    [switch]$SkipDaxStudio,
    [switch]$RequireDaxStudio,
    [switch]$SetupOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$toolkitRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
$toolkitRoot = [System.IO.Path]::GetFullPath($toolkitRoot)
$commonPath = Join-Path $toolkitRoot "powershell\common.ps1"

$runtimeRoot = Join-Path $env:LOCALAPPDATA "DigitalTransformationToolkit\runtime"
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
$statePath = Join-Path $runtimeRoot "state.json"
$resultPath = Join-Path $runtimeRoot "result.json"
$logPath = Join-Path $runtimeRoot "latest.log"
$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
$warnings = New-Object System.Collections.Generic.List[string]
$fixes = New-Object System.Collections.Generic.List[string]
$resolvedPbixName = $null
$manifestPath = $null
$outputFolder = $null
$te2Path = $null
$dscmdPath = $null
$desktopTarget = $null
$runMutex = $null
$runMutexAcquired = $false
$currentStage = "initialization"
$toolkitTe2Path = Join-Path $env:LOCALAPPDATA "DigitalTransformationToolkit\tools\TabularEditor2\2.28.0\TabularEditor.exe"
$toolkitDscmdPath = Join-Path $env:LOCALAPPDATA "DigitalTransformationToolkit\tools\DAXStudio\3.5.2\dscmd.exe"
$commonLoaded = $false

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $temp = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Get-LauncherToolkitVersion {
    $versionPath = Join-Path $toolkitRoot "VERSION"
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        $rawValue = Get-Content -LiteralPath $versionPath -Raw
        $value = if ($null -eq $rawValue) { "" } else { ([string]$rawValue).Trim() }
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return "unversioned"
}

function Remove-LauncherStaleFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
}

function New-LauncherFailureException {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$BlockerCode,
        [Parameter(Mandatory = $true)][string]$FailureStage,
        [bool]$Retryable = $false,
        [bool]$RequiresIT = $false,
        [Parameter(Mandatory = $true)][string]$NextAction
    )

    $exception = New-Object System.InvalidOperationException $Message
    $exception.Data["blockerCode"] = $BlockerCode
    $exception.Data["failureStage"] = $FailureStage
    $exception.Data["retryable"] = $Retryable
    $exception.Data["requiresIT"] = $RequiresIT
    $exception.Data["nextAction"] = $NextAction
    return $exception
}

function Get-LauncherFailureMetadata {
    param([Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($commonLoaded -and $null -ne (Get-Command Get-ToolkitFailureMetadata -ErrorAction SilentlyContinue)) {
        return Get-ToolkitFailureMetadata `
            -ErrorObject $ErrorRecord `
            -DefaultBlockerCode "UNCLASSIFIED_FAILURE" `
            -DefaultFailureStage $currentStage `
            -DefaultRetryable $false `
            -DefaultRequiresIT $false `
            -DefaultNextAction "Return the exact blocker and latest.log; do not improvise or bypass policy."
    }

    $exception = $ErrorRecord.Exception
    return [pscustomobject]@{
        blockerCode = if ($exception.Data.Contains("blockerCode")) { [string]$exception.Data["blockerCode"] } else { "UNCLASSIFIED_FAILURE" }
        failureStage = if ($exception.Data.Contains("failureStage")) { [string]$exception.Data["failureStage"] } else { $currentStage }
        retryable = if ($exception.Data.Contains("retryable")) { [bool]$exception.Data["retryable"] } else { $false }
        requiresIT = if ($exception.Data.Contains("requiresIT")) { [bool]$exception.Data["requiresIT"] } else { $false }
        nextAction = if ($exception.Data.Contains("nextAction")) { [string]$exception.Data["nextAction"] } else { "Return the exact blocker and latest.log; do not improvise or bypass policy." }
    }
}

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToUniversalTime().ToString("o"), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host "[START_HERE] $Message"
}

function Write-State {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Stage,
        [string]$LastError,
        [string]$BlockerCode,
        [bool]$Retryable = $false,
        [bool]$RequiresIT = $false,
        [string]$NextAction
    )

    $script:currentStage = $Stage
    $normalizedBlockerCode = if ([string]::IsNullOrWhiteSpace($BlockerCode)) { $null } else { $BlockerCode }
    $normalizedNextAction = if ([string]::IsNullOrWhiteSpace($NextAction)) { $null } else { $NextAction }
    $state = [ordered]@{
        schemaVersion = 2
        runId = $runId
        status = $Status
        stage = $Stage
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        toolkitRoot = $toolkitRoot
        toolkitVersion = (Get-LauncherToolkitVersion)
        pbixName = $resolvedPbixName
        desktopTarget = $desktopTarget
        outputFolder = $outputFolder
        manifestPath = $manifestPath
        resultPath = $resultPath
        logPath = $logPath
        lastError = $LastError
        blockerCode = $normalizedBlockerCode
        retryable = $Retryable
        requiresIT = $RequiresIT
        nextAction = $normalizedNextAction
    }
    Write-JsonAtomic -Path $statePath -Value $state
}

function Write-ToolkitEnvironmentFile {
    param(
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [Parameter(Mandatory = $true)][string]$Te2Path,
        [string]$DscmdPath,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Auto-generated by START_HERE.ps1. Do not store credentials here.") | Out-Null
    $lines.Add("TE2_EXE_PATH=$Te2Path") | Out-Null
    if ($DscmdPath) {
        $lines.Add("DSCMD_EXE_PATH=$DscmdPath") | Out-Null
    }
    else {
        $lines.Add("# DSCMD_EXE_PATH is omitted because DAX Studio is not currently available.") | Out-Null
    }
    $lines.Add("EVIDENCE_ROOT=$EvidenceRoot") | Out-Null
    Set-Content -LiteralPath $EnvPath -Value $lines -Encoding UTF8
}

function Get-WingetPackageExecutables {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePrefix,
        [Parameter(Mandatory = $true)][string]$ExecutableName
    )

    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (-not (Test-Path -LiteralPath $wingetRoot -PathType Container)) {
        return $null
    }

    foreach ($package in @(
        Get-ChildItem -LiteralPath $wingetRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$PackagePrefix*" } |
            Sort-Object FullName
    )) {
        foreach ($match in @(
            Get-ChildItem -LiteralPath $package.FullName -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object FullName
        )) {
            Write-Output $match.FullName
        }
    }
}

function Get-ExternalTe2Paths {
    $candidates = New-Object System.Collections.Generic.List[string]
    $command = Get-Command TabularEditor.exe -ErrorAction SilentlyContinue
    if ($null -ne $command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        $candidates.Add($command.Source) | Out-Null
    }

    $programFilesX86 = [System.Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $programFiles = [System.Environment]::GetEnvironmentVariable("ProgramFiles")
    if ($programFilesX86) { $candidates.Add((Join-Path $programFilesX86 "Tabular Editor\TabularEditor.exe")) | Out-Null }
    if ($programFiles) { $candidates.Add((Join-Path $programFiles "Tabular Editor\TabularEditor.exe")) | Out-Null }
    $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Tabular Editor\TabularEditor.exe")) | Out-Null
    foreach ($wingetPath in @(Get-WingetPackageExecutables -PackagePrefix "TabularEditor.TabularEditor.2" -ExecutableName "TabularEditor.exe")) {
        $candidates.Add($wingetPath) | Out-Null
    }

    $seen = @{}
    foreach ($candidate in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $fullPath = [System.IO.Path]::GetFullPath($candidate)
            if (-not $fullPath.Equals($toolkitTe2Path, [System.StringComparison]::OrdinalIgnoreCase) -and -not $seen.ContainsKey($fullPath)) {
                $seen[$fullPath] = $true
                Write-Output $fullPath
            }
        }
    }
}

function Get-ExternalDscmdPaths {
    $candidates = New-Object System.Collections.Generic.List[string]
    $command = Get-Command dscmd.exe -ErrorAction SilentlyContinue
    if ($null -ne $command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        $candidates.Add($command.Source) | Out-Null
    }

    $programFiles = [System.Environment]::GetEnvironmentVariable("ProgramFiles")
    $programFilesX86 = [System.Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFiles) { $candidates.Add((Join-Path $programFiles "DAX Studio\dscmd.exe")) | Out-Null }
    if ($programFilesX86) { $candidates.Add((Join-Path $programFilesX86 "DAX Studio\dscmd.exe")) | Out-Null }
    $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\DAX Studio\dscmd.exe")) | Out-Null
    foreach ($wingetPath in @(Get-WingetPackageExecutables -PackagePrefix "DaxStudio.DaxStudio" -ExecutableName "dscmd.exe")) {
        $candidates.Add($wingetPath) | Out-Null
    }

    $seen = @{}
    foreach ($candidate in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $fullPath = [System.IO.Path]::GetFullPath($candidate)
            if (-not $fullPath.Equals($toolkitDscmdPath, [System.StringComparison]::OrdinalIgnoreCase) -and -not $seen.ContainsKey($fullPath)) {
                $seen[$fullPath] = $true
                Write-Output $fullPath
            }
        }
    }
}

function Test-DotNetFramework46OrLater {
    # TE2 2.28 requires .NET Framework 4.6+. Modern supported Windows systems
    # normally have a later 4.x runtime. Detect the runtime itself so WinGet
    # does not need to install the Developer Pack dependency merely to run TE2.
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP\v4\Full"
    )
    foreach ($path in $paths) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            if ($null -ne $item.Release -and [int]$item.Release -ge 393295) { return $true }
            if ($null -ne $item.Version) {
                $versionMatch = [regex]::Match([string]$item.Version, '\d+(?:\.\d+){1,3}')
                if ($versionMatch.Success -and [version]$versionMatch.Value -ge [version]"4.6") { return $true }
            }
        }
        catch { }
    }
    return $false
}

function Test-DotNetFramework472OrLater {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP\v4\Full"
    )
    foreach ($path in $paths) {
        try {
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            if ($null -ne $item.Release -and [int]$item.Release -ge 461808) { return $true }
            if ($null -ne $item.Version) {
                $versionMatch = [regex]::Match([string]$item.Version, '\d+(?:\.\d+){1,3}')
                if ($versionMatch.Success -and [version]$versionMatch.Value -ge [version]"4.7.2") { return $true }
            }
        }
        catch { }
    }
    return $false
}

function Test-PolicyBlockText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }
    return ($Text -match '(?i)(blocked by.*policy|group policy|policy restriction|administrator has blocked|AppLocker|WDAC|Windows Defender Application Control|0x800704ec|0x800704c7|error\s*740|elevation required|requested operation requires elevation|UAC|access is denied|unauthorized)')
}

function Get-ToolCandidateAssessment {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$ExpectedFileName,
        [Parameter(Mandatory = $true)][version]$MinimumVersion,
        [Parameter(Mandatory = $true)][string]$ProductName,
        [Parameter(Mandatory = $true)][string]$PublisherRegex,
        [Parameter(Mandatory = $true)][string[]]$SmokeArguments,
        [Parameter(Mandatory = $true)][string]$SmokeMarkerPattern,
        [string]$ExactVersionPrefix
    )

    try {
        Assert-ExecutableFile -Path $Path -VariableName $ProductName -ExpectedFileName $ExpectedFileName
        Assert-MinimumFileVersion `
            -Path $Path `
            -MinimumVersion $MinimumVersion `
            -ProductName $ProductName `
            -PublisherRegex $PublisherRegex
        if (-not [string]::IsNullOrWhiteSpace($ExactVersionPrefix)) {
            $productVersionText = [string](Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
            $productVersionMatch = [regex]::Match($productVersionText, '\d+(?:\.\d+){1,3}')
            if (-not $productVersionMatch.Success -or
                (-not $productVersionMatch.Value.Equals($ExactVersionPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not $productVersionMatch.Value.StartsWith(($ExactVersionPrefix + "."), [System.StringComparison]::OrdinalIgnoreCase))) {
                throw "$ProductName toolkit-owned product version must be $ExactVersionPrefix; found $productVersionText."
            }
        }
        Invoke-ToolkitExecutableSmoke `
            -Path $Path `
            -ProductName $ProductName `
            -Arguments $SmokeArguments `
            -ExpectedMarkerPattern $SmokeMarkerPattern `
            -BlockerCode "TOOL_VALIDATION_FAILED" `
            -FailureStage "tool-readiness" `
            -Retryable $false `
            -RequiresIT $false `
            -NextAction "Use another validated candidate or let START_HERE.ps1 perform its one portable repair attempt." `
            -LogPath $logPath `
            -TimeoutSeconds 15 | Out-Null

        return [pscustomobject]@{
            valid = $true
            path = $Path
            source = $Source
            message = $null
            blockerCode = $null
            retryable = $false
            requiresIT = $false
            nextAction = $null
        }
    }
    catch {
        $metadata = Get-ToolkitFailureMetadata `
            -ErrorObject $_ `
            -DefaultBlockerCode "TOOL_VALIDATION_FAILED" `
            -DefaultFailureStage "tool-readiness" `
            -DefaultRetryable $false `
            -DefaultRequiresIT $false `
            -DefaultNextAction "Use another validated candidate or let START_HERE.ps1 perform its one portable repair attempt."
        if (Test-PolicyBlockText -Text $_.Exception.Message) {
            $metadata.blockerCode = "TOOL_EXECUTION_BLOCKED"
            $metadata.retryable = $false
            $metadata.requiresIT = $true
            $metadata.nextAction = "Send latest.log and the blocked executable path '$Path' to IT; do not bypass policy."
        }
        return [pscustomobject]@{
            valid = $false
            path = $Path
            source = $Source
            message = $_.Exception.Message
            blockerCode = $metadata.blockerCode
            retryable = [bool]$metadata.retryable
            requiresIT = [bool]$metadata.requiresIT
            nextAction = $metadata.nextAction
        }
    }
}

function Write-RejectedToolCandidate {
    param([Parameter(Mandatory = $true)]$Assessment)
    Write-Log ("Rejected {0} candidate '{1}': {2}" -f $Assessment.source, $Assessment.path, $Assessment.message)
}

function Assert-ToolPolicyNotBlocked {
    param(
        [Parameter(Mandatory = $true)][string]$ProductName,
        [Parameter(Mandatory = $true)]$Assessment
    )

    if ($Assessment.requiresIT -or $Assessment.blockerCode -eq "TOOL_EXECUTION_BLOCKED") {
        Throw-FinalToolFailure -ProductName $ProductName -LastFailure $Assessment -RepairAttempted $false
    }
}

function Get-PreferredToolFailure {
    param(
        $Current,
        [Parameter(Mandatory = $true)]$Candidate
    )

    if ($null -ne $Current -and $Current.requiresIT -and -not $Candidate.requiresIT) {
        return $Current
    }
    return $Candidate
}

function Get-ToolErrorAssessment {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Source,
        [string]$Path
    )

    $metadata = Get-ToolkitFailureMetadata `
        -ErrorObject $ErrorRecord `
        -DefaultBlockerCode "TOOL_REPAIR_FAILED" `
        -DefaultFailureStage "tool-readiness" `
        -DefaultRetryable $false `
        -DefaultRequiresIT $false `
        -DefaultNextAction "Return latest.log; do not install unverified software or bypass policy."
    if (Test-PolicyBlockText -Text $ErrorRecord.Exception.Message) {
        $metadata.blockerCode = "TOOL_EXECUTION_BLOCKED"
        $metadata.retryable = $false
        $metadata.requiresIT = $true
        $metadata.nextAction = "Send latest.log and the blocked executable path to IT; do not bypass policy."
    }
    elseif ($ErrorRecord.Exception.Message -match '(?i)requires \.NET Framework') {
        $metadata.blockerCode = "TOOL_REPAIR_FAILED"
        $metadata.retryable = $false
        $metadata.requiresIT = $true
        $metadata.nextAction = "Ask IT to confirm the required .NET Framework runtime is installed; do not launch an elevated installer."
    }
    return [pscustomobject]@{
        valid = $false
        path = $Path
        source = $Source
        message = $ErrorRecord.Exception.Message
        blockerCode = $metadata.blockerCode
        retryable = [bool]$metadata.retryable
        requiresIT = [bool]$metadata.requiresIT
        nextAction = $metadata.nextAction
    }
}

function Throw-FinalToolFailure {
    param(
        [Parameter(Mandatory = $true)][string]$ProductName,
        $LastFailure,
        [bool]$RepairAttempted
    )

    if ($null -ne $LastFailure -and $LastFailure.blockerCode -eq "TOOL_EXECUTION_BLOCKED") {
        Throw-ToolkitFailure `
            -Message "$ProductName execution was blocked. $($LastFailure.message)" `
            -BlockerCode "TOOL_EXECUTION_BLOCKED" `
            -FailureStage "tool-readiness" `
            -Retryable $false `
            -RequiresIT $true `
            -NextAction $LastFailure.nextAction
    }

    if ($null -ne $LastFailure -and $LastFailure.requiresIT) {
        Throw-ToolkitFailure `
            -Message "$ProductName requires an IT-controlled prerequisite. $($LastFailure.message)" `
            -BlockerCode $LastFailure.blockerCode `
            -FailureStage "tool-readiness" `
            -Retryable $false `
            -RequiresIT $true `
            -NextAction $LastFailure.nextAction
    }

    $detail = if ($null -ne $LastFailure -and -not [string]::IsNullOrWhiteSpace([string]$LastFailure.message)) {
        [string]$LastFailure.message
    }
    else {
        "No compatible executable was found."
    }
    $isTransient = $detail -match '(?i)(timed out|temporar|network|download|connection|locked|being used by another process)'
    $blockerCode = if ($RepairAttempted) { "TOOL_REPAIR_FAILED" } else { "TOOL_VALIDATION_FAILED" }
    $nextAction = if ($isTransient) {
        "Wait 30 seconds and confirm no process is locking the toolkit tool directory."
    }
    else {
        "Return latest.log and the rejected tool paths; do not install unverified software or bypass policy."
    }
    Throw-ToolkitFailure `
        -Message "$ProductName is unavailable after bounded validation and repair. $detail" `
        -BlockerCode $blockerCode `
        -FailureStage "tool-readiness" `
        -Retryable $isTransient `
        -RequiresIT $false `
        -NextAction $nextAction
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Version,
        [switch]$SkipDependencies,
        [ValidateRange(30, 900)][int]$TimeoutSeconds = 180
    )

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
    }
    if ($null -eq $winget) {
        return [pscustomobject]@{
            ExitCode = -1
            Output = "winget is not available"
            PolicyBlocked = $false
            Available = $false
        }
    }

    $arguments = @(
        "install",
        "--id", $Id,
        "--exact",
        "--source", "winget",
        "--scope", "user",
        "--silent",
        "--disable-interactivity",
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--version", $Version
    )
    if ($SkipDependencies) {
        $arguments += "--skip-dependencies"
    }

    Write-Log ("winget install attempt: {0}{1}" -f $Id, $(if ($SkipDependencies) { " (skip dependencies)" } else { "" }))
    $attemptId = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $runtimeRoot "winget_${attemptId}.stdout.log"
    $stderrPath = Join-Path $runtimeRoot "winget_${attemptId}.stderr.log"
    try {
        $nativeArguments = @($arguments | ForEach-Object { Quote-NativeArgument -Value ([string]$_) }) -join " "
        $process = Start-Process `
            -FilePath $winget.Source `
            -ArgumentList $nativeArguments `
            -WindowStyle Hidden `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch { }
            $output = "winget timed out after $TimeoutSeconds seconds"
            $exitCode = -2
        }
        else {
            $process.WaitForExit()
            $process.Refresh()
            $exitCode = $process.ExitCode
            $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw | Out-String } else { "" }
            $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw | Out-String } else { "" }
            $output = (@($stderr.Trim(), $stdout.Trim()) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrWhiteSpace($output)) {
        Add-Content -LiteralPath $logPath -Value $output -Encoding UTF8
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
        PolicyBlocked = (Test-PolicyBlockText -Text $output)
        Available = $true
    }
}

function Invoke-VerifiedPortableZipInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$ExecutableName,
        [string]$PublisherRegex,
        [ValidateRange(15, 300)][int]$DownloadTimeoutSeconds = 60
    )

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $downloadRoot = Join-Path $env:TEMP "DigitalTransformationToolkit"
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    $zipPath = Join-Path $downloadRoot (([guid]::NewGuid().ToString("N")) + ".zip")
    $extractTemp = "$Destination.extracting"

    try {
        Write-Log "Downloading official portable $Name package."
        Invoke-WebRequest -Uri $Uri -OutFile $zipPath -UseBasicParsing -TimeoutSec $DownloadTimeoutSeconds
        if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf) -or (Get-Item -LiteralPath $zipPath).Length -le 0) {
            throw "$Name portable download did not produce a non-empty ZIP."
        }

        if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
            $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            if (-not $actualHash.Equals($ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "$Name portable ZIP failed SHA-256 validation."
            }
        }

        if (Test-Path -LiteralPath $extractTemp -PathType Container) {
            Remove-Item -LiteralPath $extractTemp -Recurse -Force
        }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractTemp -Force
        $executable = Get-ChildItem -LiteralPath $extractTemp -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $executable) {
            throw "$Name portable package did not contain $ExecutableName."
        }

        if (-not [string]::IsNullOrWhiteSpace($PublisherRegex)) {
            $signature = Get-AuthenticodeSignature -FilePath $executable.FullName
            if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
                $null -eq $signature.SignerCertificate -or
                $signature.SignerCertificate.Subject -notmatch $PublisherRegex) {
                throw "$Name portable executable failed Authenticode publisher validation."
            }
        }

        if (Test-Path -LiteralPath $Destination -PathType Container) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        Move-Item -LiteralPath $extractTemp -Destination $Destination
        $finalExecutable = Get-ChildItem -LiteralPath $Destination -Filter $ExecutableName -File -Recurse -ErrorAction Stop |
            Select-Object -First 1
        if ($null -eq $finalExecutable) {
            throw "$Name portable executable was not found after installation."
        }
        return $finalExecutable.FullName
    }
    finally {
        if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $extractTemp -PathType Container) {
            Remove-Item -LiteralPath $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-Te2Portable {
    if (-not (Test-DotNetFramework46OrLater)) {
        throw "Tabular Editor 2 requires .NET Framework 4.6 or later. The runtime was not detected, and this zero-touch workflow will not launch an elevated dependency installer."
    }

    $destination = Join-Path $env:LOCALAPPDATA "DigitalTransformationToolkit\tools\TabularEditor2\2.28.0"
    $path = Invoke-VerifiedPortableZipInstall `
        -Name "Tabular Editor 2" `
        -Uri "https://github.com/TabularEditor/TabularEditor/releases/download/2.28.0/TabularEditor.Portable.zip" `
        -Destination $destination `
        -ExpectedSha256 "BA85F4653C850B06687E6E0B3C8AF3D7C951921EC281DEB5DF615B2CE43D4EF2" `
        -ExecutableName "TabularEditor.exe" `
        -PublisherRegex '(?i)Tabular Editor|twoday|Kapacity'
    Assert-MinimumFileVersion -Path $path -MinimumVersion ([version]"2.28.0") -ProductName "Tabular Editor 2" -PublisherRegex '(?i)Tabular Editor|twoday|Kapacity'
    return $path
}

function Get-Te2CandidateAssessment {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Source,
        [bool]$ToolkitOwned = $false
    )

    return Get-ToolCandidateAssessment `
        -Path $Path `
        -Source $Source `
        -ExpectedFileName "TabularEditor.exe" `
        -MinimumVersion ([version]"2.28.0") `
        -ProductName "Tabular Editor 2" `
        -PublisherRegex '(?i)Tabular Editor|twoday|Kapacity' `
        -SmokeArguments @('/?') `
        -SmokeMarkerPattern '(?i)(Tabular\s+Editor\s+2\.28\.0|Usage:)' `
        -ExactVersionPrefix $(if ($ToolkitOwned) { "2.28.0" } else { $null })
}

function Ensure-Te2 {
    $repairAttempted = $false
    $lastFailure = $null
    $toolkitRootPath = Split-Path -Parent $toolkitTe2Path

    if (Test-Path -LiteralPath $toolkitRootPath -PathType Container) {
        $assessment = Get-Te2CandidateAssessment -Path $toolkitTe2Path -Source "toolkit-owned portable TE2" -ToolkitOwned $true
        if ($assessment.valid) {
            Write-Log "Selected validated toolkit-owned Tabular Editor 2: $toolkitTe2Path"
            return $toolkitTe2Path
        }
        Write-RejectedToolCandidate -Assessment $assessment
        Assert-ToolPolicyNotBlocked -ProductName "Tabular Editor 2" -Assessment $assessment
        $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
        $repairAttempted = $true
        try {
            Write-Log "Toolkit-owned Tabular Editor 2 is incomplete or invalid; reinstalling it once from the pinned portable archive."
            $path = Install-Te2Portable
            $assessment = Get-Te2CandidateAssessment -Path $path -Source "repaired toolkit-owned portable TE2" -ToolkitOwned $true
            if ($assessment.valid) {
                $fixes.Add("Reinstalled and revalidated toolkit-owned portable Tabular Editor 2 once") | Out-Null
                return $path
            }
            Write-RejectedToolCandidate -Assessment $assessment
            Assert-ToolPolicyNotBlocked -ProductName "Tabular Editor 2" -Assessment $assessment
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
        }
        catch {
            $repairFailure = Get-ToolErrorAssessment -ErrorRecord $_ -Source "toolkit-owned portable TE2 repair" -Path $toolkitTe2Path
            Write-RejectedToolCandidate -Assessment $repairFailure
            Assert-ToolPolicyNotBlocked -ProductName "Tabular Editor 2" -Assessment $repairFailure
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $repairFailure
        }
    }

    foreach ($candidate in @(Get-ExternalTe2Paths)) {
        $assessment = Get-Te2CandidateAssessment -Path $candidate -Source "external TE2 candidate"
        if ($assessment.valid) {
            Write-Log "Selected validated external Tabular Editor 2: $candidate"
            return $candidate
        }
        Write-RejectedToolCandidate -Assessment $assessment
        Assert-ToolPolicyNotBlocked -ProductName "Tabular Editor 2" -Assessment $assessment
        $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
    }

    if (-not $repairAttempted) {
        try {
            if (-not (Test-DotNetFramework46OrLater)) {
                throw "Tabular Editor 2 requires .NET Framework 4.6 or later. The runtime was not detected. No elevated dependency installer will be launched."
            }

            # The official WinGet package is portable. Try the existing bounded
            # user-scope path once before the pinned direct portable fallback.
            $attempt = Invoke-WingetInstall `
                -Id "TabularEditor.TabularEditor.2" `
                -Version "2.28.0" `
                -SkipDependencies
            if ($attempt.PolicyBlocked) {
                Throw-ToolkitFailure `
                    -Message "Tabular Editor 2 installation was blocked by organizational policy. No security control was changed." `
                    -BlockerCode "TOOL_EXECUTION_BLOCKED" `
                    -FailureStage "tool-readiness" `
                    -Retryable $false `
                    -RequiresIT $true `
                    -NextAction "Send latest.log to IT and request approval for the pinned Tabular Editor 2 executable; do not bypass policy."
            }
            foreach ($candidate in @(Get-ExternalTe2Paths)) {
                $assessment = Get-Te2CandidateAssessment -Path $candidate -Source "post-WinGet TE2 candidate"
                if ($assessment.valid) {
                    $fixes.Add("Installed and validated Tabular Editor 2 through user-scope silent WinGet") | Out-Null
                    return $candidate
                }
                Write-RejectedToolCandidate -Assessment $assessment
                Assert-ToolPolicyNotBlocked -ProductName "Tabular Editor 2" -Assessment $assessment
                $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
            }

            Write-Log "WinGet did not yield a usable TE2 executable; installing the hash-pinned official portable ZIP once with no elevation."
            $repairAttempted = $true
            $path = Install-Te2Portable
            $assessment = Get-Te2CandidateAssessment -Path $path -Source "new toolkit-owned portable TE2" -ToolkitOwned $true
            if ($assessment.valid) {
                $fixes.Add("Installed and validated hash-verified portable Tabular Editor 2 under LOCALAPPDATA") | Out-Null
                return $path
            }
            Write-RejectedToolCandidate -Assessment $assessment
            Assert-ToolPolicyNotBlocked -ProductName "Tabular Editor 2" -Assessment $assessment
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
        }
        catch {
            $installFailure = Get-ToolErrorAssessment -ErrorRecord $_ -Source "Tabular Editor 2 bounded install" -Path $toolkitTe2Path
            Write-RejectedToolCandidate -Assessment $installFailure
            Assert-ToolPolicyNotBlocked -ProductName "Tabular Editor 2" -Assessment $installFailure
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $installFailure
        }
    }

    Throw-FinalToolFailure -ProductName "Tabular Editor 2" -LastFailure $lastFailure -RepairAttempted $repairAttempted
}

function Install-DaxStudioPortable {
    if (-not (Test-DotNetFramework472OrLater)) {
        throw "DAX Studio 3.5.2 requires .NET Framework 4.7.2 or later. No elevated dependency installer will be launched."
    }

    $destination = Join-Path $env:LOCALAPPDATA "DigitalTransformationToolkit\tools\DAXStudio\3.5.2"
    $path = Invoke-VerifiedPortableZipInstall `
        -Name "DAX Studio" `
        -Uri "https://github.com/DaxStudio/DaxStudio/releases/download/v3.5.2/DaxStudio_3_5_2_portable.zip" `
        -Destination $destination `
        -ExpectedSha256 "2C28F7264452E143490EC5FE8ACA2B64D15080CB9BB2B65C71D6A14B5B639BBE" `
        -ExecutableName "dscmd.exe" `
        -PublisherRegex '(?i)SQL\s*BI|SQLBI'
    Assert-MinimumFileVersion -Path $path -MinimumVersion ([version]"3.3.0") -ProductName "DAX Studio" -PublisherRegex '(?i)SQL\s*BI|SQLBI'
    return $path
}

function Get-DaxCandidateAssessment {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Source,
        [bool]$ToolkitOwned = $false
    )

    return Get-ToolCandidateAssessment `
        -Path $Path `
        -Source $Source `
        -ExpectedFileName "dscmd.exe" `
        -MinimumVersion ([version]"3.3.0") `
        -ProductName "DAX Studio" `
        -PublisherRegex '(?i)SQL\s*BI|SQLBI' `
        -SmokeArguments @('--help') `
        -SmokeMarkerPattern '(?i)(DSCMD\s+v?3\.5\.2|Usage:)' `
        -ExactVersionPrefix $(if ($ToolkitOwned) { "3.5.2" } else { $null })
}

function Ensure-DaxStudio {
    if ($SkipDaxStudio) {
        Write-Log "DAX Studio readiness intentionally skipped for a metadata-only task."
        return $null
    }

    $repairAttempted = $false
    $lastFailure = $null
    $toolkitRootPath = Split-Path -Parent $toolkitDscmdPath

    if (Test-Path -LiteralPath $toolkitRootPath -PathType Container) {
        $assessment = Get-DaxCandidateAssessment -Path $toolkitDscmdPath -Source "toolkit-owned portable DAX Studio" -ToolkitOwned $true
        if ($assessment.valid) {
            Write-Log "Selected validated toolkit-owned DAX Studio: $toolkitDscmdPath"
            return $toolkitDscmdPath
        }
        Write-RejectedToolCandidate -Assessment $assessment
        Assert-ToolPolicyNotBlocked -ProductName "DAX Studio" -Assessment $assessment
        $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
        $repairAttempted = $true
        try {
            Write-Log "Toolkit-owned DAX Studio is incomplete or invalid; reinstalling it once from the pinned portable archive."
            $path = Install-DaxStudioPortable
            $assessment = Get-DaxCandidateAssessment -Path $path -Source "repaired toolkit-owned portable DAX Studio" -ToolkitOwned $true
            if ($assessment.valid) {
                $fixes.Add("Reinstalled and revalidated toolkit-owned portable DAX Studio once") | Out-Null
                return $path
            }
            Write-RejectedToolCandidate -Assessment $assessment
            Assert-ToolPolicyNotBlocked -ProductName "DAX Studio" -Assessment $assessment
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
        }
        catch {
            $repairFailure = Get-ToolErrorAssessment -ErrorRecord $_ -Source "toolkit-owned portable DAX Studio repair" -Path $toolkitDscmdPath
            Write-RejectedToolCandidate -Assessment $repairFailure
            Assert-ToolPolicyNotBlocked -ProductName "DAX Studio" -Assessment $repairFailure
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $repairFailure
        }
    }

    foreach ($candidate in @(Get-ExternalDscmdPaths)) {
        $assessment = Get-DaxCandidateAssessment -Path $candidate -Source "external DAX Studio candidate"
        if ($assessment.valid) {
            Write-Log "Selected validated external DAX Studio: $candidate"
            return $candidate
        }
        Write-RejectedToolCandidate -Assessment $assessment
        Assert-ToolPolicyNotBlocked -ProductName "DAX Studio" -Assessment $assessment
        $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
    }

    if (-not $repairAttempted) {
        try {
            Write-Log "DAX Studio not found/current; installing the official portable release once under LOCALAPPDATA (no UAC/admin install)."
            $repairAttempted = $true
            $path = Install-DaxStudioPortable
            $assessment = Get-DaxCandidateAssessment -Path $path -Source "new toolkit-owned portable DAX Studio" -ToolkitOwned $true
            if ($assessment.valid) {
                $fixes.Add("Installed and validated signed portable DAX Studio under LOCALAPPDATA") | Out-Null
                return $path
            }
            Write-RejectedToolCandidate -Assessment $assessment
            Assert-ToolPolicyNotBlocked -ProductName "DAX Studio" -Assessment $assessment
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $assessment
        }
        catch {
            $installFailure = Get-ToolErrorAssessment -ErrorRecord $_ -Source "DAX Studio bounded install" -Path $toolkitDscmdPath
            Write-RejectedToolCandidate -Assessment $installFailure
            Assert-ToolPolicyNotBlocked -ProductName "DAX Studio" -Assessment $installFailure
            $lastFailure = Get-PreferredToolFailure -Current $lastFailure -Candidate $installFailure
        }
    }

    try {
        Throw-FinalToolFailure -ProductName "DAX Studio" -LastFailure $lastFailure -RepairAttempted $repairAttempted
    }
    catch {
        $metadata = Get-ToolkitFailureMetadata -ErrorObject $_ -DefaultFailureStage "tool-readiness"
        $message = "DAX Studio is unavailable after bounded validation and repair. Core PBIX metadata extraction can still run with TE2. $($_.Exception.Message)"
        if ($RequireDaxStudio) {
            if ($metadata.blockerCode -eq "TOOL_EXECUTION_BLOCKED") { throw $_.Exception }
            Throw-ToolkitFailure `
                -Message $message `
                -BlockerCode "DAX_REQUIRED_UNAVAILABLE" `
                -FailureStage "tool-readiness" `
                -Retryable ([bool]$metadata.retryable) `
                -RequiresIT ([bool]$metadata.requiresIT) `
                -NextAction $metadata.nextAction
        }
        $warnings.Add($message) | Out-Null
        return $null
    }
}

function Write-FinalResult {
    param(
        [Parameter(Mandatory = $true)][string]$Result,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string]$Blocker,
        [string]$Status,
        [string]$BlockerCode,
        [bool]$Retryable = $false,
        [bool]$RequiresIT = $false,
        [string]$NextAction
    )

    $artifactCounts = $null
    $normalizedBlockerCode = if ([string]::IsNullOrWhiteSpace($BlockerCode)) { $null } else { $BlockerCode }
    $normalizedNextAction = if ([string]::IsNullOrWhiteSpace($NextAction)) { $null } else { $NextAction }
    if ($manifestPath -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $artifactCounts = @($manifest.artifacts | ForEach-Object {
                [ordered]@{ name = $_.name; rowCount = $_.rowCount }
            })
        }
        catch {
            $artifactCounts = $null
        }
    }

    $resultObject = [ordered]@{
        schemaVersion = 2
        runId = $runId
        result = $Result
        status = $Status
        exitCode = $ExitCode
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        toolkitVersion = (Get-LauncherToolkitVersion)
        toolkitRoot = $toolkitRoot
        pbixName = $resolvedPbixName
        desktopTarget = $desktopTarget
        capabilities = [ordered]@{
            metadataInventory = ($null -ne $te2Path)
            daxQueries = ($null -ne $dscmdPath)
            reportContext = if ($null -ne $desktopTarget -and $desktopTarget.DiscoverySource -eq "desktop-bridge") {
                "desktop-bridge-file-identity-only"
            } else {
                "semantic-model-only"
            }
        }
        outputFolder = $outputFolder
        manifestPath = $manifestPath
        statePath = $statePath
        logPath = $logPath
        fixes = @($fixes)
        warnings = @($warnings)
        artifactCounts = $artifactCounts
        blocker = $Blocker
        blockerCode = $normalizedBlockerCode
        retryable = $Retryable
        requiresIT = $RequiresIT
        nextAction = $normalizedNextAction
    }
    Write-JsonAtomic -Path $resultPath -Value $resultObject

    $displayArguments = New-Object System.Collections.Generic.List[string]
    if ($resolvedPbixName) { $displayArguments.Add("-PbixName `"$resolvedPbixName`"") | Out-Null }
    if ($SkipDaxStudio) { $displayArguments.Add("-SkipDaxStudio") | Out-Null }
    if ($RequireDaxStudio) { $displayArguments.Add("-RequireDaxStudio") | Out-Null }
    if ($SetupOnly) { $displayArguments.Add("-SetupOnly") | Out-Null }
    $displaySuffix = if ($displayArguments.Count -gt 0) { " " + (@($displayArguments) -join " ") } else { "" }
    Write-Host ("Command: powershell.exe -NoProfile -File `"{0}`"{1}" -f (Join-Path $toolkitRoot "START_HERE.ps1"), $displaySuffix)
    Write-Host "ExitCode: $ExitCode"
    Write-Host ("Fixes: {0}" -f $(if ($fixes.Count -gt 0) { @($fixes) -join "; " } else { "none" }))
    Write-Host ("OutputFolder: {0}" -f $(if ($outputFolder) { $outputFolder } else { "" }))
    Write-Host "Result: $Result"
    Write-Host ("Blocker: {0}" -f $(if ($Blocker) { $Blocker } else { "" }))
    Write-Host "StateFile: $statePath"
    Write-Host "LogFile: $logPath"
    Write-Host "ResultFile: $resultPath"
}

# Prevent concurrent launchers from racing on shared state, .env, downloads,
# evidence outputs, or portable-tool destinations.
$createdNew = $false
$runMutex = New-Object System.Threading.Mutex($false, "Local\DigitalTransformationToolkit.START_HERE", [ref]$createdNew)
try {
    $runMutexAcquired = $runMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    $runMutexAcquired = $true
}
if (-not $runMutexAcquired) {
    [Console]::Error.WriteLine("BLOCKER: Another Digital Transformation Toolkit run is already active. Wait for it to finish and retry.")
    $runMutex.Dispose()
    exit 2
}

# Capture the old state before binding shared evidence to this runId. Only a
# genuinely non-terminal prior run is reported as interrupted.
$previousState = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try { $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $previousState = $null }
}

# Invalidate prior success evidence immediately after the concurrency guard is
# acquired. Writing the new runId first makes an older result non-authoritative
# even if result.json is locked and cannot be deleted.
try {
    Write-State -Status "running" -Stage "result-invalidation"
    Remove-LauncherStaleFile -Path $resultPath
}
catch {
    $invalidationError = "Unable to invalidate prior success evidence: $($_.Exception.Message)"
    $nextAction = "Close any process holding result.json and preserve the mismatched state/result runIds as failure evidence."
    try { Remove-LauncherStaleFile -Path $resultPath } catch { }
    try {
        Write-State `
            -Status "failed" `
            -Stage "result-invalidation-failed" `
            -LastError $invalidationError `
            -BlockerCode "RESULT_INVALIDATION_FAILED" `
            -Retryable $false `
            -RequiresIT $false `
            -NextAction $nextAction
    }
    catch { }
    [Console]::Error.WriteLine("BLOCKER: $invalidationError")
    try { $runMutex.ReleaseMutex() } catch { }
    $runMutex.Dispose()
    exit 1
}

try {
    try {
        Set-Content -LiteralPath $logPath -Value "" -Encoding UTF8
        if ($null -ne $previousState) {
            $previousStatus = $previousState.PSObject.Properties["status"]
            $previousStage = $previousState.PSObject.Properties["stage"]
            $previousRunId = $previousState.PSObject.Properties["runId"]
            if ($null -ne $previousStatus -and [string]$previousStatus.Value -eq "running") {
                $stageText = if ($null -ne $previousStage) { [string]$previousStage.Value } else { "unknown" }
                $runIdText = if ($null -ne $previousRunId) { [string]$previousRunId.Value } else { "unknown" }
                Write-Log "Previous run '$runIdText' was interrupted at stage '$stageText'; re-validating idempotently."
            }
        }
    }
    catch {
        throw (New-LauncherFailureException `
            -Message "Unable to initialize latest.log: $($_.Exception.Message)" `
            -BlockerCode "UNCLASSIFIED_FAILURE" `
            -FailureStage "runtime-validation" `
            -Retryable $false `
            -RequiresIT $false `
            -NextAction "Close any process holding latest.log, then report the state.json blocker without treating an older result as current.")
    }

    try {
        if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) {
            throw "Toolkit is incomplete. Missing powershell\common.ps1"
        }
        . $commonPath
        $commonLoaded = $true
    }
    catch {
        throw (New-LauncherFailureException `
            -Message $_.Exception.Message `
            -BlockerCode "PACKAGE_VALIDATION_FAILED" `
            -FailureStage "runtime-validation" `
            -Retryable $false `
            -RequiresIT $false `
            -NextAction "Stop and obtain a fresh copy of the authoritative RC2 package; do not run an incomplete toolkit.")
    }

    if ($SkipDaxStudio -and $RequireDaxStudio) {
        throw (New-LauncherFailureException `
            -Message "Use either -SkipDaxStudio or -RequireDaxStudio, not both." `
            -BlockerCode "UNCLASSIFIED_FAILURE" `
            -FailureStage "runtime-validation" `
            -Retryable $false `
            -RequiresIT $false `
            -NextAction "Choose -SkipDaxStudio for metadata or -RequireDaxStudio for calculations, then start a new run.")
    }

    Write-State -Status "running" -Stage "runtime-validation"
    try {
        Assert-ToolkitRuntimeFilesPresent
        Assert-ToolkitExecutionFilesClean
    }
    catch {
        Throw-ToolkitFailure `
            -Message $_.Exception.Message `
            -BlockerCode "PACKAGE_VALIDATION_FAILED" `
            -FailureStage "runtime-validation" `
            -Retryable $false `
            -RequiresIT $false `
            -NextAction "Stop and obtain a fresh copy of the authoritative RC2 package; do not run modified toolkit files."
    }
    Write-Log "Toolkit runtime files validated."

    Write-State -Status "running" -Stage "tool-discovery"
    $te2Path = Ensure-Te2
    Assert-ExecutableFile -Path $te2Path -VariableName "TE2_EXE_PATH" -ExpectedFileName "TabularEditor.exe"
    Assert-MinimumFileVersion -Path $te2Path -MinimumVersion ([version]"2.28.0") -ProductName "Tabular Editor 2" -PublisherRegex '(?i)Tabular Editor|twoday|Kapacity'
    Write-Log "Tabular Editor 2 ready: $te2Path"

    $dscmdPath = Ensure-DaxStudio
    if ($dscmdPath) {
        Assert-ExecutableFile -Path $dscmdPath -VariableName "DSCMD_EXE_PATH" -ExpectedFileName "dscmd.exe"
        Assert-MinimumFileVersion -Path $dscmdPath -MinimumVersion ([version]"3.3.0") -ProductName "DAX Studio" -PublisherRegex '(?i)SQL\s*BI|SQLBI'
        Write-Log "DAX Studio ready: $dscmdPath"
    }

    Write-State -Status "running" -Stage "environment-configuration"
    $envPath = Join-Path $toolkitRoot ".env"
    $evidenceRoot = Join-Path $env:USERPROFILE "PowerBI-Evidence"
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    Write-ToolkitEnvironmentFile `
        -EnvPath $envPath `
        -Te2Path $te2Path `
        -DscmdPath $dscmdPath `
        -EvidenceRoot $evidenceRoot
    $fixes.Add("Regenerated .env with validated local tool paths") | Out-Null

    Write-State -Status "running" -Stage "preflight"
    $preflightScript = Join-Path $toolkitRoot "powershell\test_toolkit_setup.ps1"
    if ($dscmdPath) {
        & $preflightScript -EnvPath $envPath -LogPath $logPath -SkipToolSmoke
    }
    else {
        & $preflightScript -InventoryOnly -EnvPath $envPath -LogPath $logPath -SkipToolSmoke
    }
    Write-Log "Preflight passed."

    if ($SetupOnly) {
        Write-State -Status "succeeded" -Stage "ready-no-model"
        Write-FinalResult -Result "PASS" -ExitCode 0 -Status "ready-no-model" -Blocker ""
        exit 0
    }

    Write-State -Status "running" -Stage "pbix-discovery"
    try {
        $openTargets = @(Get-PowerBIDesktopTargets)
    }
    catch {
        Throw-ToolkitFailure `
            -Message $_.Exception.Message `
            -BlockerCode "PBIX_CONNECTION_FAILED" `
            -FailureStage "pbix-discovery" `
            -Retryable $true `
            -RequiresIT $false `
            -NextAction "Keep Power BI Desktop open and wait for the model to finish loading."
    }
    if ([string]::IsNullOrWhiteSpace($PbixName)) {
        if ($openTargets.Count -eq 0) {
            $warnings.Add("Environment is ready, but no Power BI Desktop PBIX is open. Open a PBIX and run START_HERE.ps1 again.") | Out-Null
            Write-State -Status "succeeded" -Stage "ready-no-model"
            Write-FinalResult -Result "PASS" -ExitCode 0 -Status "ready-no-model" -Blocker ""
            exit 0
        }
        if ($openTargets.Count -gt 1) {
            $labels = @(
                $openTargets | ForEach-Object {
                    if ($_.CurrentFilePath) { "$($_.PbixName) [$($_.CurrentFilePath)]" } else { [string]$_.PbixName }
                }
            )
            Throw-ToolkitFailure `
                -Message "Multiple Power BI Desktop files are open: $($labels -join '; '). Re-run with -PbixName only when that filename is unique; otherwise close one copy." `
                -BlockerCode "PBIX_TARGET_INVALID" `
                -FailureStage "pbix-discovery" `
                -Retryable $false `
                -RequiresIT $false `
                -NextAction "Close unrelated Power BI Desktop files or provide one unique -PbixName, then rerun."
        }
        $desktopTarget = $openTargets[0]
        $resolvedPbixName = [string]$desktopTarget.PbixName
        Write-Log "Auto-detected PBIX: $resolvedPbixName (source: $($desktopTarget.DiscoverySource))"
    }
    else {
        try {
            $resolvedPbixName = Normalize-PbixName -PbixName $PbixName
        }
        catch {
            Throw-ToolkitFailure `
                -Message $_.Exception.Message `
                -BlockerCode "PBIX_TARGET_INVALID" `
                -FailureStage "pbix-discovery" `
                -Retryable $false `
                -RequiresIT $false `
                -NextAction "Provide only the exact open PBIX filename, including .pbix, with no folder path."
        }
        $sameNameTargets = @(
            $openTargets | Where-Object { $_.PbixName.Equals($resolvedPbixName, [System.StringComparison]::OrdinalIgnoreCase) }
        )
        if ($sameNameTargets.Count -gt 1) {
            Throw-ToolkitFailure `
                -Message "More than one open Power BI Desktop process has filename '$resolvedPbixName'. Close one copy before continuing." `
                -BlockerCode "PBIX_TARGET_INVALID" `
                -FailureStage "pbix-discovery" `
                -Retryable $false `
                -RequiresIT $false `
                -NextAction "Close duplicate copies of '$resolvedPbixName', leave exactly one open, then rerun."
        }
        if ($sameNameTargets.Count -eq 1) { $desktopTarget = $sameNameTargets[0] }
        Write-Log "Using requested PBIX: $resolvedPbixName"
    }

    $inventorySafeName = Get-SafeArtifactName -Value ([System.IO.Path]::GetFileNameWithoutExtension($resolvedPbixName))
    $inventoryRunName = "inventory_{0}_{1}" -f $inventorySafeName, (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
    $outputFolder = Join-Path $evidenceRoot $inventoryRunName
    Write-State -Status "running" -Stage "metadata-extraction"
    $inventoryScript = Join-Path $toolkitRoot "powershell\run_model_inventory.ps1"
    try {
        $manifestPath = & $inventoryScript -PbixName $resolvedPbixName -OutDir $outputFolder -EnvPath $envPath
    }
    catch {
        $inventoryMessage = $_.Exception.Message
        if ($inventoryMessage -match '(?i)(PBIX-name connection failed|local port/catalog fallback failed|could not uniquely resolve PBIX|no local Power BI Desktop model|wait for it to finish loading)') {
            Throw-ToolkitFailure `
                -Message $inventoryMessage `
                -BlockerCode "PBIX_CONNECTION_FAILED" `
                -FailureStage "metadata-extraction" `
                -Retryable $true `
                -RequiresIT $false `
                -NextAction "Wait for '$resolvedPbixName' to finish loading in Power BI Desktop."
        }
        Throw-ToolkitFailure `
            -Message $inventoryMessage `
            -BlockerCode "INVENTORY_FAILED" `
            -FailureStage "metadata-extraction" `
            -Retryable $true `
            -RequiresIT $false `
            -NextAction "Keep the same PBIX open and retain latest.log plus the TE2 stdout/stderr logs."
    }

    try {
    if ([string]::IsNullOrWhiteSpace($manifestPath) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "inventory_manifest.json was not produced."
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.status -ne "succeeded") {
        throw "Inventory manifest status is '$($manifest.status)', not succeeded."
    }
    if ([string]$manifest.toolkitCommit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "Inventory manifest did not record a valid toolkitCommit."
    }

    $expectedArtifactNames = @("tables.csv", "measures.csv", "columns.csv", "relationships.csv", "partitions.csv", "expressions.csv")
    $actualArtifactNames = @($manifest.artifacts | ForEach-Object { [string]$_.name })
    $uniqueArtifactNames = @($actualArtifactNames | Sort-Object -Unique)
    if (@($manifest.artifacts).Count -ne 6 -or
        $uniqueArtifactNames.Count -ne 6 -or
        (@($expectedArtifactNames | Sort-Object) -join '|') -ne (@($actualArtifactNames | Sort-Object) -join '|')) {
        throw "Inventory manifest did not contain the exact six expected metadata artifacts."
    }

    foreach ($artifact in @($manifest.artifacts)) {
        $artifactName = [string]$artifact.name
        if ([System.IO.Path]::GetFileName($artifactName) -ne $artifactName) {
            throw "Manifest contains an unsafe artifact name: $artifactName"
        }
        if ([string]$artifact.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Manifest contains an invalid SHA-256 value for $artifactName"
        }
        $artifactPath = Join-Path (Split-Path -Parent $manifestPath) $artifactName
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "Manifest references a missing artifact: $artifactName"
        }
        if ((Get-Item -LiteralPath $artifactPath).Length -le 0) {
            throw "Manifest references an empty artifact: $artifactName"
        }
        $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
        if (-not $artifactHash.Equals([string]$artifact.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest hash does not match artifact: $artifactName"
        }
    }
    }
    catch {
        Throw-ToolkitFailure `
            -Message $_.Exception.Message `
            -BlockerCode "OUTPUT_VALIDATION_FAILED" `
            -FailureStage "output-validation" `
            -Retryable $true `
            -RequiresIT $false `
            -NextAction "Discard this run's output folder and retain latest.log plus inventory_manifest.json."
    }

    $outputFolder = Split-Path -Parent $manifestPath
    Write-Log "Metadata extraction and manifest validation passed."
    Write-State -Status "succeeded" -Stage "complete"
    Write-FinalResult -Result "PASS" -ExitCode 0 -Status "complete" -Blocker ""
    exit 0
}
catch {
    $message = $_.Exception.Message
    $metadata = Get-LauncherFailureMetadata -ErrorRecord $_
    try { Write-Log "FAIL: $message" } catch { [Console]::Error.WriteLine("BLOCKER: $message") }
    try {
        Write-State `
            -Status "failed" `
            -Stage $metadata.failureStage `
            -LastError $message `
            -BlockerCode $metadata.blockerCode `
            -Retryable ([bool]$metadata.retryable) `
            -RequiresIT ([bool]$metadata.requiresIT) `
            -NextAction $metadata.nextAction
    }
    catch { [Console]::Error.WriteLine("BLOCKER: Unable to write state.json: $($_.Exception.Message)") }
    try {
        Write-FinalResult `
            -Result "FAIL" `
            -ExitCode 1 `
            -Status "failed" `
            -Blocker $message `
            -BlockerCode $metadata.blockerCode `
            -Retryable ([bool]$metadata.retryable) `
            -RequiresIT ([bool]$metadata.requiresIT) `
            -NextAction $metadata.nextAction
    }
    catch { [Console]::Error.WriteLine("BLOCKER: Unable to write result.json: $($_.Exception.Message)") }
    exit 1
}
finally {
    if ($runMutexAcquired -and $null -ne $runMutex) {
        try { $runMutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $runMutex) { $runMutex.Dispose() }
}
