[CmdletBinding()]
param(
    [Parameter()]
    [string]$PbixName,

    [Parameter()]
    [string]$OutputRoot,

    [Parameter()]
    [string]$ToolConfigPath,

    [Parameter()]
    [ValidateRange(10, 1800)]
    [int]$TimeoutSeconds = 180,

    [Parameter()]
    [switch]$SkipVpax
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot 'runs'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot $OutputRoot
}

if ([string]::IsNullOrWhiteSpace($ToolConfigPath)) {
    $ToolConfigPath = Join-Path $PSScriptRoot 'config\tools.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($ToolConfigPath)) {
    $ToolConfigPath = Join-Path $PSScriptRoot $ToolConfigPath
}

$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$ToolConfigPath = [System.IO.Path]::GetFullPath($ToolConfigPath)
$modulePath = Join-Path $PSScriptRoot 'powershell\PbixIntake.Core.psm1'
$queryPath = Join-Path $PSScriptRoot 'dax\queries\connection_test.dax'

function Write-Utf8JsonFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 30
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($json -replace "`r`n", "`n") + "`n", $encoding)
}

function Get-SafePropertyValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    if ($null -eq $InputObject) {
        return $null
    }
    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            return $property.Value
        }
    }
    return $null
}

function Get-SafeTargetEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Target)

    return [pscustomobject][ordered]@{
        pbixName            = Get-SafePropertyValue -InputObject $Target -Names @('PbixName', 'Name')
        processId           = Get-SafePropertyValue -InputObject $Target -Names @('ProcessId', 'DesktopProcessId', 'Pid')
        currentFilePath     = Get-SafePropertyValue -InputObject $Target -Names @('CurrentFilePath', 'Path', 'FilePath')
        discoverySource     = Get-SafePropertyValue -InputObject $Target -Names @('DiscoverySource', 'Source')
        bridgeFilePath      = Get-SafePropertyValue -InputObject $Target -Names @('BridgeCurrentFilePath', 'DesktopBridgeCurrentFilePath', 'BridgeFilePath')
        bridgePbixName      = Get-SafePropertyValue -InputObject $Target -Names @('BridgePbixName', 'DesktopBridgePbixName')
        commandLineFilePath = Get-SafePropertyValue -InputObject $Target -Names @('CommandLineFilePath', 'CommandLinePath', 'ProcessCommandLinePath')
        commandLinePbixName = Get-SafePropertyValue -InputObject $Target -Names @('CommandLinePbixName', 'ProcessCommandLinePbixName')
        commandLine         = Get-SafePropertyValue -InputObject $Target -Names @('CommandLine', 'ProcessCommandLine')
        windowTitle         = Get-SafePropertyValue -InputObject $Target -Names @('WindowTitle', 'MainWindowTitle')
        windowPbixName      = Get-SafePropertyValue -InputObject $Target -Names @('WindowPbixName', 'WindowTitlePbixName')
        hasUnsavedChanges   = Get-SafePropertyValue -InputObject $Target -Names @('HasUnsavedChanges')
        discoveryEvidence   = Get-SafePropertyValue -InputObject $Target -Names @('DiscoveryEvidence', 'Evidence')
    }
}

function Assert-AgentFacingTextSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$ArtifactName
    )

    $tokenPatterns = @(
        '(?i)\bBearer\s+[A-Za-z0-9._~+\/-]{12,}={0,2}',
        '(?i)\bdapi[a-z0-9]{20,}\b',
        '(?i)\bsk-(?:proj-)?[a-z0-9_-]{16,}\b',
        '(?i)\bgh[pousr]_[a-z0-9]{20,}\b',
        '(?i)\bSharedAccessSignature\s+sr=[^\s;]+'
    )
    foreach ($pattern in $tokenPatterns) {
        if ([regex]::IsMatch($Text, $pattern)) {
            Throw-PbixIntakeFailure `
                -BlockerCode 'REDACTION_FAILED' `
                -Message "A likely secret remained in agent-facing artifact $ArtifactName." `
                -NextAction 'Keep this run restricted and update the redaction rules before sharing it.' `
                -FailureStage 'publish'
        }
    }

    $assignmentPattern = '(?i)(?:password|pwd|client[_-]?secret|api[_-]?key|accountkey|account_key|sharedaccesssignature|access[_-]?token)\s*[=:]\s*["'']?([^;,\r\n}"'']+)'
    foreach ($match in [regex]::Matches($Text, $assignmentPattern)) {
        $candidate = $match.Groups[1].Value.Trim()
        if ($candidate -and
            $candidate -notmatch '(?i)^(?:\[?redacted\]?|<redacted>|\*+|null|none)$') {
            Throw-PbixIntakeFailure `
                -BlockerCode 'REDACTION_FAILED' `
                -Message "A credential-like assignment remained in agent-facing artifact $ArtifactName." `
                -NextAction 'Keep this run restricted and update the redaction rules before sharing it.' `
                -FailureStage 'publish'
        }
    }
}

