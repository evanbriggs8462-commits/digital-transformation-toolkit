Set-StrictMode -Version 2.0

$script:ToolkitRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Get-ToolkitRoot {
    return $script:ToolkitRoot
}

function Get-ToolkitVersion {
    $versionPath = Join-Path $script:ToolkitRoot "VERSION"
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        $value = (Get-Content -LiteralPath $versionPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    return "unversioned"
}

function Get-ToolkitPackageManifestPath {
    return (Join-Path $script:ToolkitRoot "package_manifest.json")
}

function Test-ToolkitPackageMode {
    return (Test-Path -LiteralPath (Get-ToolkitPackageManifestPath) -PathType Leaf)
}

function Assert-ToolkitPackageIntegrity {
    $manifestPath = Get-ToolkitPackageManifestPath
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "package_manifest.json not found. Re-download the toolkit package."
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($null -eq $manifest.files -or @($manifest.files).Count -eq 0) {
        throw "package_manifest.json does not list runtime files. Re-download the toolkit package."
    }
    if ([string]$manifest.sourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "package_manifest.json does not contain a valid sourceCommit. Re-download the toolkit package."
    }
    if (-not ([string]$manifest.toolkitVersion).Equals((Get-ToolkitVersion), [System.StringComparison]::Ordinal)) {
        throw "package_manifest.json toolkitVersion does not match VERSION. Re-download the toolkit package."
    }

    $manifestPaths = @($manifest.files | ForEach-Object { ([string]$_.path).Replace('\', '/') })
    $duplicateManifestPaths = @($manifestPaths | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($duplicateManifestPaths.Count -gt 0) {
        throw "package_manifest.json contains duplicate file paths. Re-download the toolkit package."
    }

    foreach ($entry in @($manifest.files)) {
        $relative = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "package_manifest.json contains an unsafe path."
        }
        if ([string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "package_manifest.json contains an invalid SHA-256 value for $relative."
        }
        $filePath = Join-Path $script:ToolkitRoot $relative
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Runtime file is missing: $relative. Re-download the toolkit package."
        }
        $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
        if (-not $actual.Equals([string]$entry.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Runtime file failed integrity validation: $relative. Re-download the toolkit package."
        }
    }

    $listedPaths = $manifestPaths
    $unexpectedExecutionFiles = @(
        Get-ChildItem -LiteralPath $script:ToolkitRoot -File -Recurse -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.ps1', '.csx', '.dax') } |
            ForEach-Object {
                $_.FullName.Substring($script:ToolkitRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            } |
            Where-Object { $listedPaths -notcontains $_ }
    )
    if ($unexpectedExecutionFiles.Count -gt 0) {
        throw "Unexpected executable toolkit content is present: $($unexpectedExecutionFiles -join ', '). Re-download the toolkit package."
    }
}

function Get-ToolkitPackManifestPath {
    return (Join-Path $script:ToolkitRoot "pack_manifest.json")
}

function Test-ToolkitPackMode {
    return (Test-Path -LiteralPath (Get-ToolkitPackManifestPath) -PathType Leaf)
}

function Test-ToolkitGitRepository {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        return $false
    }

    & $gitCommand.Source -C $script:ToolkitRoot rev-parse --is-inside-work-tree 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Import-ToolkitEnvironment {
    [CmdletBinding()]
    param([string]$EnvPath)

    if ([string]::IsNullOrWhiteSpace($EnvPath)) {
        $EnvPath = Join-Path $script:ToolkitRoot ".env"
    }
    elseif (-not [System.IO.Path]::IsPathRooted($EnvPath)) {
        $EnvPath = Join-Path $script:ToolkitRoot $EnvPath
    }

    $EnvPath = [System.IO.Path]::GetFullPath($EnvPath)
    if (-not (Test-Path -LiteralPath $EnvPath -PathType Leaf)) {
        throw ".env not found. Run START_HERE.ps1 to create and repair it automatically."
    }

    $allowedNames = @("TE2_EXE_PATH", "DSCMD_EXE_PATH", "EVIDENCE_ROOT")
    foreach ($allowedName in $allowedNames) {
        [System.Environment]::SetEnvironmentVariable($allowedName, $null, "Process")
    }
    foreach ($line in Get-Content -LiteralPath $EnvPath) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }

        $separator = $trimmed.IndexOf("=")
        if ($separator -lt 1) {
            throw "Invalid .env entry. Expected NAME=value."
        }

        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment variable name in .env."
        }
        if ($allowedNames -notcontains $name) {
            throw "Unsupported .env entry: $name. Only local tool and evidence paths are allowed."
        }

        if ($value.Length -ge 2) {
            $first = $value.Substring(0, 1)
            $last = $value.Substring($value.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        $value = [System.Environment]::ExpandEnvironmentVariables($value)
        [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function Resolve-ToolkitInputPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $script:ToolkitRoot $Path
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Resolve-ToolkitOutputPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        throw "Output paths must be absolute and outside the toolkit folder."
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = $script:ToolkitRoot.TrimEnd([char[]]@('\', '/'))
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar

    if (Test-ToolkitPackMode) {
        $outputsPrefix = (Join-Path $root "outputs") + [System.IO.Path]::DirectorySeparatorChar
        if ($fullPath.StartsWith($outputsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $fullPath
        }
    }

    if ($fullPath.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Output path must be outside the toolkit folder: $fullPath"
    }

    return $fullPath
}

function Get-ConfiguredEvidenceRoot {
    if ([string]::IsNullOrWhiteSpace($env:EVIDENCE_ROOT)) {
        throw "EVIDENCE_ROOT is missing from .env. Run START_HERE.ps1."
    }

    return Resolve-ToolkitOutputPath -Path $env:EVIDENCE_ROOT
}

function Assert-ExecutableFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$VariableName,
        [string]$ExpectedFileName
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$VariableName is missing from .env."
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$VariableName does not point to an executable file: $Path"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedFileName) -and
        -not [System.IO.Path]::GetFileName($Path).Equals(
            $ExpectedFileName,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "$VariableName must point to $ExpectedFileName."
    }
}

function Assert-ToolkitPackIntegrity {
    $manifestPath = Get-ToolkitPackManifestPath
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "pack_manifest.json not found. Regenerate the pack."
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($null -eq $manifest.files -or @($manifest.files).Count -eq 0) {
        throw "pack_manifest.json does not list pinned files."
    }

    foreach ($entry in @($manifest.files)) {
        $filePath = Join-Path $script:ToolkitRoot $entry.path
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Pack file is missing: $($entry.path)."
        }

        $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
        if ($actual -ne $entry.sha256) {
            throw "Pack file was modified after generation: $($entry.path)."
        }
    }
}

function Assert-ToolkitExecutionFilesClean {
    if (Test-ToolkitPackageMode) {
        Assert-ToolkitPackageIntegrity
        return
    }
    if (Test-ToolkitPackMode) {
        Assert-ToolkitPackIntegrity
        return
    }

    # An unpackaged development folder does not require Git unless explicitly
    # requested. Production SharePoint builds contain package_manifest.json.
    $enforce = [System.Environment]::GetEnvironmentVariable("TOOLKIT_ENFORCE_GIT_CLEAN", "Process")
    if ($enforce -ne "1") {
        return
    }

    if (-not (Test-ToolkitGitRepository)) {
        throw "TOOLKIT_ENFORCE_GIT_CLEAN=1 but this folder is not a Git checkout."
    }

    $gitCommand = Get-Command git -ErrorAction Stop
    $statusOutput = @(
        & $gitCommand.Source `
            -C $script:ToolkitRoot `
            status `
            --porcelain `
            --untracked-files=all `
            -- `
            powershell `
            te2/readonly `
            dax/queries/connection_test.dax 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify toolkit execution files with Git."
    }
    if ($statusOutput.Count -gt 0) {
        throw "Toolkit execution files differ from the checked-out commit. Restore or review them before running."
    }
}

function Assert-ToolkitRuntimeFilesPresent {
    $required = @(
        "powershell\common.ps1",
        "powershell\invoke_te2_readonly.ps1",
        "powershell\run_model_inventory.ps1",
        "powershell\run_dax_query_any_model.ps1",
        "powershell\test_toolkit_setup.ps1",
        "te2\readonly\export_model_inventory.csx",
        "dax\queries\connection_test.dax",
        "templates\.env.example"
    )

    foreach ($relative in $required) {
        $path = Join-Path $script:ToolkitRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required toolkit file is missing: $relative"
        }
    }
}

function Assert-MinimumFileVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][version]$MinimumVersion,
        [Parameter(Mandatory = $true)][string]$ProductName,
        [string]$PublisherRegex
    )

    $installedVersion = [version](Get-ExecutableFileVersion -Path $Path -ProductName $ProductName)
    if ($installedVersion -lt $MinimumVersion) {
        throw "$ProductName $MinimumVersion or later is required; found $installedVersion."
    }

    if (-not [string]::IsNullOrWhiteSpace($PublisherRegex)) {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
            $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch $PublisherRegex) {
            throw "$ProductName failed Authenticode publisher validation."
        }
    }
}

function Get-ExecutableFileVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ProductName
    )

    $versionText = (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
    $match = [regex]::Match([string]$versionText, '\d+(?:\.\d+){1,3}')
    if (-not $match.Success) {
        throw "Unable to verify the $ProductName version."
    }

    return $match.Value
}

function Get-ToolkitCommit {
    if (Test-ToolkitPackageMode) {
        $manifest = Get-Content -LiteralPath (Get-ToolkitPackageManifestPath) -Raw | ConvertFrom-Json
        $sourceCommit = [string]$manifest.sourceCommit
        if ($sourceCommit -match '^[0-9a-fA-F]{40}$') {
            return $sourceCommit.ToLowerInvariant()
        }
        return $null
    }

    if (Test-ToolkitPackMode) {
        $manifest = Get-Content -LiteralPath (Get-ToolkitPackManifestPath) -Raw | ConvertFrom-Json
        $sourceCommit = [string]$manifest.sourceCommit
        if ($sourceCommit -match '^[0-9a-fA-F]{40}$') {
            return $sourceCommit.ToLowerInvariant()
        }
        return $null
    }

    if (-not (Test-ToolkitGitRepository)) {
        return $null
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        return $null
    }

    $commit = (& $gitCommand.Source -C $script:ToolkitRoot rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-fA-F]{40}$') {
        return $null
    }

    return $commit.ToLowerInvariant()
}

function Quote-NativeArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value.Contains('"')) {
        throw "A native command argument contains an unsupported quote character."
    }

    return '"' + $Value + '"'
}

