[CmdletBinding(DefaultParameterSetName = "Desktop")]
param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true, ParameterSetName = "Desktop")][string]$PbixName,
    [Parameter(Mandatory = $true, ParameterSetName = "Service")][string]$ModelServer,
    [Parameter(Mandatory = $true, ParameterSetName = "Service")][string]$ModelName,
    [string]$EnvPath,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$AttemptLabel = "default",
    [ValidateRange(15, 1800)][int]$TimeoutSeconds = 180
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Import-ToolkitEnvironment -EnvPath $EnvPath

$scriptFullPath = Resolve-ToolkitInputPath -Path $ScriptPath
$allowedScript = [System.IO.Path]::GetFullPath(
    (Join-Path (Get-ToolkitRoot) "te2\readonly\export_model_inventory.csx")
)

if (-not $scriptFullPath.Equals($allowedScript, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The TE2 wrapper only permits te2\readonly\export_model_inventory.csx."
}
if (-not (Test-Path -LiteralPath $scriptFullPath -PathType Leaf)) {
    throw "TE2 exporter script not found."
}

Assert-ToolkitExecutionFilesClean

$outputFullPath = Resolve-ToolkitOutputPath -Path $OutputDirectory
New-Item -ItemType Directory -Path $outputFullPath -Force | Out-Null

Assert-ExecutableFile `
    -Path $env:TE2_EXE_PATH `
    -VariableName "TE2_EXE_PATH" `
    -ExpectedFileName "TabularEditor.exe"
Assert-MinimumFileVersion `
    -Path $env:TE2_EXE_PATH `
    -MinimumVersion ([version]"2.28.0") `
    -ProductName "Tabular Editor 2" `
    -PublisherRegex '(?i)Tabular Editor|twoday|Kapacity'
$te2 = $env:TE2_EXE_PATH

# TE2 is a WinForms executable. Start-Process + WaitForExit is intentional:
# direct invocation can return control before TE2 has finished the C# script.
$nativeArguments = New-Object System.Collections.Generic.List[string]
if ($PSCmdlet.ParameterSetName -eq "Desktop") {
    $normalized = Normalize-PbixName -PbixName $PbixName
    $nativeArguments.Add("-L")
    $nativeArguments.Add((Quote-NativeArgument -Value $normalized))
}
else {
    $nativeArguments.Add((Quote-NativeArgument -Value $ModelServer))
    $nativeArguments.Add((Quote-NativeArgument -Value $ModelName))
}
$nativeArguments.Add("-S")
$nativeArguments.Add((Quote-NativeArgument -Value $scriptFullPath))

$stdoutPath = Join-Path $outputFullPath ("_te2_{0}_stdout.log" -f $AttemptLabel)
$stderrPath = Join-Path $outputFullPath ("_te2_{0}_stderr.log" -f $AttemptLabel)
Remove-StaleFile -Path $stdoutPath
Remove-StaleFile -Path $stderrPath

$previousOutputDirectory = [System.Environment]::GetEnvironmentVariable("TE2_OUTPUT_DIR", "Process")
[System.Environment]::SetEnvironmentVariable("TE2_OUTPUT_DIR", $outputFullPath, "Process")

try {
    $process = Start-Process `
        -FilePath $te2 `
        -ArgumentList ($nativeArguments -join " ") `
        -WorkingDirectory (Get-ToolkitRoot) `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    # Force acquisition of the native process handle before the short-lived
    # WinForms process exits. Without this, Windows PowerShell 5.1 can report a
    # null ExitCode after a timed WaitForExit call.
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch { }
        throw "Tabular Editor timed out after $TimeoutSeconds seconds. Check $stderrPath and $stdoutPath."
    }
    # The parameterless wait flushes redirected streams and makes ExitCode
    # available reliably on Windows PowerShell 5.1 after the timed wait.
    $process.WaitForExit()
    $process.Refresh()

    $stdout = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { (Get-Content -LiteralPath $stdoutPath -Raw | Out-String).Trim() } else { "" }
    $stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { (Get-Content -LiteralPath $stderrPath -Raw | Out-String).Trim() } else { "" }
    $diagnostic = @($stderr, $stdout) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $diagnosticText = if (@($diagnostic).Count -gt 0) { @($diagnostic) -join " | " } else { "No diagnostic output from Tabular Editor." }

    if ($process.ExitCode -ne 0) {
        throw "Tabular Editor exited with code $($process.ExitCode). $diagnosticText"
    }

    $tablesCsv = Join-Path $outputFullPath "tables.csv"
    if (-not (Test-Path -LiteralPath $tablesCsv -PathType Leaf)) {
        throw "Tabular Editor exited successfully but did not create the expected metadata files. $diagnosticText"
    }
}
finally {
    [System.Environment]::SetEnvironmentVariable(
        "TE2_OUTPUT_DIR",
        $previousOutputDirectory,
        "Process"
    )
}