function Assert-HandoffScope {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text)

    if ($Text -notmatch '(?i)report\s+layer' -or
        $Text -notmatch '(?i)(?:not\s+(?:captured|collected)|out\s+of\s+scope)') {
        Throw-PbixIntakeFailure `
            -BlockerCode 'HANDOFF_OVERCLAIM' `
            -Message 'The handoff does not explicitly state that the report layer was not captured.' `
            -NextAction 'Add the required report-layer boundary and regenerate the handoff.' `
            -FailureStage 'publish'
    }

    $affirmativeOverclaims = @(
        '(?im)^\s*(?:[-*]\s*)?(?:report\s+canvas|report\s+pages?|visuals?|slicers?|bookmarks?)\s*[:=-]?\s*(?:were\s+|was\s+|is\s+|are\s+)?(?:captured|collected|extracted)',
        '(?im)^\s*(?:[-*]\s*)?(?:complete|full)\s+PBIX\s*[:=-]?\s*(?:captured|recreated|reconstructable)'
    )
    foreach ($pattern in $affirmativeOverclaims) {
        if ($Text -match $pattern) {
            Throw-PbixIntakeFailure `
                -BlockerCode 'HANDOFF_OVERCLAIM' `
                -Message 'The handoff claims coverage beyond the semantic model.' `
                -NextAction 'Remove report-canvas or complete-PBIX claims and regenerate the handoff.' `
                -FailureStage 'publish'
        }
    }
}

$runId = '{0}_{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), ([Guid]::NewGuid().ToString('N').Substring(0, 12))
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$runFolder = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runFolder -ErrorAction Stop | Out-Null