function Remove-StaleFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Assert-NonEmptyFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected output was not created: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        throw "Expected output is empty: $Path"
    }
}

function Get-SafeArtifactName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = [regex]::Replace($Value, '[^A-Za-z0-9._-]+', '_').Trim([char[]]@('_', '.'))
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "model"
    }

    return $safe
}

function Normalize-PbixName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PbixName)

    $value = $PbixName.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "PbixName cannot be empty."
    }
    if ($value -match '[\\/]') {
        throw "PbixName must be a filename only (no path)."
    }
    if ($value -notmatch '(?i)\.pbix$') {
        $value = "$value.pbix"
    }

    return $value
}

function Convert-DesktopWindowTitleToPbixName {
    [CmdletBinding()]
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $null
    }

    $value = [regex]::Replace($Title.Trim(), '\s+-\s+Power BI Desktop$', '')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }
    if ($value -notmatch '(?i)\.pbix$') {
        $value = "$value.pbix"
    }
    return $value
}

function Read-DesktopBridgeBytes {
    param(
        [Parameter(Mandatory = $true)][System.IO.Pipes.NamedPipeClientStream]$Pipe,
        [Parameter(Mandatory = $true)][byte[]]$Buffer,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(Mandatory = $true)][datetime]$DeadlineUtc
    )

    $remainingMs = [int][Math]::Ceiling(($DeadlineUtc - [datetime]::UtcNow).TotalMilliseconds)
    if ($remainingMs -le 0) { throw "Desktop Bridge response timed out." }
    $task = $Pipe.ReadAsync($Buffer, $Offset, $Count)
    if (-not $task.Wait($remainingMs)) { throw "Desktop Bridge response timed out." }
    return [int]$task.Result
}

