$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$CliArguments = @($args)

function Test-SimulatorPython {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [switch] $RequireHttps
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $probe = if ($RequireHttps) {
        'import ssl,sys,urllib.request; raise SystemExit(0 if sys.version_info >= (3,9) and hasattr(ssl,"SSLContext") else 1)'
    }
    else {
        'import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)'
    }

    & $Path -c $probe 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Find-SimulatorPython {
    param([switch] $RequireHttps)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'))
        $candidates.Add((Join-Path $env:USERPROFILE 'anaconda3\python.exe'))
        $candidates.Add((Join-Path $env:USERPROFILE 'miniconda3\python.exe'))
    }
    if ($env:LOCALAPPDATA) {
        Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Filter python.exe -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates.Add($_.FullName) }
    }
    Get-Command python.exe -All -ErrorAction SilentlyContinue |
        ForEach-Object { if ($_.Source) { $candidates.Add($_.Source) } }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -like '*\Microsoft\WindowsApps\python*.exe') {
            continue
        }
        if (Test-SimulatorPython -Path $candidate -RequireHttps:$RequireHttps) {
            return $candidate
        }
    }

    $capability = if ($RequireHttps) { 'Python 3.9+ with SSL/HTTPS support' } else { 'Python 3.9+' }
    throw "Unable to find $capability. No installer or network fallback was attempted."
}

$isDocsSync = $CliArguments.Count -ge 2 -and $CliArguments[0] -eq 'docs' -and $CliArguments[1] -eq 'sync'
$isSelfTest = $CliArguments.Count -eq 2 -and $CliArguments[0] -eq 'sim' -and $CliArguments[1] -eq 'self-test'
$pythonPath = Find-SimulatorPython -RequireHttps:$isDocsSync
$exitCode = 1
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    if ($isDocsSync) {
        $syncArguments = if ($CliArguments.Count -gt 2) { $CliArguments[2..($CliArguments.Count - 1)] } else { @() }
        & $pythonPath (Join-Path $PSScriptRoot 'scripts\sync_official_docs.py') @syncArguments
    }
    elseif ($isSelfTest) {
        Push-Location -LiteralPath $PSScriptRoot
        try {
            & $pythonPath -m unittest discover -s tests -p 'test_*.py' -v
        }
        finally {
            Pop-Location
        }
    }
    else {
        $entryPoint = 'import sys; root=sys.argv.pop(1); sys.path.insert(0,root); from simulator.cli import main; raise SystemExit(main(sys.argv[1:]))'
        & $pythonPath -c $entryPoint $PSScriptRoot @CliArguments
    }
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $savedErrorActionPreference
}

exit $exitCode
