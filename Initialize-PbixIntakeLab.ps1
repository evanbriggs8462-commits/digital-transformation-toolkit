[CmdletBinding()]
param(
    [Parameter()]
    [string]$Te2Path,

    [Parameter()]
    [string]$DscmdPath,

    [Parameter()]
    [string]$ToolConfigPath,

    [Parameter()]
    [string]$ProvisioningLogDirectory,

    [Parameter()]
    [ValidateRange(5, 120)]
    [int]$SmokeTimeoutSeconds = 20
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ToolConfigPath)) {
    $ToolConfigPath = Join-Path $PSScriptRoot 'config\tools.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($ToolConfigPath)) {
    $ToolConfigPath = Join-Path $PSScriptRoot $ToolConfigPath
}

$modulePath = Join-Path $PSScriptRoot 'powershell\PbixIntake.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "PBIX Intake Lab core module is missing: $modulePath"
}
Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop

function Resolve-ToolPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RequestedPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('TE2', 'DAX')]
        [string]$Kind
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            Throw-PbixIntakeFailure `
                -BlockerCode 'TOOL_MISSING' `
                -Message "$Kind executable was not found at the supplied path." `
                -NextAction 'Supply the absolute path to the approved executable.' `
                -FailureStage 'provisioning'
        }
        return (Get-Item -LiteralPath $RequestedPath -ErrorAction Stop).FullName
    }

    $candidatePatterns = if ($Kind -eq 'TE2') {
        @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\TabularEditor.TabularEditor.2_*\TabularEditor.exe'),
            (Join-Path $env:LOCALAPPDATA 'DigitalTransformationToolkit\tools\TabularEditor2\*\TabularEditor.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Tabular Editor\TabularEditor.exe'),
            (Join-Path $env:ProgramFiles 'Tabular Editor\TabularEditor.exe')
        )
    }
    else {
        @(
            (Join-Path $env:LOCALAPPDATA 'Programs\DAX Studio\dscmd.exe'),
            (Join-Path $env:LOCALAPPDATA 'DigitalTransformationToolkit\tools\DAXStudio\*\dscmd.exe'),
            (Join-Path $env:ProgramFiles 'DAX Studio\dscmd.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'DAX Studio\dscmd.exe')
        )
    }

    $candidates = @(
        foreach ($pattern in $candidatePatterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                continue
            }
            Get-Item -Path $pattern -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer }
        }
    ) | Sort-Object -Property FullName -Unique

    if ($candidates.Count -eq 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'TOOL_MISSING' `
            -Message "No installed $Kind executable was found in the known local locations." `
            -NextAction 'Provision the approved tool once, then supply its absolute executable path.' `
            -FailureStage 'provisioning'
    }

    if ($candidates.Count -ne 1) {
        $paths = ($candidates.FullName -join '; ')
        Throw-PbixIntakeFailure `
            -BlockerCode 'TOOL_IDENTITY_INVALID' `
            -Message "More than one $Kind executable was found: $paths" `
            -NextAction 'Rerun the initializer with the exact approved executable path.' `
            -FailureStage 'provisioning'
    }

    return $candidates[0].FullName
}

function New-ToolRegistrationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('TE2', 'DAX')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName -ErrorAction Stop
    $hash = Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop
    $signerSubject = if ($null -ne $signature.SignerCertificate) {
        [string]$signature.SignerCertificate.Subject
    }
    else {
        $null
    }
    $distribution = New-ToolDistributionRecord -ExecutablePath $item.FullName

    return [pscustomobject][ordered]@{
        kind            = $Kind
        path            = $item.FullName
        fileName        = $item.Name
        productName     = [string]$item.VersionInfo.ProductName
        productVersion  = [string]$item.VersionInfo.ProductVersion
        fileVersion     = [string]$item.VersionInfo.FileVersion
        signatureStatus = [string]$signature.Status
        signerSubject   = $signerSubject
        publisher       = $signerSubject
        sha256          = ([string]$hash.Hash).ToUpperInvariant()
        distributionRoot = [string]$distribution.root
        distributionFiles = [object[]]$distribution.files
    }
}

function Invoke-ToolHelpSmoke {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('TE2', 'DAX')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$LogDirectory
    )

    $arguments = if ($Kind -eq 'TE2') { @('/?') } else { @('--help') }
    $prefix = $Kind.ToLowerInvariant()
    try {
        $result = Invoke-BoundedProcess `
            -FilePath $Path `
            -ArgumentList $arguments `
            -TimeoutSeconds $SmokeTimeoutSeconds `
            -StdoutPath (Join-Path $LogDirectory "$prefix-help.stdout.log") `
            -StderrPath (Join-Path $LogDirectory "$prefix-help.stderr.log") `
            -TimeoutBlockerCode 'TOOL_RUNTIME_INCOMPLETE'
    }
    catch {
        $failure = Get-PbixIntakeFailureInfo -Exception $_.Exception
        Throw-PbixIntakeFailure `
            -BlockerCode $(if ($failure.blockerCode -eq 'TOOL_EXECUTION_BLOCKED') { 'TOOL_EXECUTION_BLOCKED' } else { 'TOOL_RUNTIME_INCOMPLETE' }) `
            -Message "$Kind harmless help smoke test could not complete: $($failure.message)" `
            -NextAction 'Restore the complete approved distribution or ask IT to review the execution-policy logs.' `
            -FailureStage 'provisioning'
    }

    if ($result.PSObject.Properties.Name -contains 'TimedOut' -and $result.TimedOut) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'TOOL_RUNTIME_INCOMPLETE' `
            -Message "$Kind harmless help smoke test timed out." `
            -NextAction 'Restore the complete approved distribution and rerun initialization.' `
            -FailureStage 'provisioning'
    }

    if ($null -eq $result.ExitCode -or [int]$result.ExitCode -ne 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'TOOL_RUNTIME_INCOMPLETE' `
            -Message "$Kind harmless help smoke test returned exit code $($result.ExitCode)." `
            -NextAction 'Review the provisioning logs and restore the complete approved distribution.' `
            -FailureStage 'provisioning'
    }
}

try {
    $resolvedTe2Path = Resolve-ToolPath -RequestedPath $Te2Path -Kind TE2
    $resolvedDscmdPath = Resolve-ToolPath -RequestedPath $DscmdPath -Kind DAX

    $te2Record = New-ToolRegistrationRecord -Kind TE2 -Path $resolvedTe2Path
    $daxRecord = New-ToolRegistrationRecord -Kind DAX -Path $resolvedDscmdPath

    # Validate identity, publisher, version floor, and the just-computed hash before execution.
    Assert-ToolRegistration `
        -Kind TE2 `
        -Path $te2Record.path `
        -ExpectedSha256 $te2Record.sha256 `
        -ExpectedVersion $te2Record.productVersion `
        -ExpectedSignerSubject $te2Record.signerSubject | Out-Null
    Assert-ToolRegistration `
        -Kind DAX `
        -Path $daxRecord.path `
        -ExpectedSha256 $daxRecord.sha256 `
        -ExpectedVersion $daxRecord.productVersion `
        -ExpectedSignerSubject $daxRecord.signerSubject | Out-Null

    $configFullPath = [System.IO.Path]::GetFullPath($ToolConfigPath)
    $configDirectory = Split-Path -Parent $configFullPath
    if ([string]::IsNullOrWhiteSpace($ProvisioningLogDirectory)) {
        $provisioningRunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss.fffffffZ') + '-' + [Guid]::NewGuid().ToString('N')
        $logDirectory = Join-Path (Join-Path $configDirectory 'provisioning-logs') $provisioningRunId
    }
    elseif ([System.IO.Path]::IsPathRooted($ProvisioningLogDirectory)) {
        $logDirectory = [System.IO.Path]::GetFullPath($ProvisioningLogDirectory)
    }
    else {
        $logDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ProvisioningLogDirectory))
    }
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

    Invoke-ToolHelpSmoke -Kind TE2 -Path $resolvedTe2Path -LogDirectory $logDirectory
    Invoke-ToolHelpSmoke -Kind DAX -Path $resolvedDscmdPath -LogDirectory $logDirectory

    $config = [pscustomobject][ordered]@{
        schemaVersion   = 2
        registeredAtUtc = [DateTime]::UtcNow.ToString('o')
        tools           = [pscustomobject][ordered]@{
            te2 = $te2Record
            dax = $daxRecord
        }
    }

    $temporaryConfigPath = "$configFullPath.tmp"
    Write-JsonFile -Path $temporaryConfigPath -InputObject $config -Depth 10
    Move-Item -LiteralPath $temporaryConfigPath -Destination $configFullPath -Force

    Write-Output "PBIX Intake Lab tools registered at: $configFullPath"
    Write-Output 'No software was downloaded, installed, updated, repaired, or elevated.'
}
catch {
    $failure = Get-PbixIntakeFailureInfo -Exception $_.Exception
    Write-Error ("{0}: {1} Next action: {2}" -f $failure.blockerCode, $failure.message, $failure.nextAction)
    exit 1
}