function Invoke-DesktopBridgeRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$Method,
        [hashtable]$Parameters = @{},
        [int]$TimeoutMs = 500
    )

    # Desktop Bridge is preview. Treat every bridge failure as a soft miss so
    # the stable process/window/Analysis Services discovery path still works.
    $pipeName = "pbi-desktop-bridge-$ProcessId"
    $pipe = $null
    try {
        $pipe = New-Object -TypeName System.IO.Pipes.NamedPipeClientStream -ArgumentList @(
            ".",
            $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::None
        )
        $pipe.Connect($TimeoutMs)
        $pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Byte

        $request = [ordered]@{
            jsonrpc = "2.0"
            id = 1
            method = $Method
            params = $Parameters
        } | ConvertTo-Json -Depth 8 -Compress
        $body = [System.Text.Encoding]::UTF8.GetBytes($request)
        $header = [System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($body.Length)`r`n`r`n")
        $pipe.Write($header, 0, $header.Length)
        $pipe.Write($body, 0, $body.Length)
        $pipe.Flush()
        $deadlineUtc = [datetime]::UtcNow.AddMilliseconds($TimeoutMs)

        $headerBytes = New-Object System.Collections.Generic.List[byte]
        $window = New-Object System.Collections.Generic.Queue[byte]
        $singleByte = New-Object byte[] 1
        while ($true) {
            $read = Read-DesktopBridgeBytes -Pipe $pipe -Buffer $singleByte -Offset 0 -Count 1 -DeadlineUtc $deadlineUtc
            if ($read -le 0) { throw "Desktop Bridge closed before sending a response header." }
            $byte = $singleByte[0]
            $headerBytes.Add($byte) | Out-Null
            $window.Enqueue($byte)
            while ($window.Count -gt 4) { [void]$window.Dequeue() }
            if ($window.Count -eq 4) {
                $a = $window.ToArray()
                if ($a[0] -eq 13 -and $a[1] -eq 10 -and $a[2] -eq 13 -and $a[3] -eq 10) { break }
            }
            if ($headerBytes.Count -gt 8192) { throw "Desktop Bridge response header is unexpectedly large." }
        }

        $headerText = [System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
        $lengthMatch = [regex]::Match($headerText, '(?im)^Content-Length:\s*(\d+)\s*$')
        if (-not $lengthMatch.Success) { throw "Desktop Bridge response omitted Content-Length." }
        $contentLength = [int]$lengthMatch.Groups[1].Value
        if ($contentLength -lt 1 -or $contentLength -gt 16777216) { throw "Desktop Bridge response length is invalid." }

        $responseBytes = New-Object byte[] $contentLength
        $offset = 0
        while ($offset -lt $contentLength) {
            $read = Read-DesktopBridgeBytes -Pipe $pipe -Buffer $responseBytes -Offset $offset -Count ($contentLength - $offset) -DeadlineUtc $deadlineUtc
            if ($read -le 0) { throw "Desktop Bridge closed before the complete response body was received." }
            $offset += $read
        }
        $response = [System.Text.Encoding]::UTF8.GetString($responseBytes) | ConvertFrom-Json
        $errorProperty = $response.PSObject.Properties["error"]
        if ($null -ne $errorProperty -and $null -ne $errorProperty.Value) {
            throw "Desktop Bridge $Method failed: $($errorProperty.Value.message)"
        }
        $resultProperty = $response.PSObject.Properties["result"]
        if ($null -eq $resultProperty) { throw "Desktop Bridge response omitted result." }
        return $resultProperty.Value
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $pipe) { $pipe.Dispose() }
    }
}

