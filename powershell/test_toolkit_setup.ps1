[CmdletBinding()]
param(
    [switch]$InventoryOnly,
    [string]$EnvPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Action
    )

    $checks.Add([pscustomobject]@{
        Check = $Name
        Status = $Status
        Action = $Action
    }) | Out-Null
}

if ($PSVersionTable.PSVersion -ge [version]"5.1") {
    Add-Check -Name "PowerShell 5.1+" -Status "PASS" -Action ""
}
else {
    Add-Check -Name "PowerShell 5.1+" -Status "FAIL" -Action "PowerShell 5.1 or later is required."
}

try {
    Assert-ToolkitRuntimeFilesPresent
    Add-Check -Name "Runtime files" -Status "PASS" -Action ""
}
catch {
    Add-Check -Name "Runtime files" -Status "FAIL" -Action $_.Exception.Message
}

try {
    $syntaxErrors = New-Object System.Collections.Generic.List[string]
    foreach ($scriptFile in Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptFile.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null
        foreach ($parseError in @($parseErrors)) {
            $syntaxErrors.Add(("{0}: {1}" -f $scriptFile.Name, $parseError.Message)) | Out-Null
        }
    }

    $startHere = Join-Path (Get-ToolkitRoot) "START_HERE.ps1"
    if (Test-Path -LiteralPath $startHere -PathType Leaf) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $startHere,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null
        foreach ($parseError in @($parseErrors)) {
            $syntaxErrors.Add(("START_HERE.ps1: {0}" -f $parseError.Message)) | Out-Null
        }
    }

    if ($syntaxErrors.Count -gt 0) {
        throw ($syntaxErrors -join "; ")
    }
    Add-Check -Name "PowerShell syntax" -Status "PASS" -Action ""
}
catch {
    Add-Check -Name "PowerShell syntax" -Status "FAIL" -Action $_.Exception.Message
}

try {
    Assert-ToolkitExecutionFilesClean
    $mode = if ([System.Environment]::GetEnvironmentVariable("TOOLKIT_ENFORCE_GIT_CLEAN", "Process") -eq "1") {
        "Git-clean enforcement enabled"
    }
    else {
        "SharePoint/download mode; Git not required"
    }
    Add-Check -Name "Execution-file policy" -Status "PASS" -Action $mode
}
catch {
    Add-Check -Name "Execution-file policy" -Status "FAIL" -Action $_.Exception.Message
}

try {
    Import-ToolkitEnvironment -EnvPath $EnvPath
    Add-Check -Name ".env" -Status "PASS" -Action ""
}
catch {
    Add-Check -Name ".env" -Status "FAIL" -Action $_.Exception.Message
}

if (($checks | Where-Object { $_.Check -eq ".env" }).Status -eq "PASS") {
    try {
        Assert-ExecutableFile `
            -Path $env:TE2_EXE_PATH `
            -VariableName "TE2_EXE_PATH" `
            -ExpectedFileName "TabularEditor.exe"
        Assert-MinimumFileVersion `
            -Path $env:TE2_EXE_PATH `
            -MinimumVersion ([version]"2.28.0") `
            -ProductName "Tabular Editor 2" `
            -PublisherRegex '(?i)Tabular Editor|twoday|Kapacity'
        Add-Check -Name "Tabular Editor 2" -Status "PASS" -Action ""
    }
    catch {
        Add-Check -Name "Tabular Editor 2" -Status "FAIL" -Action $_.Exception.Message
    }

    if ($InventoryOnly) {
        Add-Check -Name "DAX Studio dscmd" -Status "SKIP" -Action "Inventory-only preflight"
    }
    else {
        try {
            Assert-ExecutableFile `
                -Path $env:DSCMD_EXE_PATH `
                -VariableName "DSCMD_EXE_PATH" `
                -ExpectedFileName "dscmd.exe"
            Assert-MinimumFileVersion `
                -Path $env:DSCMD_EXE_PATH `
                -MinimumVersion ([version]"3.3.0") `
                -ProductName "DAX Studio" `
                -PublisherRegex '(?i)SQL\s*BI|SQLBI'
            Add-Check -Name "DAX Studio dscmd" -Status "PASS" -Action ""
        }
        catch {
            Add-Check -Name "DAX Studio dscmd" -Status "FAIL" -Action $_.Exception.Message
        }
    }

    try {
        $evidenceRoot = Get-ConfiguredEvidenceRoot
        New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
        $probe = Join-Path $evidenceRoot ("toolkit_write_test_{0}.tmp" -f [guid]::NewGuid().ToString("N"))
        try {
            [System.IO.File]::WriteAllText($probe, "ok")
        }
        finally {
            if (Test-Path -LiteralPath $probe -PathType Leaf) {
                Remove-Item -LiteralPath $probe -Force
            }
        }
        Add-Check -Name "Evidence folder" -Status "PASS" -Action ""
    }
    catch {
        Add-Check -Name "Evidence folder" -Status "FAIL" -Action $_.Exception.Message
    }
}

try {
    $queryPath = Join-Path (Get-ToolkitRoot) "dax\queries\connection_test.dax"
    $queryText = (Get-Content -LiteralPath $queryPath -Raw).Trim()
    if ($queryText -notmatch '(?is)^EVALUATE\s+ROW\s*\(\s*"ToolkitConnection"\s*,\s*"OK"\s*\)\s*$') {
        throw "connection_test.dax is not the canonical ToolkitConnection=OK query."
    }
    Add-Check -Name "DAX connection-test query" -Status "PASS" -Action ""
}
catch {
    Add-Check -Name "DAX connection-test query" -Status "FAIL" -Action $_.Exception.Message
}

foreach ($check in $checks) {
    if ([string]::IsNullOrWhiteSpace($check.Action)) {
        Write-Host ("[{0}] {1}" -f $check.Status, $check.Check)
    }
    else {
        Write-Host ("[{0}] {1}: {2}" -f $check.Status, $check.Check, $check.Action)
    }
}

if (@($checks | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
    throw "Toolkit preflight failed. Fix every FAIL result and rerun START_HERE.ps1."
}

Write-Host "Toolkit preflight passed."