$logsDirectory = Join-Path $runFolder 'logs'
$semanticDirectory = Join-Path $runFolder 'semantic_model'
$tmdlDirectory = Join-Path $semanticDirectory 'tmdl'
$normalizedDirectory = Join-Path $runFolder 'normalized'
$validationDirectory = Join-Path $runFolder 'validation'
foreach ($directory in @($logsDirectory, $semanticDirectory, $tmdlDirectory, $normalizedDirectory, $validationDirectory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$runJsonPath = Join-Path $runFolder 'run.json'
$commandsJsonPath = Join-Path $runFolder 'commands.json'
$handoffPath = Join-Path $runFolder 'GENIE_HANDOFF.md'
$handoffTemporaryPath = Join-Path $runFolder '.GENIE_HANDOFF.md.tmp'
$scriptSucceeded = $false
$ownsMutex = $false
$mutex = $null
$commands = New-Object System.Collections.ArrayList

$runState = [pscustomobject][ordered]@{
    schemaVersion      = 1
    runId              = $runId
    status             = 'running'
    result             = $null
    blockerCode        = $null
    message            = 'PBIX semantic-model intake started.'
    nextAction         = $null
    failureStage       = $null
    retryable          = $false
    requiresIT         = $false
    requestedPbixName  = if ([string]::IsNullOrWhiteSpace($PbixName)) { $null } else { $PbixName }
    openTargets        = @()
    selectedPbixName   = $null
    startedAtUtc       = [DateTime]::UtcNow.ToString('o')
    finishedAtUtc      = $null
    outputDirectory    = $runFolder
}

function Save-RunState {
    Write-Utf8JsonFallback -Path $runJsonPath -Value $runState
}

function Save-CommandTrail {
    $document = [pscustomobject][ordered]@{
        schemaVersion = 1
        commands      = [object[]]$commands.ToArray()
    }
    Write-Utf8JsonFallback -Path $commandsJsonPath -Value $document
}

function Invoke-RecordedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath,
        [Parameter(Mandatory = $true)][string]$TimeoutBlockerCode
    )

    $entry = [pscustomobject][ordered]@{
        name          = $Name
        executable    = $FilePath
        argumentList  = @($ArgumentList)
        status        = 'started'
        exitCode      = $null
        timedOut      = $false
        failureCode   = $null
        stdout        = [System.IO.Path]::GetFileName($StdoutPath)
        stderr        = [System.IO.Path]::GetFileName($StderrPath)
    }
    [void]$commands.Add($entry)
    Save-CommandTrail

    try {
        $result = Invoke-BoundedProcess `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -TimeoutSeconds $TimeoutSeconds `
            -StdoutPath $StdoutPath `
            -StderrPath $StderrPath `
            -TimeoutBlockerCode $TimeoutBlockerCode
        $entry.exitCode = $result.ExitCode
        if ($result.PSObject.Properties.Name -contains 'TimedOut') {
            $entry.timedOut = [bool]$result.TimedOut
        }
        $entry.status = if ($entry.timedOut) { 'timed-out' } elseif ([int]$entry.exitCode -eq 0) { 'completed' } else { 'failed' }
        Save-CommandTrail
        return $result
    }
    catch {
        $entry.status = 'failed'
        $failure = $null
        try { $failure = Get-PbixIntakeFailureInfo -Exception $_.Exception } catch { }
        if ($null -ne $failure -and $failure.PSObject.Properties.Name -contains 'blockerCode') {
            $entry.failureCode = $failure.blockerCode
        }
        Save-CommandTrail
        throw
    }
}

Save-RunState
Save-CommandTrail