function Get-PowerBIDesktopTargets {
    [CmdletBinding()]
    param()

    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($process in @(Get-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue)) {
        $bridgeState = Invoke-DesktopBridgeRequest -ProcessId $process.Id -Method "application.state.get/v1"
        $currentPath = $null
        $pbixName = $null
        $source = "window-title"
        $hasUnsavedChanges = $null

        if ($null -ne $bridgeState -and -not [string]::IsNullOrWhiteSpace([string]$bridgeState.currentFilePath)) {
            $currentPath = [string]$bridgeState.currentFilePath
            if ([System.IO.Path]::GetExtension($currentPath).Equals(".pbix", [System.StringComparison]::OrdinalIgnoreCase)) {
                $pbixName = [System.IO.Path]::GetFileName($currentPath)
                $source = "desktop-bridge"
                $unsavedProperty = $bridgeState.PSObject.Properties["hasUnsavedChanges"]
                if ($null -ne $unsavedProperty) { $hasUnsavedChanges = [bool]$unsavedProperty.Value }
            }
        }
        if ([string]::IsNullOrWhiteSpace($pbixName)) {
            $pbixName = Convert-DesktopWindowTitleToPbixName -Title ([string]$process.MainWindowTitle)
        }
        if ([string]::IsNullOrWhiteSpace($pbixName)) { continue }

        $targets.Add([pscustomobject]@{
            ProcessId = $process.Id
            PbixName = $pbixName
            CurrentFilePath = $currentPath
            HasUnsavedChanges = $hasUnsavedChanges
            DiscoverySource = $source
            WindowTitle = [string]$process.MainWindowTitle
        }) | Out-Null
    }
    return $targets
}

