[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$QueryFile,
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$Database,
    [string]$OutputCsv,
    [string]$EnvPath,
    [ValidateRange(15, 1800)][int]$TimeoutSeconds = 180
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Import-ToolkitEnvironment -EnvPath $EnvPath
Assert-ToolkitRuntimeFilesPresent
Assert-ToolkitExecutionFilesClean

$queryFullPath = Resolve-ToolkitInputPath -Path $QueryFile
if (-not (Test-Path -LiteralPath $queryFullPath -PathType Leaf)) {
    throw "DAX query file not found."
}

$queryText = Get-Content -LiteralPath $queryFullPath -Raw
if ($queryText -match '@@[A-Z0-9_]+@@') {
    throw "DAX query contains unresolved template tokens."
}
$queryHashBefore = (Get-FileHash -LiteralPath $queryFullPath -Algorithm SHA256).Hash
$connectionTestPath = [System.IO.Path]::GetFullPath(
    (Join-Path (Get-ToolkitRoot) "dax\queries\connection_test.dax")
)
$isConnectionTest = $queryFullPath.Equals(
    $connectionTestPath,
    [System.StringComparison]::OrdinalIgnoreCase
)

$toolkitRoot = (Get-ToolkitRoot).TrimEnd([char[]]@('\', '/'))
$toolkitPrefix = $toolkitRoot + [System.IO.Path]::DirectorySeparatorChar
$queryIsInsideToolkit = $queryFullPath.Equals(
    $toolkitRoot,
    [System.StringComparison]::OrdinalIgnoreCase
) -or $queryFullPath.StartsWith(
    $toolkitPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)
if (-not $isConnectionTest -and $queryIsInsideToolkit) {
    throw "Non-test DAX queries must be reviewed copies outside the toolkit folder, normally under EVIDENCE_ROOT."
}

$requestedServer = $Server
$requestedDatabase = $Database
$resolvedConnection = $null
$desktopFileName = $null

if ($Server -match '(?i)\.(pbix|pbip)$') {
    if ($Server -match '[\\/]') {
        throw "For Power BI Desktop, Server must be the PBIX/PBIP filename without its path."
    }
    $desktopFileName = [System.IO.Path]::GetFileName($Server)
    Assert-UniqueOpenPowerBIDesktopFileName -FileName $desktopFileName
}
elseif ($Server -match '(?i)^localhost:(\d+)$') {
    if ([string]::IsNullOrWhiteSpace($Database)) {
        $port = [regex]::Match($Server, '(?i)^localhost:(\d+)$').Groups[1].Value
        $context = Resolve-LocalDesktopContextByPort -Port $port
        $Database = $context.Catalog
    }
    $resolvedConnection = [ordered]@{
        type = "power-bi-desktop"
        server = $Server
        database = $Database
        resolution = "explicit-localhost"
    }
}
else {
    if ([string]::IsNullOrWhiteSpace($Database)) {
        throw "Database is required for non-Desktop connections."
    }
    $resolvedConnection = [ordered]@{
        type = "xmla-or-analysis-services"
        server = $Server
        database = $Database
        resolution = "explicit-server-database"
    }
}

if ([string]::IsNullOrWhiteSpace($OutputCsv)) {
    $evidenceRoot = Get-ConfiguredEvidenceRoot
    $outputName = "dax_query_{0}.csv" -f (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
    $OutputCsv = Join-Path $evidenceRoot $outputName
}

$outputFullPath = Resolve-ToolkitOutputPath -Path $OutputCsv
if (-not [System.IO.Path]::GetExtension($outputFullPath).Equals(".csv", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputCsv must use a .csv extension."
}

$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Remove-StaleFile -Path $outputFullPath
$manifestPath = [System.IO.Path]::ChangeExtension($outputFullPath, ".manifest.json")
Remove-StaleFile -Path $manifestPath

Assert-ExecutableFile `
    -Path $env:DSCMD_EXE_PATH `
    -VariableName "DSCMD_EXE_PATH" `
    -ExpectedFileName "dscmd.exe"
Assert-MinimumFileVersion `
    -Path $env:DSCMD_EXE_PATH `
    -MinimumVersion ([version]"3.3.0") `
    -ProductName "DAX Studio" `
    -PublisherRegex '(?i)SQL\s*BI|SQLBI'
$daxStudioVersion = Get-ExecutableFileVersion `
    -Path $env:DSCMD_EXE_PATH `
    -ProductName "DAX Studio"

function Invoke-DscmdAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$AttemptServer,
        [string]$AttemptDatabase,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$AttemptLabel
    )

    Remove-StaleFile -Path $outputFullPath
    $stdoutPath = [System.IO.Path]::ChangeExtension($outputFullPath, ".dscmd-${AttemptLabel}.stdout.log")
    $stderrPath = [System.IO.Path]::ChangeExtension($outputFullPath, ".dscmd-${AttemptLabel}.stderr.log")
    Remove-StaleFile -Path $stdoutPath
    Remove-StaleFile -Path $stderrPath

    # -f passes a query file. -q would treat the path itself as inline DAX.
    $arguments = New-Object System.Collections.Generic.List[string]
    foreach ($value in @("csv", $outputFullPath, "-s", $AttemptServer)) {
        $arguments.Add((Quote-NativeArgument -Value ([string]$value))) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($AttemptDatabase)) {
        $arguments.Add("-d") | Out-Null
        $arguments.Add((Quote-NativeArgument -Value $AttemptDatabase)) | Out-Null
    }
    $arguments.Add("-f") | Out-Null
    $arguments.Add((Quote-NativeArgument -Value $queryFullPath)) | Out-Null

    $startedAtUtc = [datetime]::UtcNow
    $process = Start-Process `
        -FilePath $env:DSCMD_EXE_PATH `
        -ArgumentList ($arguments -join " ") `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
    $null = $process.Handle
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch { }
        $exitCode = -2
    }
    else {
        $process.WaitForExit()
        $process.Refresh()
        $exitCode = $process.ExitCode
    }

    $stdout = if (Test-Path -LiteralPath $stdoutPath) { (Get-Content -LiteralPath $stdoutPath -Raw | Out-String).Trim() } else { "" }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Raw | Out-String).Trim() } else { "" }
    $combined = (@($stderr, $stdout) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " | "
    if ($timedOut) { $combined = "Timed out after $TimeoutSeconds seconds. $combined".Trim() }
    $outputReady = Test-Path -LiteralPath $outputFullPath -PathType Leaf
    if ($outputReady) { $outputReady = (Get-Item -LiteralPath $outputFullPath).Length -gt 0 }

    return [pscustomobject]@{
        exitCode = $exitCode
        timedOut = $timedOut
        succeeded = ($exitCode -eq 0 -and $outputReady)
        output = $combined
        startedAtUtc = $startedAtUtc
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
    }
}

$attempt = $null
if ($desktopFileName) {
    $nativeAttempt = Invoke-DscmdAttempt -AttemptServer $desktopFileName -AttemptLabel "desktop-filename"
    if ($nativeAttempt.succeeded) {
        $attempt = $nativeAttempt
        $resolvedConnection = [ordered]@{
            type = "power-bi-desktop"
            pbixName = $desktopFileName
            server = $desktopFileName
            database = $null
            resolution = "dscmd-native-filename"
        }
    }
    elseif ($desktopFileName -match '(?i)\.pbix$') {
        $context = Resolve-LocalDesktopModelContext -PbixName $desktopFileName
        $Server = "localhost:$($context.Port)"
        $Database = $context.Catalog
        $fallbackAttempt = Invoke-DscmdAttempt -AttemptServer $Server -AttemptDatabase $Database -AttemptLabel "localhost-catalog"
        if (-not $fallbackAttempt.succeeded) {
            throw "dscmd filename attempt failed: $($nativeAttempt.output) | localhost/catalog attempt failed: $($fallbackAttempt.output)"
        }
        $attempt = $fallbackAttempt
        $resolvedConnection = [ordered]@{
            type = "power-bi-desktop"
            pbixName = $desktopFileName
            server = $Server
            portSource = $context.PortSource
            database = $Database
            modelName = $context.DatabaseName
            resolution = "localhost-port-catalog-fallback"
        }
    }
    else {
        throw "dscmd PBIP filename attempt failed: $($nativeAttempt.output)"
    }
}
else {
    $attempt = Invoke-DscmdAttempt -AttemptServer $Server -AttemptDatabase $Database -AttemptLabel "explicit-connection"
    if (-not $attempt.succeeded) {
        throw "dscmd failed with exit code $($attempt.exitCode). $($attempt.output)"
    }
}
$toolOutput = $attempt.output

Assert-NonEmptyFile -Path $outputFullPath
$outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($outputFullPath)
$unexpectedResultFiles = @(
    Get-ChildItem -LiteralPath $outputDirectory -File -Filter "${outputBaseName}*.csv" -ErrorAction SilentlyContinue |
        Where-Object { -not $_.FullName.Equals($outputFullPath, [System.StringComparison]::OrdinalIgnoreCase) -and $_.LastWriteTimeUtc -ge $attempt.startedAtUtc.AddSeconds(-1) }
)
if ($unexpectedResultFiles.Count -gt 0) {
    throw "dscmd produced additional unmanifested result files: $($unexpectedResultFiles.Name -join ', ')"
}
$listSeparator = [System.Globalization.CultureInfo]::CurrentUICulture.TextInfo.ListSeparator
if ([string]::IsNullOrWhiteSpace($listSeparator) -or $listSeparator.Length -ne 1) {
    throw "The current Windows list separator is not supported for CSV validation."
}
$delimiter = [char]$listSeparator
try {
    $rows = @(Import-Csv -LiteralPath $outputFullPath -Delimiter $delimiter)
    $rowCount = $rows.Count
}
catch {
    throw "DAX output CSV validation failed: $($_.Exception.Message)"
}

if ($isConnectionTest) {
    if ($rows.Count -ne 1) {
        throw "DAX connection test returned an unexpected row count."
    }
    $connectionProperty = $rows[0].PSObject.Properties |
        Where-Object { $_.Name.Trim([char[]]@('[', ']')) -eq "ToolkitConnection" } |
        Select-Object -First 1
    if ($null -eq $connectionProperty -or [string]$connectionProperty.Value -ne "OK") {
        throw "DAX connection test did not return ToolkitConnection=OK."
    }
}

$queryHashAfter = (Get-FileHash -LiteralPath $queryFullPath -Algorithm SHA256).Hash
if ($queryHashAfter -ne $queryHashBefore) {
    throw "The DAX query file changed during execution. Discard the output and rerun."
}

$item = Get-Item -LiteralPath $outputFullPath
$hash = Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256
$manifest = [ordered]@{
    schemaVersion = 2
    status = "succeeded"
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    toolkitVersion = (Get-ToolkitVersion)
    toolkitCommit = (Get-ToolkitCommit)
    tool = [ordered]@{
        name = "DAX Studio dscmd"
        version = $daxStudioVersion
    }
    requestedConnection = [ordered]@{
        server = $requestedServer
        database = $requestedDatabase
    }
    connection = $resolvedConnection
    query = [ordered]@{
        path = $queryFullPath
        sha256 = $queryHashBefore
    }
    validation = [ordered]@{
        connectionTest = if ($isConnectionTest) { "passed" } else { "not-applicable" }
    }
    output = [ordered]@{
        name = [System.IO.Path]::GetFileName($outputFullPath)
        delimiter = $listSeparator
        rowCount = $rowCount
        bytes = $item.Length
        sha256 = $hash.Hash
    }
}

$manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Assert-NonEmptyFile -Path $manifestPath
$verifiedManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($verifiedManifest.status -ne "succeeded" -or
    $verifiedManifest.query.sha256 -ne $queryHashBefore -or
    $verifiedManifest.output.sha256 -ne $hash.Hash) {
    throw "DAX manifest validation failed."
}

Write-Host "DAX export complete: $outputFullPath"
Write-Host "Rows: $rowCount"
Write-Output $manifestPath
