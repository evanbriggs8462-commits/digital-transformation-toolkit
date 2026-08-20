[CmdletBinding(DefaultParameterSetName = "Desktop")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Desktop")][string]$PbixName,
    [Parameter(Mandatory = $true, ParameterSetName = "Service")][string]$ModelServer,
    [Parameter(Mandatory = $true, ParameterSetName = "Service")][string]$ModelName,
    [string]$OutDir,
    [string]$EnvPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Import-ToolkitEnvironment -EnvPath $EnvPath
Assert-ToolkitRuntimeFilesPresent
Assert-ToolkitExecutionFilesClean

if ($PSCmdlet.ParameterSetName -eq "Desktop") {
    $PbixName = Normalize-PbixName -PbixName $PbixName
    Assert-UniqueOpenPowerBIDesktopFileName -FileName $PbixName
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $evidenceRoot = Get-ConfiguredEvidenceRoot
    $connectionName = if ($PSCmdlet.ParameterSetName -eq "Desktop") {
        [System.IO.Path]::GetFileNameWithoutExtension($PbixName)
    }
    else {
        $ModelName
    }
    $safeName = Get-SafeArtifactName -Value $connectionName
    $runName = "inventory_{0}_{1}" -f $safeName, (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
    $OutDir = Join-Path $evidenceRoot $runName
}

$outputFullPath = Resolve-ToolkitOutputPath -Path $OutDir
New-Item -ItemType Directory -Path $outputFullPath -Force | Out-Null

$expectedArtifacts = @(
    [pscustomobject]@{ Name = "tables.csv"; Header = '"Table","ObjectType","IsHidden","Description"' },
    [pscustomobject]@{ Name = "measures.csv"; Header = '"Table","Measure","DisplayFolder","FormatString","IsHidden","Description","Expression"' },
    [pscustomobject]@{ Name = "columns.csv"; Header = '"Table","Column","ColumnType","DataType","IsHidden","DisplayFolder","SortByColumn","Description","Expression"' },
    [pscustomobject]@{ Name = "relationships.csv"; Header = '"FromTable","FromColumn","ToTable","ToColumn","IsActive","CrossFilteringBehavior"' },
    [pscustomobject]@{ Name = "partitions.csv"; Header = '"Table","Partition","Mode","SourceType","Expression"' },
    [pscustomobject]@{ Name = "expressions.csv"; Header = '"Expression","Kind","Description","Definition"' }
)

$manifestPath = Join-Path $outputFullPath "inventory_manifest.json"
foreach ($artifact in $expectedArtifacts) {
    Remove-StaleFile -Path (Join-Path $outputFullPath $artifact.Name)
}
Remove-StaleFile -Path $manifestPath

$exporterPath = Join-Path (Get-ToolkitRoot) "te2\readonly\export_model_inventory.csx"
$exporterHashBefore = (Get-FileHash -LiteralPath $exporterPath -Algorithm SHA256).Hash
$invokeScript = Join-Path $PSScriptRoot "invoke_te2_readonly.ps1"
$resolvedConnection = $null

if ($PSCmdlet.ParameterSetName -eq "Desktop") {
    $nameAttemptError = $null
    try {
        & $invokeScript `
            -ScriptPath $exporterPath `
            -OutputDirectory $outputFullPath `
            -EnvPath $EnvPath `
            -AttemptLabel "pbix-name" `
            -PbixName $PbixName

        $resolvedConnection = [ordered]@{
            type = "power-bi-desktop"
            pbixName = $PbixName
            resolution = "te2-local-name"
        }
    }
    catch {
        $nameAttemptError = $_.Exception.Message
        foreach ($artifact in $expectedArtifacts) {
            Remove-StaleFile -Path (Join-Path $outputFullPath $artifact.Name)
        }

        try {
            $localContext = Resolve-LocalDesktopModelContext -PbixName $PbixName
            & $invokeScript `
                -ScriptPath $exporterPath `
                -OutputDirectory $outputFullPath `
                -EnvPath $EnvPath `
                -AttemptLabel "localhost-catalog" `
                -ModelServer "localhost:$($localContext.Port)" `
                -ModelName $localContext.Catalog

            $resolvedConnection = [ordered]@{
                type = "power-bi-desktop"
                pbixName = $PbixName
                resolution = "localhost-port-catalog-fallback"
                server = "localhost:$($localContext.Port)"
                portSource = $localContext.PortSource
                model = $localContext.Catalog
                modelName = $localContext.DatabaseName
                desktopProcessId = $localContext.ParentProcessId
                analysisServicesProcessId = $localContext.ProcessId
                nameAttemptError = $nameAttemptError
            }
        }
        catch {
            $fallbackError = $_.Exception.Message
            throw "PBIX-name connection failed: $nameAttemptError | Local port/catalog fallback failed: $fallbackError"
        }
    }
}
else {
    & $invokeScript `
        -ScriptPath $exporterPath `
        -OutputDirectory $outputFullPath `
        -EnvPath $EnvPath `
        -ModelServer $ModelServer `
        -ModelName $ModelName

    $resolvedConnection = [ordered]@{
        type = "xmla"
        server = $ModelServer
        model = $ModelName
        resolution = "explicit-server-model"
    }
}

$te2Version = Get-ExecutableFileVersion `
    -Path $env:TE2_EXE_PATH `
    -ProductName "Tabular Editor 2"
$exporterHashAfter = (Get-FileHash -LiteralPath $exporterPath -Algorithm SHA256).Hash
if ($exporterHashAfter -ne $exporterHashBefore) {
    throw "The Tabular Editor exporter changed during execution. Discard the output and rerun."
}

$artifacts = New-Object System.Collections.Generic.List[object]
foreach ($expected in $expectedArtifacts) {
    $path = Join-Path $outputFullPath $expected.Name
    Assert-NonEmptyFile -Path $path

    $header = Get-Content -LiteralPath $path -TotalCount 1
    if ($header -ne $expected.Header) {
        throw "Unexpected CSV header in $($expected.Name)."
    }

    try {
        $rowCount = @(Import-Csv -LiteralPath $path).Count
    }
    catch {
        throw "CSV validation failed for $($expected.Name): $($_.Exception.Message)"
    }
    if ($expected.Name -eq "tables.csv" -and $rowCount -lt 1) {
        throw "Inventory did not contain any model tables."
    }

    $item = Get-Item -LiteralPath $path
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    $artifacts.Add([pscustomobject]@{
        name = $expected.Name
        rowCount = $rowCount
        bytes = $item.Length
        sha256 = $hash.Hash
    }) | Out-Null
}

$manifest = [ordered]@{
    schemaVersion = 2
    status = "succeeded"
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    toolkitVersion = (Get-ToolkitVersion)
    toolkitCommit = (Get-ToolkitCommit)
    tool = [ordered]@{
        name = "Tabular Editor 2"
        version = $te2Version
    }
    exporter = [ordered]@{
        path = "te2/readonly/export_model_inventory.csx"
        sha256 = $exporterHashBefore
    }
    connection = $resolvedConnection
    artifacts = @($artifacts | ForEach-Object { $_ })
}

$manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Assert-NonEmptyFile -Path $manifestPath
$verifiedManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($verifiedManifest.status -ne "succeeded" -or
    $verifiedManifest.exporter.sha256 -ne $exporterHashBefore -or
    @($verifiedManifest.artifacts).Count -ne 6) {
    throw "Inventory manifest validation failed."
}

Write-Host "Inventory complete: $outputFullPath"
foreach ($artifact in $artifacts) {
    $artifactPath = Join-Path $outputFullPath $artifact.name
    $verifiedHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
    if (-not $verifiedHash.Equals([string]$artifact.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Inventory artifact changed after manifest creation: $($artifact.name)"
    }
    Write-Host ("- {0}: {1} rows" -f $artifact.name, $artifact.rowCount)
}
Write-Output $manifestPath