function Assert-UniqueOpenPowerBIDesktopFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FileName)

    $requestedName = [System.IO.Path]::GetFileName($FileName.Trim())
    if ([string]::IsNullOrWhiteSpace($requestedName) -or $requestedName -ne $FileName.Trim()) {
        throw "Power BI Desktop target must be a filename only (no path)."
    }
    $requestedBaseName = [System.IO.Path]::GetFileNameWithoutExtension($requestedName)
    $matches = @(
        Get-PowerBIDesktopTargets | Where-Object {
            $targetName = [string]$_.PbixName
            $targetName.Equals($requestedName, [System.StringComparison]::OrdinalIgnoreCase) -or
                [System.IO.Path]::GetFileNameWithoutExtension($targetName).Equals(
                    $requestedBaseName,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
        }
    )
    if ($matches.Count -gt 1) {
        throw "More than one open Power BI Desktop process matches filename '$requestedName'. Close one copy before continuing."
    }
}

function Get-OpenPowerBIDesktopNames {
    [CmdletBinding()]
    param()

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($target in @(Get-PowerBIDesktopTargets)) {
        if (-not $names.Contains([string]$target.PbixName)) {
            $names.Add([string]$target.PbixName) | Out-Null
        }
    }
    return @($names)
}

function Get-ListeningTcpPortForProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $ports = New-Object System.Collections.Generic.List[int]
    $netTcp = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
    if ($null -ne $netTcp) {
        try {
            foreach ($connection in @(
                Get-NetTCPConnection -State Listen -OwningProcess $ProcessId -ErrorAction Stop
            )) {
                if ($connection.LocalPort -gt 0 -and -not $ports.Contains([int]$connection.LocalPort)) {
                    $ports.Add([int]$connection.LocalPort) | Out-Null
                }
            }
        }
        catch { }
    }

    if ($ports.Count -eq 0) {
        try {
            foreach ($line in @(& netstat.exe -ano -p tcp 2>$null)) {
                $match = [regex]::Match([string]$line, '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$')
                if ($match.Success -and [int]$match.Groups[2].Value -eq $ProcessId) {
                    $port = [int]$match.Groups[1].Value
                    if (-not $ports.Contains($port)) { $ports.Add($port) | Out-Null }
                }
            }
        }
        catch { }
    }

    if ($ports.Count -eq 1) { return [string]$ports[0] }
    return $null
}

function Get-LocalDesktopModelContexts {
    [CmdletBinding()]
    param()

    $contexts = New-Object System.Collections.Generic.List[object]
    try {
        $processes = @(
            Get-CimInstance Win32_Process -Filter "Name='msmdsrv.exe'" -ErrorAction Stop |
                Select-Object -Property ProcessId, ParentProcessId, CommandLine
        )
    }
    catch {
        $processes = @()
    }

    foreach ($proc in $processes) {
        if ([string]::IsNullOrWhiteSpace($proc.CommandLine)) {
            continue
        }

        $dataPathMatch = [regex]::Match($proc.CommandLine, '-s\s+"([^"]+)"')
        if (-not $dataPathMatch.Success) {
            continue
        }

        $dataPath = $dataPathMatch.Groups[1].Value
        if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) {
            continue
        }

        $port = $null
        $portSource = $null
        $portFile = Join-Path $dataPath "msmdsrv.port.txt"
        if (Test-Path -LiteralPath $portFile -PathType Leaf) {
            $candidatePort = ((Get-Content -LiteralPath $portFile -Raw) -replace "`0", "").Trim()
            if ($candidatePort -match '^\d+$') {
                $port = $candidatePort
                $portSource = "msmdsrv.port.txt"
            }
        }
        $listenerPort = Get-ListeningTcpPortForProcess -ProcessId ([int]$proc.ProcessId)
        if ($listenerPort) {
            if ([string]::IsNullOrWhiteSpace($port)) {
                $port = $listenerPort
                $portSource = "tcp-listener"
            }
            elseif ([string]$listenerPort -ne [string]$port) {
                # Prefer the live listener owned by this exact msmdsrv process if
                # a stale port file disagrees with current process evidence.
                $port = $listenerPort
                $portSource = "tcp-listener-overrode-port-file"
            }
        }
        if ([string]::IsNullOrWhiteSpace($port)) { continue }

        $dbXml = Get-ChildItem -LiteralPath $dataPath -Filter "*.db.xml" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $dbXml) {
            continue
        }

        [xml]$xmlDoc = Get-Content -LiteralPath $dbXml.FullName -Raw
        $database = $xmlDoc.Load.ObjectDefinition.Database
        if ($null -eq $database) {
            continue
        }

        $desktopWindowTitle = $null
        $pbixName = $null
        if ($proc.ParentProcessId) {
            $parent = Get-Process -Id $proc.ParentProcessId -ErrorAction SilentlyContinue
            if ($null -ne $parent -and $parent.ProcessName -like "PBIDesktop*") {
                $desktopWindowTitle = [string]$parent.MainWindowTitle
                $pbixName = Convert-DesktopWindowTitleToPbixName -Title $desktopWindowTitle
            }
        }

        $contexts.Add([pscustomobject]@{
            ProcessId = $proc.ProcessId
            ParentProcessId = $proc.ParentProcessId
            DesktopWindowTitle = $desktopWindowTitle
            PbixName = $pbixName
            DataPath = $dataPath
            Port = $port
            PortSource = $portSource
            Catalog = [string]$database.ID
            DatabaseName = [string]$database.Name
            LastWriteTime = $dbXml.LastWriteTime
            DbXmlPath = $dbXml.FullName
        }) | Out-Null
    }

    return $contexts
}