try {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "PBIX Intake Lab core module is missing: $modulePath"
    }
    Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($false, 'Local\PBIXIntakeLab.SemanticIntake.v2', [ref]$createdNew)
    try {
        $ownsMutex = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $ownsMutex = $true
    }
    if (-not $ownsMutex) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'RUN_ALREADY_ACTIVE' `
            -Message 'Another PBIX Intake Lab run owns the local runtime mutex.' `
            -NextAction 'Wait for the active run to finish, then retry.' `
            -FailureStage 'startup' `
            -Retryable
    }

    if (-not (Test-Path -LiteralPath $ToolConfigPath -PathType Leaf)) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'TOOLS_NOT_PROVISIONED' `
            -Message "The one-time tool registration does not exist: $ToolConfigPath" `
            -NextAction 'Run Initialize-PbixIntakeLab.ps1 once with the approved TE2 and dscmd paths.' `
            -FailureStage 'tool-validation'
    }

    $registeredTools = Get-RegisteredTools -ConfigPath $ToolConfigPath
    $te2Tool = $registeredTools.Te2
    $daxTool = $registeredTools.Dax

    $targets = @(Get-PowerBIDesktopTargets)
    $runState.openTargets = @($targets | ForEach-Object { Get-SafeTargetEvidence -Target $_ })
    Save-RunState

    $selectionArguments = @{ Targets = $targets }
    if (-not [string]::IsNullOrWhiteSpace($PbixName)) {
        $selectionArguments.PbixName = $PbixName
    }
    $target = Select-PbixTarget @selectionArguments
    $runState.selectedPbixName = [string](Get-SafePropertyValue -InputObject $target -Names @('PbixName', 'Name'))
    Save-RunState

    $contexts = @(Get-LocalDesktopModelContexts)
    $context = Resolve-PbixModelContext -Target $target -Contexts $contexts
    if ([string]::IsNullOrWhiteSpace([string]$context.Server) -or
        [string]::IsNullOrWhiteSpace([string]$context.Catalog)) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'PBIX_IDENTITY_MISMATCH' `
            -Message 'The selected Desktop process did not resolve to one explicit server and catalog.' `
            -NextAction 'Close stale Desktop instances, reopen the intended PBIX, wait for its Data pane, and retry.' `
            -FailureStage 'identity'
    }

    $identity = [pscustomobject][ordered]@{
        schemaVersion = 1
        target        = Get-SafeTargetEvidence -Target $target
        openTargets   = @($runState.openTargets)
        modelContext  = [pscustomobject][ordered]@{
            server           = [string]$context.Server
            catalog          = [string]$context.Catalog
            port             = Get-SafePropertyValue -InputObject $context -Names @('Port')
            desktopProcessId = Get-SafePropertyValue -InputObject $context -Names @('DesktopProcessId', 'ProcessId')
            modelProcessId   = Get-SafePropertyValue -InputObject $context -Names @('ModelProcessId', 'AnalysisServicesProcessId')
            dataPath         = Get-SafePropertyValue -InputObject $context -Names @('DataPath')
            portSource       = Get-SafePropertyValue -InputObject $context -Names @('PortSource')
            catalogSource    = Get-SafePropertyValue -InputObject $context -Names @('CatalogSource', 'DatabaseSource')
            desktopWindowTitle = Get-SafePropertyValue -InputObject $context -Names @('DesktopWindowTitle', 'WindowTitle')
            discoveryEvidence = Get-SafePropertyValue -InputObject $context -Names @('DiscoveryEvidence', 'Evidence')
        }
        tools         = [pscustomobject][ordered]@{
            te2 = [pscustomobject][ordered]@{
                path           = $te2Tool.Path
                productVersion = $te2Tool.ProductVersion
                signerSubject  = $te2Tool.SignerSubject
                sha256         = $te2Tool.Sha256
            }
            dax = [pscustomobject][ordered]@{
                path           = $daxTool.Path
                productVersion = $daxTool.ProductVersion
                signerSubject  = $daxTool.SignerSubject
                sha256         = $daxTool.Sha256
            }
        }
    }
    Write-JsonFile -Path (Join-Path $runFolder 'identity.json') -InputObject $identity -Depth 15

    $bimPath = Join-Path $semanticDirectory 'model.bim'
    $te2BimArguments = @(Get-Te2ExportArguments -Server $context.Server -Catalog $context.Catalog -OutputPath $bimPath -Format BIM)
    $bimResult = Invoke-RecordedProcess `
        -Name 'te2-bim-export' `
        -FilePath $te2Tool.Path `
        -ArgumentList $te2BimArguments `
        -StdoutPath (Join-Path $logsDirectory 'te2-bim.stdout.log') `
        -StderrPath (Join-Path $logsDirectory 'te2-bim.stderr.log') `
        -TimeoutBlockerCode 'TE2_TIMEOUT'
    if ([int]$bimResult.ExitCode -ne 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'TE2_EXECUTION_FAILED' `
            -Message "TE2 BIM export returned exit code $($bimResult.ExitCode)." `
            -NextAction 'Read the bounded TE2 logs and confirm that the selected model is fully loaded.' `
            -FailureStage 'bim-export'
    }
    if (-not (Test-Path -LiteralPath $bimPath -PathType Leaf) -or (Get-Item -LiteralPath $bimPath).Length -le 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'MODEL_EXPORT_MISSING' `
            -Message 'TE2 returned without producing a nonempty BIM artifact.' `
            -NextAction 'Treat the run as failed, inspect TE2 logs, and retry only after model readiness is proven.' `
            -FailureStage 'bim-validation'
    }
    try {
        $null = Get-Content -LiteralPath $bimPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Throw-PbixIntakeFailure `
            -BlockerCode 'MODEL_EXPORT_INVALID' `
            -Message 'The exported BIM is not valid JSON.' `
            -NextAction 'Preserve the logs and retry after confirming model readiness.' `
            -FailureStage 'bim-validation'
    }

    $te2TmdlArguments = @(Get-Te2ExportArguments -Server $context.Server -Catalog $context.Catalog -OutputPath $tmdlDirectory -Format TMDL)
    $tmdlResult = Invoke-RecordedProcess `
        -Name 'te2-tmdl-export' `
        -FilePath $te2Tool.Path `
        -ArgumentList $te2TmdlArguments `
        -StdoutPath (Join-Path $logsDirectory 'te2-tmdl.stdout.log') `
        -StderrPath (Join-Path $logsDirectory 'te2-tmdl.stderr.log') `
        -TimeoutBlockerCode 'TE2_TIMEOUT'
    if ([int]$tmdlResult.ExitCode -ne 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'TE2_EXECUTION_FAILED' `
            -Message "TE2 TMDL export returned exit code $($tmdlResult.ExitCode)." `
            -NextAction 'Read the bounded TE2 logs and confirm that the selected model is fully loaded.' `
            -FailureStage 'tmdl-export'
    }
    $tmdlFiles = @(Get-ChildItem -LiteralPath $tmdlDirectory -Recurse -File -Filter '*.tmdl' -ErrorAction SilentlyContinue)
    if ($tmdlFiles.Count -eq 0 -or @($tmdlFiles | Where-Object { $_.Length -gt 0 }).Count -eq 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'MODEL_EXPORT_INVALID' `
            -Message 'The TMDL export did not contain a nonempty .tmdl file.' `
            -NextAction 'Preserve the logs and retry after confirming model readiness.' `
            -FailureStage 'tmdl-validation'
    }

    $normalizedModelPath = Join-Path $normalizedDirectory 'model.redacted.json'
    $normalizedModel = ConvertTo-PbixIntakeNormalizedModel -BimPath $bimPath -OutputPath $normalizedModelPath
    if (-not (Test-Path -LiteralPath $normalizedModelPath -PathType Leaf) -or
        (Get-Item -LiteralPath $normalizedModelPath).Length -le 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'MODEL_EXPORT_INVALID' `
            -Message 'The deterministic normalized model artifact was not created.' `
            -NextAction 'Inspect the BIM normalizer and preserve this failed run.' `
            -FailureStage 'normalization'
    }

    if (-not (Test-Path -LiteralPath $queryPath -PathType Leaf)) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'DAX_ARGUMENT_CONTRACT_FAILED' `
            -Message 'The fixed DAX connection-proof query is missing.' `
            -NextAction 'Restore dax\queries\connection_test.dax from the reviewed lab source.' `
            -FailureStage 'dax-validation'
    }
    $queryText = ((Get-Content -LiteralPath $queryPath -Raw -Encoding UTF8) -replace "`r`n", "`n").Trim()
    $expectedQueryText = "EVALUATE`nROW(`"PbixIntakeConnection`", `"OK`")"
    if ($queryText -cne $expectedQueryText) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'DAX_ARGUMENT_CONTRACT_FAILED' `
            -Message 'The fixed DAX connection-proof query differs from the reviewed one-row contract.' `
            -NextAction 'Restore the reviewed connection_test.dax file; do not substitute a business-data query.' `
            -FailureStage 'dax-validation'
    }

    $daxCsvPath = Join-Path $validationDirectory 'dax_connection.csv'
    $daxCsvArguments = @(Get-DscmdCsvArguments -Server $context.Server -Catalog $context.Catalog -OutputPath $daxCsvPath -QueryFile $queryPath)
    $daxResult = Invoke-RecordedProcess `
        -Name 'dax-connection-proof' `
        -FilePath $daxTool.Path `
        -ArgumentList $daxCsvArguments `
        -StdoutPath (Join-Path $logsDirectory 'dax-connection.stdout.log') `
        -StderrPath (Join-Path $logsDirectory 'dax-connection.stderr.log') `
        -TimeoutBlockerCode 'DAX_TIMEOUT'
    if ([int]$daxResult.ExitCode -ne 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'DAX_CONNECTION_FAILED' `
            -Message "The fixed DAX connection proof returned exit code $($daxResult.ExitCode)." `
            -NextAction 'Read the dscmd logs and reopen or finish loading the selected PBIX.' `
            -FailureStage 'dax-validation'
    }
    if (-not (Test-Path -LiteralPath $daxCsvPath -PathType Leaf) -or (Get-Item -LiteralPath $daxCsvPath).Length -le 0) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'DAX_OUTPUT_INVALID' `
            -Message 'dscmd returned without producing a nonempty DAX connection CSV.' `
            -NextAction 'Preserve the logs and do not publish a handoff.' `
            -FailureStage 'dax-validation'
    }
    $connectionRows = @(Import-Csv -LiteralPath $daxCsvPath)
    if ($connectionRows.Count -ne 1) {
        Throw-PbixIntakeFailure `
            -BlockerCode 'DAX_OUTPUT_INVALID' `
            -Message "The DAX connection proof returned $($connectionRows.Count) rows instead of exactly one." `
            -NextAction 'Preserve the logs and do not publish a handoff.' `
            -FailureStage 'dax-validation'
    }
    $connectionProperties = @($connectionRows[0].PSObject.Properties)
    if ($connectionProperties.Count -ne 1 -or
        $connectionProperties[0].Name.Trim('[', ']') -cne 'PbixIntakeConnection' -or
        [string]$connectionProperties[0].Value -cne 'OK') {
        Throw-PbixIntakeFailure `
            -BlockerCode 'DAX_OUTPUT_INVALID' `
            -Message 'The DAX connection proof did not contain the exact PbixIntakeConnection=OK result.' `
            -NextAction 'Preserve the logs and do not publish a handoff.' `
            -FailureStage 'dax-validation'
    }

    $vpaxStatus = 'skipped-by-operator'
    if (-not $SkipVpax) {
        $vpaxPath = Join-Path $validationDirectory 'model.vpax'
        $vpaxArguments = @(Get-DscmdVpaxArguments -Server $context.Server -Catalog $context.Catalog -OutputPath $vpaxPath)
        $vpaxResult = Invoke-RecordedProcess `
            -Name 'vpax-metadata-export' `
            -FilePath $daxTool.Path `
            -ArgumentList $vpaxArguments `
            -StdoutPath (Join-Path $logsDirectory 'dax-vpax.stdout.log') `
            -StderrPath (Join-Path $logsDirectory 'dax-vpax.stderr.log') `
            -TimeoutBlockerCode 'DAX_TIMEOUT'
        if ([int]$vpaxResult.ExitCode -ne 0) {
            Throw-PbixIntakeFailure `
                -BlockerCode 'DAX_CONNECTION_FAILED' `
                -Message "The metadata-only VPAX command returned exit code $($vpaxResult.ExitCode)." `
                -NextAction 'Read the dscmd logs and confirm the model endpoint is still alive.' `
                -FailureStage 'vpax-validation'
        }
        if (-not (Test-Path -LiteralPath $vpaxPath -PathType Leaf) -or (Get-Item -LiteralPath $vpaxPath).Length -le 0) {
            Throw-PbixIntakeFailure `
                -BlockerCode 'DAX_OUTPUT_INVALID' `
                -Message 'dscmd returned without producing a nonempty VPAX artifact.' `
                -NextAction 'Preserve the logs and do not publish a handoff.' `
                -FailureStage 'vpax-validation'
        }
        $vpaxStatus = 'captured-without-data-stat-scans'
    }

    $coverage = [pscustomobject][ordered]@{
        schemaVersion = 1
        semanticModel = 'captured'
        reportLayer   = 'not-collected'
        businessData  = 'not-collected'
        credentials   = 'not-requested-raw-metadata-may-contain-embedded-secrets'
        agentArtifacts = 'redacted'
        vpax           = $vpaxStatus
        boundaries     = @(
            'Pages, visuals, layout, visual bindings, report filters, slicers, interactions, and bookmarks are not captured.',
            'Semantic metadata alone cannot recreate a complete PBIX.'
        )
    }
    $coveragePath = Join-Path $runFolder 'coverage.json'
    Write-JsonFile -Path $coveragePath -InputObject $coverage -Depth 8

    $normalizedText = Get-Content -LiteralPath $normalizedModelPath -Raw -Encoding UTF8
    Assert-AgentFacingTextSafe -Text $normalizedText -ArtifactName 'normalized/model.redacted.json'
    Assert-AgentFacingTextSafe -Text (Get-Content -LiteralPath $coveragePath -Raw -Encoding UTF8) -ArtifactName 'coverage.json'

    $handoffText = New-GenieHandoff -NormalizedModel $normalizedModel -PbixName $runState.selectedPbixName
    $handoffText = Protect-PbixIntakeText -Text ([string]$handoffText)
    Assert-HandoffScope -Text $handoffText
    Assert-AgentFacingTextSafe -Text $handoffText -ArtifactName 'GENIE_HANDOFF.md'
    Write-Utf8NoBom -Path $handoffTemporaryPath -Text $handoffText
    Move-Item -LiteralPath $handoffTemporaryPath -Destination $handoffPath

    $manifestPath = Join-Path $runFolder 'manifest.json'
    $null = New-PbixIntakeManifest -RootPath $runFolder -OutputPath $manifestPath -ExcludeRelativePath 'run.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        (Get-Item -LiteralPath $manifestPath).Length -le 0) {
        throw 'Manifest generation did not produce a nonempty manifest.json.'
    }
    $null = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop

    $runState.status = 'succeeded'
    $runState.result = 'PASS'
    $runState.blockerCode = $null
    $runState.message = 'The full TOM/TMDL semantic metadata was captured and the redacted Genie handoff passed validation.'
    $runState.nextAction = 'Give Genie the handoff, coverage file, and normalized artifacts. Supply report-layer context separately if needed.'
    $runState.failureStage = $null
    $runState.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    Save-RunState
    $scriptSucceeded = $true
}
catch {
    $failure = $null
    try {
        if (Get-Command -Name Get-PbixIntakeFailureInfo -ErrorAction SilentlyContinue) {
            $failure = Get-PbixIntakeFailureInfo -Exception $_.Exception
        }
    }
    catch { }

    if ($null -eq $failure) {
        $failure = [pscustomobject]@{
            blockerCode = 'UNCLASSIFIED_FAILURE'
            message     = $_.Exception.Message
            nextAction  = 'Preserve the complete run folder and extend the failure catalog before retrying.'
            failureStage = 'runtime'
            retryable   = $false
            requiresIT  = $false
        }
    }

    $runState.status = 'failed'
    $runState.result = 'FAIL'
    $runState.blockerCode = [string](Get-SafePropertyValue -InputObject $failure -Names @('blockerCode', 'BlockerCode'))
    if ([string]::IsNullOrWhiteSpace($runState.blockerCode)) { $runState.blockerCode = 'UNCLASSIFIED_FAILURE' }
    $runState.message = [string](Get-SafePropertyValue -InputObject $failure -Names @('message', 'Message'))
    if ([string]::IsNullOrWhiteSpace($runState.message)) { $runState.message = $_.Exception.Message }
    $runState.nextAction = [string](Get-SafePropertyValue -InputObject $failure -Names @('nextAction', 'NextAction'))
    if ([string]::IsNullOrWhiteSpace($runState.nextAction)) {
        $runState.nextAction = 'Preserve the complete run folder and extend the failure catalog before retrying.'
    }
    $runState.failureStage = [string](Get-SafePropertyValue -InputObject $failure -Names @('failureStage', 'FailureStage'))
    $retryableValue = Get-SafePropertyValue -InputObject $failure -Names @('retryable', 'Retryable')
    $requiresITValue = Get-SafePropertyValue -InputObject $failure -Names @('requiresIT', 'RequiresIT')
    $runState.retryable = if ($null -eq $retryableValue) { $false } else { [bool]$retryableValue }
    $runState.requiresIT = if ($null -eq $requiresITValue) { $false } else { [bool]$requiresITValue }
    $runState.finishedAtUtc = [DateTime]::UtcNow.ToString('o')

    if (Test-Path -LiteralPath $handoffPath -PathType Leaf) {
        Remove-Item -LiteralPath $handoffPath -Force
    }
    if (Test-Path -LiteralPath $handoffTemporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $handoffTemporaryPath -Force
    }
    Save-CommandTrail
    Save-RunState
}
finally {
    if ($ownsMutex -and $null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $mutex) {
        $mutex.Dispose()
    }
    if (Test-Path -LiteralPath $handoffTemporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $handoffTemporaryPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not $scriptSucceeded) {
    Write-Error ("{0}: {1} Next action: {2} Run folder: {3}" -f $runState.blockerCode, $runState.message, $runState.nextAction, $runFolder)
    exit 1
}

Write-Output $runFolder