function Resolve-LocalDesktopModelContext {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PbixName)

    $normalized = Normalize-PbixName -PbixName $PbixName
    $targetBaseName = [System.IO.Path]::GetFileNameWithoutExtension($normalized)
    $contexts = @(Get-LocalDesktopModelContexts)

    if ($contexts.Count -eq 0) {
        throw "No local Power BI Desktop model contexts found. Open the PBIX and wait for it to finish loading."
    }

    # When Desktop Bridge is available it gives us the exact file-to-PID mapping,
    # which is stronger evidence than window titles or internal database names.
    $bridgeTargets = @(
        Get-PowerBIDesktopTargets | Where-Object {
            $_.DiscoverySource -eq "desktop-bridge" -and
            $_.PbixName.Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )
    if ($bridgeTargets.Count -gt 1) {
        throw "More than one open Power BI Desktop process has filename '$normalized'. Close one copy before continuing."
    }
    if ($bridgeTargets.Count -eq 1) {
        $bridgeContextMatches = @(
            $contexts | Where-Object { [int]$_.ParentProcessId -eq [int]$bridgeTargets[0].ProcessId }
        )
        if ($bridgeContextMatches.Count -eq 1) { return $bridgeContextMatches[0] }
    }

    $windowMatches = @(
        $contexts | Where-Object {
            $_.PbixName -and $_.PbixName.Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )
    if ($windowMatches.Count -eq 1) {
        return $windowMatches[0]
    }
    if ($windowMatches.Count -gt 1) {
        throw "More than one local model matches PBIX filename '$normalized'. Close one copy before continuing."
    }

    $databaseMatches = @(
        $contexts | Where-Object {
            $_.DatabaseName -and $_.DatabaseName.Equals($targetBaseName, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )
    if ($databaseMatches.Count -eq 1) {
        return $databaseMatches[0]
    }
    if ($databaseMatches.Count -gt 1) {
        throw "More than one local model has internal database name '$targetBaseName'. Refusing to guess."
    }

    $available = @(
        $contexts | ForEach-Object {
            $label = if ($_.PbixName) { $_.PbixName } elseif ($_.DatabaseName) { $_.DatabaseName } else { "unknown" }
            "${label}@localhost:$($_.Port)"
        }
    ) -join ", "
    throw "Could not uniquely resolve PBIX '$normalized'. Open models: $available"
}

function Resolve-LocalDesktopContextByPort {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Port)

    $matches = @(Get-LocalDesktopModelContexts | Where-Object { [string]$_.Port -eq [string]$Port })
    if ($matches.Count -eq 1) {
        return $matches[0]
    }
    if ($matches.Count -eq 0) {
        throw "No local Power BI Desktop model found on port $Port."
    }
    throw "More than one local model context reported port $Port."
}
