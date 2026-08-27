[CmdletBinding()]
param(
    [string]$ModulePath,
    [string]$ResultsRoot,
    [switch]$KeepSandbox
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$provisioningScriptPath = Join-Path $repositoryRoot 'Install-PbixIntakeTools.Once.ps1'
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $repositoryRoot 'powershell\PbixIntake.Core.psm1'
}
if ([string]::IsNullOrWhiteSpace($ResultsRoot)) {
    $ResultsRoot = Join-Path $PSScriptRoot 'results'
}

if (-not (Test-Path -LiteralPath $ResultsRoot -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $ResultsRoot -Force
}
$resolvedResultsRoot = (Resolve-Path -LiteralPath $ResultsRoot).Path
$resultPath = Join-Path $resolvedResultsRoot 'adversarial-results.json'
$sandboxRoot = Join-Path $resolvedResultsRoot ('sandbox-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandboxRoot

$script:testResults = @()

function Write-TestUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "ASSERT_TRUE_FAILED: $Message"
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ([string]$Actual -cne [string]$Expected) {
        throw "ASSERT_EQUAL_FAILED: $Message Expected='$Expected' Actual='$Actual'"
    }
}

function Assert-SequenceEqual {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Assert-Equal -Actual $Actual.Count -Expected $Expected.Count -Message "$Message (element count)"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-Equal -Actual $Actual[$index] -Expected $Expected[$index] -Message "$Message (element $index)"
    }
}

function Assert-NoToken {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string[]]$Forbidden,
        [Parameter(Mandatory = $true)][string]$Message
    )

    foreach ($token in $Forbidden) {
        if ($Arguments -contains $token) {
            throw "ASSERT_FORBIDDEN_TOKEN: $Message Found '$token' in: $($Arguments -join ' | ')"
        }
    }
}

function Assert-OptionValue {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string[]]$Aliases,
        [Parameter(Mandatory = $true)][string]$ExpectedValue,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $matches = @()
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        if ($Aliases -contains $Arguments[$index]) {
            $matches += $index
        }
    }
    Assert-Equal -Actual $matches.Count -Expected 1 -Message "$Message (option occurrence)"
    $valueIndex = $matches[0] + 1
    Assert-True -Condition ($valueIndex -lt $Arguments.Count) -Message "$Message (missing option value)"
    Assert-Equal -Actual $Arguments[$valueIndex] -Expected $ExpectedValue -Message $Message
}

function Get-ExceptionBlockerCode {
    param([Parameter(Mandatory = $true)][System.Exception]$Exception)

    $cursor = $Exception
    while ($null -ne $cursor) {
        foreach ($key in @($cursor.Data.Keys)) {
            if ([string]$key -ieq 'BlockerCode' -or [string]$key -ieq 'blockerCode') {
                return [string]$cursor.Data[$key]
            }
        }
        if ($cursor.Message -match '\b([A-Z][A-Z0-9_]{4,})\b') {
            return $Matches[1]
        }
        $cursor = $cursor.InnerException
    }
    return $null
}

function Assert-ThrowsBlocker {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Body,
        [Parameter(Mandatory = $true)][string[]]$ExpectedCode,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $caught = $null
    try {
        & $Body
    }
    catch {
        $caught = $_.Exception
    }
    Assert-True -Condition ($null -ne $caught) -Message "$Message (expected an exception)"
    $actualCode = Get-ExceptionBlockerCode -Exception $caught
    Assert-True -Condition ($ExpectedCode -contains $actualCode) -Message "$Message Expected blocker '$($ExpectedCode -join ',')', got '$actualCode': $($caught.Message)"
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
        $stopwatch.Stop()
        $script:testResults += [pscustomobject][ordered]@{
            name = $Name
            result = 'PASS'
            durationMs = [int64]$stopwatch.ElapsedMilliseconds
            error = $null
            blockerCode = $null
        }
        Write-Host "PASS  $Name" -ForegroundColor Green
    }
    catch {
        $stopwatch.Stop()
        $script:testResults += [pscustomobject][ordered]@{
            name = $Name
            result = 'FAIL'
            durationMs = [int64]$stopwatch.ElapsedMilliseconds
            error = $_.Exception.Message
            blockerCode = Get-ExceptionBlockerCode -Exception $_.Exception
        }
        Write-Host "FAIL  $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-SyntheticTarget {
    param(
        [Parameter(Mandatory = $true)][string]$PbixName,
        [Parameter(Mandatory = $true)][int]$ProcessId
    )

    # Extra aliases make the fixture self-describing when target evidence grows;
    # Select-PbixTarget uses PbixName and ProcessId.
    return [pscustomobject][ordered]@{
        PbixName = $PbixName
        Name = $PbixName
        ProcessId = $ProcessId
        DesktopProcessId = $ProcessId
        MainWindowTitle = "$PbixName - Power BI Desktop"
        WindowHandle = [int64]$ProcessId
    }
}

$requiredCommands = @(
    'Get-Te2ExportArguments',
    'Get-DscmdCsvArguments',
    'Get-DscmdVpaxArguments',
    'Get-PbixIntakeFailureInfo',
    'Select-PbixTarget',
    'Resolve-PbixModelContext',
    'Invoke-BoundedProcess',
    'Protect-PbixIntakeText',
    'New-GenieHandoff',
    'Assert-ToolRegistration',
    'New-ToolDistributionRecord',
    'Assert-ToolDistribution',
    'Get-RegisteredTools',
    'Assert-PbixIntakeArtifact'
)

try {
    if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
        throw "Core module is missing: $ModulePath"
    }
    Import-Module -Name $ModulePath -Force -DisableNameChecking -ErrorAction Stop
    foreach ($commandName in $requiredCommands) {
        if ($null -eq (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            throw "Core module does not export required command '$commandName'."
        }
    }

    # Windows PowerShell 5.1 treats UTF-8 source without BOM as an ANSI code
    # page. Construct non-ASCII fixtures from code points so this remains a
    # genuine Unicode test on every Windows host.
    $unicodeName = 'Caf' + [char]0x00E9 + ' ' + [char]0x6771 + [char]0x4EAC
    $server = 'localhost:54321'
    $catalog = 'Model Catalog & ' + $unicodeName
    $bimPath = Join-Path $sandboxRoot ('semantic model & ' + $unicodeName + '.bim')
    $tmdlPath = Join-Path $sandboxRoot ('semantic model & ' + $unicodeName + ' tmdl')
    $csvPath = Join-Path $sandboxRoot ('connection proof & ' + $unicodeName + '.csv')
    $queryPath = Join-Path $sandboxRoot ('connection query & ' + $unicodeName + '.dax')
    $vpaxPath = Join-Path $sandboxRoot ('metadata only & ' + $unicodeName + '.vpax')
    Write-TestUtf8NoBom -Path $queryPath -Text 'EVALUATE ROW("PbixIntakeConnection", "OK")'

    Invoke-TestCase -Name 'Run-once installer parses on Windows PowerShell 5.1' -Body {
        Assert-True -Condition (Test-Path -LiteralPath $provisioningScriptPath -PathType Leaf) -Message 'Run-once installer is missing'
        $parseTokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($provisioningScriptPath, [ref]$parseTokens, [ref]$parseErrors)
        Assert-Equal -Actual @($parseErrors).Count -Expected 0 -Message 'Run-once installer contains PowerShell parser errors'
    }

    Invoke-TestCase -Name 'WinGet plan pins exact audited user-scope packages without elevation fallback' -Body {
        . $provisioningScriptPath
        $packages = @(Get-PinnedToolPackages)
        Assert-Equal -Actual $packages.Count -Expected 2 -Message 'Provisioning package count changed'

        $te2 = @($packages | Where-Object { $_.kind -eq 'TE2' })[0]
        $dax = @($packages | Where-Object { $_.kind -eq 'DAX' })[0]
        Assert-Equal -Actual $te2.id -Expected 'TabularEditor.TabularEditor.2' -Message 'TE2 WinGet ID drifted'
        Assert-Equal -Actual $te2.version -Expected '2.28.0' -Message 'TE2 pin drifted'
        Assert-Equal -Actual $te2.architecture -Expected 'x86' -Message 'TE2 architecture drifted'
        Assert-Equal -Actual $dax.id -Expected 'DaxStudio.DaxStudio' -Message 'DAX WinGet ID drifted'
        Assert-Equal -Actual $dax.version -Expected '3.6.0' -Message 'DAX pin drifted'
        Assert-Equal -Actual $dax.architecture -Expected 'x64' -Message 'DAX architecture drifted'

        foreach ($package in $packages) {
            Assert-Equal -Actual $package.scope -Expected 'user' -Message "$($package.kind) scope must remain user"
            [string[]]$arguments = @(Get-WinGetInstallArguments -Package $package)
            Assert-OptionValue -Arguments $arguments -Aliases @('--id') -ExpectedValue ([string]$package.id) -Message 'Wrong exact package ID'
            Assert-OptionValue -Arguments $arguments -Aliases @('--version') -ExpectedValue ([string]$package.version) -Message 'Wrong pinned version'
            Assert-OptionValue -Arguments $arguments -Aliases @('--source') -ExpectedValue 'winget' -Message 'Wrong package source'
            Assert-OptionValue -Arguments $arguments -Aliases @('--scope') -ExpectedValue 'user' -Message 'Machine-scope fallback appeared'
            Assert-True -Condition ($arguments -contains '--exact') -Message 'Exact matching is required'
            Assert-True -Condition ($arguments -contains '--silent') -Message 'Silent installer mode is required'
            Assert-True -Condition ($arguments -contains '--disable-interactivity') -Message 'WinGet prompts must be disabled'
            Assert-True -Condition ($arguments -contains '--accept-source-agreements') -Message 'WinGet source agreements must be accepted noninteractively'
            Assert-True -Condition ($arguments -contains '--accept-package-agreements') -Message 'WinGet package agreements must be accepted noninteractively'
            Assert-NoToken -Arguments $arguments -Forbidden @('--force', '--ignore-security-hash', '--override', '--interactive', 'machine') -Message 'Unsafe WinGet fallback or override appeared'
        }
        Assert-True -Condition ((Get-WinGetInstallArguments -Package $te2) -contains '--skip-dependencies') -Message 'TE2 must skip the incorrect developer-pack dependency after the .NET 4.8 preflight'
        Assert-True -Condition ((Get-WinGetInstallArguments -Package $dax) -notcontains '--skip-dependencies') -Message 'DAX dependencies must not be skipped'

        $scriptText = [System.IO.File]::ReadAllText($provisioningScriptPath)
        Assert-True -Condition ($scriptText -notmatch '(?i)-Verb\s+RunAs') -Message 'Installer must never request elevation'
    }

    Invoke-TestCase -Name 'WinGet registry resolver preserves singleton arrays on PowerShell 5.1' -Body {
        . $provisioningScriptPath
        $package = @(Get-PinnedToolPackages | Where-Object { $_.kind -eq 'TE2' })[0]
        $fakeInstallRoot = Join-Path $sandboxRoot 'one winget tool'
        $null = New-Item -ItemType Directory -Path $fakeInstallRoot -Force
        $fakeExecutable = Join-Path $fakeInstallRoot 'TabularEditor.exe'
        Write-TestUtf8NoBom -Path $fakeExecutable -Text 'fixture'
        $entry = [pscustomobject]@{
            PSChildName = 'TabularEditor.TabularEditor.2_Microsoft.Winget.Source_fixture'
            InstallLocation = $fakeInstallRoot
        }
        $resolved = Resolve-PinnedInstalledExecutable -Package $package -UninstallEntries @($entry)
        Assert-Equal -Actual $resolved -Expected $fakeExecutable -Message 'Singleton WinGet registry resolution failed'
    }

    Invoke-TestCase -Name 'Provisioning preflight failure writes a unique failed result before WinGet' -Body {
        . $provisioningScriptPath
        function Assert-NonElevatedInteractiveUser {
            throw 'PROVISION_ELEVATED_SESSION: simulated preflight refusal'
        }
        # Keep this fixture compact so the suite also runs from deeply nested extracted release folders on Windows PowerShell 5.1.
        $preflightConfig = Join-Path $sandboxRoot 'pf\tools.json'
        $caught = $null
        try {
            Invoke-PbixIntakeToolProvisioning -ConfigPath $preflightConfig -InstallTimeoutSeconds 60
        }
        catch {
            $caught = $_.Exception
        }
        Assert-True -Condition ($null -ne $caught) -Message 'Simulated preflight failure was not returned'
        [object[]]$resultFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $preflightConfig) -Recurse -Filter result.json -File)
        Assert-Equal -Actual $resultFiles.Count -Expected 1 -Message 'Preflight failure should retain exactly one result record'
        $preflightResult = Get-Content -LiteralPath $resultFiles[0].FullName -Raw | ConvertFrom-Json
        Assert-Equal -Actual $preflightResult.status -Expected 'failed' -Message 'Preflight result status is not failed'
        Assert-True -Condition ([string]$preflightResult.error -like 'PROVISION_ELEVATED_SESSION:*') -Message 'Preflight error was not preserved'
        Assert-True -Condition ($null -eq $preflightResult.winget) -Message 'WinGet should not run after a rejected preflight'
    }

    Invoke-TestCase -Name 'WinGet source refresh requires positive Done evidence' -Body {
        . $provisioningScriptPath
        $result = [pscustomobject]@{ ExitCode = 0; Stdout = "Updating source: winget...`r`nDone"; Stderr = '' }
        Assert-True -Condition ([bool](Assert-WinGetSourceRefreshResult -Result $result)) -Message 'A clean source refresh should pass'
    }

    Invoke-TestCase -Name 'WinGet source refresh rejects failure text even with exit zero' -Body {
        . $provisioningScriptPath
        $result = [pscustomobject]@{ ExitCode = 0; Stdout = "Updating source: winget...`r`nFailed: 0x8A15000F"; Stderr = '' }
        Assert-ThrowsBlocker -ExpectedCode @('WINGET_SOURCE_REFRESH_FAILED') -Message 'A stale or failed source update must fail closed' -Body {
            Assert-WinGetSourceRefreshResult -Result $result
        }
    }

    Invoke-TestCase -Name 'Runtime dependency manifest detects companion-file drift' -Body {
        $toolRoot = Join-Path $sandboxRoot 'dependency manifest tool'
        $null = New-Item -ItemType Directory -Path $toolRoot -Force
        $fakeExecutable = Join-Path $toolRoot 'fixture.exe'
        $companion = Join-Path $toolRoot 'companion.dll'
        $ignoredLog = Join-Path $toolRoot 'runtime.log'
        Write-TestUtf8NoBom -Path $fakeExecutable -Text 'executable fixture'
        Write-TestUtf8NoBom -Path $companion -Text 'dependency fixture'
        Write-TestUtf8NoBom -Path $ignoredLog -Text 'operational residue'
        $record = New-ToolDistributionRecord -ExecutablePath $fakeExecutable
        Assert-Equal -Actual @($record.files).Count -Expected 2 -Message 'Dependency record should omit operational logs only'
        [void](Assert-ToolDistribution -ExecutablePath $fakeExecutable -ExpectedRecord $record)
        $duplicateExpectedRecord = [pscustomobject]@{
            root = $record.root
            files = @($record.files[0], $record.files[0])
        }
        Assert-ThrowsBlocker -ExpectedCode @('TOOLS_NOT_PROVISIONED') -Message 'Duplicate expected paths must not hide an unchecked actual dependency' -Body {
            Assert-ToolDistribution -ExecutablePath $fakeExecutable -ExpectedRecord $duplicateExpectedRecord
        }
        Write-TestUtf8NoBom -Path $companion -Text 'changed dependency fixture'
        Assert-ThrowsBlocker -ExpectedCode @('TOOL_DISTRIBUTION_CHANGED') -Message 'Changed companion DLL must fail validation' -Body {
            Assert-ToolDistribution -ExecutablePath $fakeExecutable -ExpectedRecord $record
        }
    }

    Invoke-TestCase -Name 'Legacy tool registration schema fails closed before execution' -Body {
        $legacyConfigPath = Join-Path $sandboxRoot 'legacy tools.json'
        Write-TestUtf8NoBom -Path $legacyConfigPath -Text '{"schemaVersion":1,"tools":{}}'
        Assert-ThrowsBlocker -ExpectedCode @('TOOLS_NOT_PROVISIONED') -Message 'Legacy executable-only registration must be reinitialized' -Body {
            Get-RegisteredTools -ConfigPath $legacyConfigPath
        }
    }

    Invoke-TestCase -Name 'TE2 BIM grammar is explicit, read-only, and argument-safe' -Body {
        [string[]]$arguments = @(Get-Te2ExportArguments -Server $server -Catalog $catalog -OutputPath $bimPath -Format BIM)
        Assert-SequenceEqual -Actual $arguments -Expected @($server, $catalog, '-B', $bimPath) -Message 'Unexpected TE2 BIM grammar'
        Assert-NoToken -Arguments $arguments -Forbidden @('-D', '-DEPLOY', '-S', '-SCRIPT', '-L', '-LOCAL', '-E', '-W') -Message 'BIM export used a write/script/local/deployment token'
    }

    Invoke-TestCase -Name 'TE2 TMDL grammar is separate from BIM and never uses -S for selection' -Body {
        [string[]]$arguments = @(Get-Te2ExportArguments -Server $server -Catalog $catalog -OutputPath $tmdlPath -Format TMDL)
        Assert-SequenceEqual -Actual $arguments -Expected @($server, $catalog, '-TMDL', $tmdlPath) -Message 'Unexpected TE2 TMDL grammar'
        Assert-NoToken -Arguments $arguments -Forbidden @('-B', '-D', '-DEPLOY', '-S', '-SCRIPT', '-L', '-LOCAL', '-E', '-W') -Message 'TMDL export combined formats or used a forbidden token'
    }

    Invoke-TestCase -Name 'TE2 rejects switch-like server input instead of confusing -L and -S' -Body {
        Assert-ThrowsBlocker -ExpectedCode @('TE2_ARGUMENT_CONTRACT_FAILED', 'READ_ONLY_GUARD_VIOLATION') -Message 'Switch-like TE2 server should fail' -Body {
            Get-Te2ExportArguments -Server '-S' -Catalog $catalog -OutputPath $bimPath -Format BIM
        }
        Assert-ThrowsBlocker -ExpectedCode @('TE2_ARGUMENT_CONTRACT_FAILED', 'READ_ONLY_GUARD_VIOLATION') -Message 'Deployment-like TE2 catalog should fail' -Body {
            Get-Te2ExportArguments -Server $server -Catalog '-D' -OutputPath $bimPath -Format BIM
        }
        Assert-ThrowsBlocker -ExpectedCode @('TE2_ARGUMENT_CONTRACT_FAILED') -Message 'Relative TE2 output should fail' -Body {
            Get-Te2ExportArguments -Server $server -Catalog $catalog -OutputPath 'relative-model.bim' -Format BIM
        }
    }

    Invoke-TestCase -Name 'dscmd CSV uses server/database/file and never treats a file as inline DAX' -Body {
        [string[]]$arguments = @(Get-DscmdCsvArguments -Server $server -Catalog $catalog -OutputPath $csvPath -QueryFile $queryPath)
        Assert-Equal -Actual $arguments[0] -Expected 'csv' -Message 'dscmd command names are case-sensitive; lowercase csv must be first'
        Assert-Equal -Actual $arguments[1] -Expected $csvPath -Message 'CSV output must remain one argument'
        Assert-OptionValue -Arguments $arguments -Aliases @('-s', '--server') -ExpectedValue $server -Message 'Wrong dscmd server option/value'
        Assert-OptionValue -Arguments $arguments -Aliases @('-d', '--database') -ExpectedValue $catalog -Message 'Wrong dscmd database option/value'
        Assert-OptionValue -Arguments $arguments -Aliases @('-f', '--file') -ExpectedValue $queryPath -Message 'Wrong dscmd query-file option/value'
        Assert-NoToken -Arguments $arguments -Forbidden @('-q', '--query', '-L', '--connectionstring') -Message 'CSV args confused inline query/local/connection modes'
    }

    Invoke-TestCase -Name 'dscmd rejects switch injection and relative file contracts' -Body {
        Assert-ThrowsBlocker -ExpectedCode @('DAX_ARGUMENT_CONTRACT_FAILED', 'READ_ONLY_GUARD_VIOLATION') -Message 'Direct Lake -l must not be accepted as a server' -Body {
            Get-DscmdCsvArguments -Server '-l' -Catalog $catalog -OutputPath $csvPath -QueryFile $queryPath
        }
        Assert-ThrowsBlocker -ExpectedCode @('DAX_ARGUMENT_CONTRACT_FAILED', 'READ_ONLY_GUARD_VIOLATION') -Message 'Inline-query -q must not be accepted as a catalog' -Body {
            Get-DscmdCsvArguments -Server $server -Catalog '-q' -OutputPath $csvPath -QueryFile $queryPath
        }
        Assert-ThrowsBlocker -ExpectedCode @('DAX_ARGUMENT_CONTRACT_FAILED') -Message 'Relative DAX query-file path should fail' -Body {
            Get-DscmdCsvArguments -Server $server -Catalog $catalog -OutputPath $csvPath -QueryFile 'connection-test.dax'
        }
        Assert-ThrowsBlocker -ExpectedCode @('DAX_ARGUMENT_CONTRACT_FAILED') -Message 'Relative VPAX output path should fail' -Body {
            Get-DscmdVpaxArguments -Server $server -Catalog $catalog -OutputPath 'metadata.vpax'
        }
    }

    Invoke-TestCase -Name 'dscmd VPAX is metadata-only and never mistakes -l for local' -Body {
        [string[]]$arguments = @(Get-DscmdVpaxArguments -Server $server -Catalog $catalog -OutputPath $vpaxPath)
        Assert-Equal -Actual $arguments[0] -Expected 'vpax' -Message 'dscmd command names are case-sensitive; lowercase vpax must be first'
        Assert-Equal -Actual $arguments[1] -Expected $vpaxPath -Message 'VPAX output must remain one argument'
        Assert-OptionValue -Arguments $arguments -Aliases @('-s', '--server') -ExpectedValue $server -Message 'Wrong VPAX server option/value'
        Assert-OptionValue -Arguments $arguments -Aliases @('-d', '--database') -ExpectedValue $catalog -Message 'Wrong VPAX database option/value'
        Assert-True -Condition (($arguments -contains '-r') -or ($arguments -contains '--donotreadstatsfromdata')) -Message 'VPAX must disable data-statistic reads'
        Assert-NoToken -Arguments $arguments -Forbidden @('-l', '--DirectLakeMode', '--directlakemode', '-t', '--excludeTom', '--excludetom', '-q', '--query', '-f', '--file', '-L') -Message 'VPAX args used a hallucinated/local/data/TOM-exclusion token'
    }

    Invoke-TestCase -Name 'Target selection fails closed when no PBIX is open' -Body {
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_NOT_OPEN') -Message 'Zero-target selection should fail closed' -Body {
            Select-PbixTarget -Targets @()
        }
    }

    Invoke-TestCase -Name 'Categorized failures preserve blocker, stage, message, and next action' -Body {
        $caught = $null
        try { Select-PbixTarget -Targets @() } catch { $caught = $_.Exception }
        Assert-True -Condition ($null -ne $caught) -Message 'Expected categorized discovery failure'
        $failure = Get-PbixIntakeFailureInfo -Exception $caught
        Assert-Equal -Actual $failure.blockerCode -Expected 'PBIX_NOT_OPEN' -Message 'Failure trail lost exact blocker code'
        Assert-Equal -Actual $failure.failureStage -Expected 'discovery' -Message 'Failure trail lost stage'
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$failure.message)) -Message 'Failure trail lost message'
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$failure.nextAction)) -Message 'Failure trail lost safe next action'
    }

    Invoke-TestCase -Name 'Target selection requires an exact name when distinct PBIX files are open' -Body {
        $targets = @(
            (New-SyntheticTarget -PbixName 'Alpha.pbix' -ProcessId 1101),
            (New-SyntheticTarget -PbixName 'Beta.pbix' -ProcessId 1102),
            (New-SyntheticTarget -PbixName 'Gamma.pbix' -ProcessId 1103)
        )
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_TARGET_AMBIGUOUS') -Message 'Multiple targets without a name should fail' -Body {
            Select-PbixTarget -Targets $targets
        }
        $selected = Select-PbixTarget -PbixName 'Beta.pbix' -Targets $targets
        Assert-Equal -Actual $selected.ProcessId -Expected 1102 -Message 'Exact target selected the wrong process'
        foreach ($inexactName in @('Bet.pbix', 'Btea.pbix', 'Beta', '*Beta*.pbix')) {
            $candidate = $inexactName
            Assert-ThrowsBlocker -ExpectedCode @('PBIX_TARGET_NOT_FOUND', 'PBIX_TARGET_INVALID') -Message "Fuzzy/spelling-corrected target '$candidate' must not match" -Body {
                Select-PbixTarget -PbixName $candidate -Targets $targets
            }
        }
    }

    Invoke-TestCase -Name 'Duplicate open basenames are rejected even with an exact requested name' -Body {
        $targets = @(
            (New-SyntheticTarget -PbixName 'Duplicate.pbix' -ProcessId 1201),
            (New-SyntheticTarget -PbixName 'Duplicate.pbix' -ProcessId 1202)
        )
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_TARGET_DUPLICATE') -Message 'Duplicate basename should be unresolvable' -Body {
            Select-PbixTarget -PbixName 'Duplicate.pbix' -Targets $targets
        }
    }

    Invoke-TestCase -Name 'PBIX target input rejects paths, switch-like names, and wrong extensions' -Body {
        $targets = @((New-SyntheticTarget -PbixName 'Finance.pbix' -ProcessId 1301))
        foreach ($invalidName in @('C:\Reports\Finance.pbix', '..\Finance.pbix', '-L', '--server', 'Finance.pbip', '')) {
            $candidate = $invalidName
            Assert-ThrowsBlocker -ExpectedCode @('PBIX_TARGET_INVALID') -Message "Invalid PBIX target '$candidate' should fail" -Body {
                Select-PbixTarget -PbixName $candidate -Targets $targets
            }
        }
    }

    Invoke-TestCase -Name 'TempSaves lock basenames are never durable selectable PBIX identities' -Body {
        $temporaryTarget = [pscustomobject][ordered]@{
            PbixName = '~$Revenue Opportunities.pbix'
            ProcessId = 1351
            CurrentFilePath = 'C:\Temp\Power BI Desktop\TempSaves\~$Revenue Opportunities.pbix'
            Path = 'C:\Temp\Power BI Desktop\TempSaves\~$Revenue Opportunities.pbix'
            WindowTitle = 'Untitled - Power BI Desktop'
            IsUnsaved = $true
            IdentityConflict = $false
        }
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_TARGET_UNSAVED', 'PBIX_NOT_OPEN') -Message 'Unqualified temp-lock target must not be treated as durable' -Body {
            Select-PbixTarget -Targets @($temporaryTarget)
        }
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_TARGET_INVALID', 'PBIX_TARGET_NOT_FOUND', 'PBIX_TARGET_UNSAVED') -Message 'Exact temp-lock basename must never be selectable' -Body {
            Select-PbixTarget -PbixName '~$Revenue Opportunities.pbix' -Targets @($temporaryTarget)
        }
    }

    Invoke-TestCase -Name 'Exact selection preserves spaces, ampersands, and Unicode' -Body {
        $specialName = 'Finance & ' + $unicodeName + '.pbix'
        $targets = @(
            (New-SyntheticTarget -PbixName $specialName -ProcessId 1401),
            (New-SyntheticTarget -PbixName 'Finance.pbix' -ProcessId 1402)
        )
        $selected = Select-PbixTarget -PbixName $specialName -Targets $targets
        Assert-Equal -Actual $selected.PbixName -Expected $specialName -Message 'Special filename was altered or fuzzily matched'
        Assert-Equal -Actual $selected.ProcessId -Expected 1401 -Message 'Special filename selected the wrong process'
    }

    Invoke-TestCase -Name 'Command-line and window-title fallback identities remain exact' -Body {
        $commandLineTarget = New-SyntheticTarget -PbixName 'Command Line.pbix' -ProcessId 1501
        $commandLineTarget | Add-Member -NotePropertyName DiscoverySource -NotePropertyValue 'command-line'
        $windowTarget = New-SyntheticTarget -PbixName 'Window Title.pbix' -ProcessId 1502
        $windowTarget | Add-Member -NotePropertyName DiscoverySource -NotePropertyValue 'window-title'
        $targets = @($commandLineTarget, $windowTarget)
        Assert-Equal -Actual (Select-PbixTarget -PbixName 'Command Line.pbix' -Targets $targets).ProcessId -Expected 1501 -Message 'Command-line fallback identity did not select exactly'
        Assert-Equal -Actual (Select-PbixTarget -PbixName 'Window Title.pbix' -Targets $targets).ProcessId -Expected 1502 -Message 'Window-title fallback identity did not select exactly'
    }

    Invoke-TestCase -Name 'Conflicting Bridge, command-line, and window evidence is PBIX_IDENTITY_MISMATCH' -Body {
        $conflicted = [pscustomobject][ordered]@{
            PbixName = 'Bridge Name.pbix'
            ProcessId = 1601
            IdentityConflict = $true
            BridgeName = 'Bridge Name.pbix'
            CommandLineName = 'Different Name.pbix'
            WindowName = 'Bridge Name.pbix'
        }
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_IDENTITY_MISMATCH') -Message 'Conflicting discovery evidence must fail closed' -Body {
            Select-PbixTarget -PbixName 'Bridge Name.pbix' -Targets @($conflicted)
        }
    }

    Invoke-TestCase -Name 'Model context mapping uses Desktop PID only and rejects ambiguous contexts' -Body {
        $target = New-SyntheticTarget -PbixName 'Identity.pbix' -ProcessId 1701
        $validContext = [pscustomobject][ordered]@{
            DesktopProcessId = 1701
            ParentProcessId = 1701
            Server = 'localhost:51701'
            Catalog = 'IdentityCatalog'
            Port = 51701
            PortSource = 'live-listener'
            IssueCode = $null
            IssueMessage = $null
        }
        $resolved = Resolve-PbixModelContext -Target $target -Contexts @($validContext)
        Assert-Equal -Actual $resolved.Server -Expected 'localhost:51701' -Message 'Verified PID context did not resolve'

        $wrongPidSameName = [pscustomobject][ordered]@{
            DesktopProcessId = 1799
            ParentProcessId = 1799
            Server = 'localhost:51799'
            Catalog = 'Identity.pbix'
            Port = 51799
            PortSource = 'port-file'
            IssueCode = $null
            IssueMessage = $null
        }
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_MODEL_NOT_READY', 'PBIX_IDENTITY_MISMATCH') -Message 'Catalog/name similarity must not bypass PID identity' -Body {
            Resolve-PbixModelContext -Target $target -Contexts @($wrongPidSameName)
        }

        $secondContext = [pscustomobject][ordered]@{
            DesktopProcessId = 1701
            ParentProcessId = 1701
            Server = 'localhost:51702'
            Catalog = 'SecondCatalog'
            Port = 51702
            PortSource = 'port-file'
            IssueCode = $null
            IssueMessage = $null
        }
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_CONTEXT_AMBIGUOUS') -Message 'Two plausible listeners/catalogs for one Desktop PID must fail' -Body {
            Resolve-PbixModelContext -Target $target -Contexts @($validContext, $secondContext)
        }
    }

    Invoke-TestCase -Name 'Live listener overrides a stale port file; multiple live listeners remain ambiguous' -Body {
        $target = New-SyntheticTarget -PbixName 'Port Evidence.pbix' -ProcessId 1801
        $liveOverrideContext = [pscustomobject][ordered]@{
            DesktopProcessId = 1801
            ParentProcessId = 1801
            Server = 'localhost:51801'
            Catalog = 'PortEvidenceCatalog'
            Port = 51801
            PortFilePort = 51999
            ListenerPorts = @(51801)
            PortSource = 'tcp-listener-overrode-port-file'
            IssueCode = $null
            IssueMessage = $null
        }
        $resolved = Resolve-PbixModelContext -Target $target -Contexts @($liveOverrideContext)
        Assert-Equal -Actual $resolved.Server -Expected 'localhost:51801' -Message 'Exact PID-owned live listener did not override stale port file'
        Assert-Equal -Actual $resolved.PortSource -Expected 'tcp-listener-overrode-port-file' -Message 'Port override evidence was not retained'

        $ambiguousContext = [pscustomobject][ordered]@{
            DesktopProcessId = 1801
            ParentProcessId = 1801
            Server = $null
            Catalog = 'PortEvidenceCatalog'
            Port = $null
            PortFilePort = 51999
            ListenerPorts = @(51801, 51802)
            PortSource = $null
            IssueCode = 'PBIX_CONTEXT_AMBIGUOUS'
            IssueMessage = 'The Analysis Services child owns more than one distinct TCP listener.'
        }
        Assert-ThrowsBlocker -ExpectedCode @('PBIX_CONTEXT_AMBIGUOUS') -Message 'Multiple live listeners must not be guessed' -Body {
            Resolve-PbixModelContext -Target $target -Contexts @($ambiguousContext)
        }
    }

    Invoke-TestCase -Name 'Bounded process preserves special argument boundaries' -Body {
        $probeScript = Join-Path $sandboxRoot 'argument probe.ps1'
        $probeStdout = Join-Path $sandboxRoot 'argument probe stdout.json'
        $probeStderr = Join-Path $sandboxRoot 'argument probe stderr.txt'
        $probeSource = @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Values
)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Values | ConvertTo-Json -Compress
'@
        Write-TestUtf8NoBom -Path $probeScript -Text $probeSource
        $specialArguments = @('one value', 'Sales & Returns', $unicodeName)
        $shellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
        $processResult = Invoke-BoundedProcess `
            -FilePath $shellPath `
            -ArgumentList (@('-NoProfile', '-NonInteractive', '-File', $probeScript) + $specialArguments) `
            -TimeoutSeconds 15 `
            -StdoutPath $probeStdout `
            -StderrPath $probeStderr
        Assert-Equal -Actual $processResult.ExitCode -Expected 0 -Message 'Argument probe process failed'
        [object[]]$roundTrip = @((Get-Content -LiteralPath $probeStdout -Raw | ConvertFrom-Json))
        Assert-SequenceEqual -Actual $roundTrip -Expected $specialArguments -Message 'Process helper split or changed a special argument'
    }

    Invoke-TestCase -Name 'Bounded process times out and categorizes the failure' -Body {
        $timeoutStdout = Join-Path $sandboxRoot 'timeout stdout.txt'
        $timeoutStderr = Join-Path $sandboxRoot 'timeout stderr.txt'
        $shellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
        Assert-ThrowsBlocker -ExpectedCode @('TE2_TIMEOUT') -Message 'Long-running fake tool should time out' -Body {
            Invoke-BoundedProcess `
                -FilePath $shellPath `
                -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') `
                -TimeoutSeconds 1 `
                -StdoutPath $timeoutStdout `
                -StderrPath $timeoutStderr `
                -TimeoutBlockerCode 'TE2_TIMEOUT'
        }
    }

    Invoke-TestCase -Name 'Exit zero without an artifact is MODEL_EXPORT_MISSING' -Body {
        $missingPath = Join-Path $sandboxRoot 'fake success produced nothing.bim'
        $successStdout = Join-Path $sandboxRoot 'fake success stdout.txt'
        $successStderr = Join-Path $sandboxRoot 'fake success stderr.txt'
        $shellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
        $processResult = Invoke-BoundedProcess `
            -FilePath $shellPath `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'exit 0') `
            -TimeoutSeconds 15 `
            -StdoutPath $successStdout `
            -StderrPath $successStderr
        Assert-Equal -Actual $processResult.ExitCode -Expected 0 -Message 'Fake success tool did not exit zero'
        Assert-ThrowsBlocker -ExpectedCode @('MODEL_EXPORT_MISSING') -Message 'Exit zero must not substitute for output verification' -Body {
            Assert-PbixIntakeArtifact -Path $missingPath -Kind Bim
        }
    }

    Invoke-TestCase -Name 'Redaction removes connection and token secret values' -Body {
        $secretValues = @(
            'Winter2026!',
            'shortPwd',
            'base64AccountKeyValue',
            'sv=2026-01-01&sig=VerySecretSignature',
            'clientSecretValue',
            'apiKeyValue',
            'opaqueTokenValue',
            'bearerTokenValue',
            ('da' + 'pi' + '0123456789abcdef0123456789abcdef'),
            ('sk-' + 'proj-' + '0123456789abcdefghijklmnopqrstuvwxyz'),
            ('gh' + 'p_' + '0123456789abcdefghijklmnopqrstuvwxyz')
        )
        $text = @"
Server=warehouse;Password=$($secretValues[0]);Pwd=$($secretValues[1]);AccountKey=$($secretValues[2]);SharedAccessSignature=$($secretValues[3]);
client_secret=$($secretValues[4]);api_key=$($secretValues[5]);token=$($secretValues[6]);Authorization=Bearer $($secretValues[7]);
$($secretValues[8]) $($secretValues[9]) $($secretValues[10])
"@
        $protected = Protect-PbixIntakeText -Text $text
        foreach ($secret in $secretValues) {
            Assert-True -Condition (-not $protected.Contains($secret)) -Message "Secret survived redaction: $secret"
        }
        Assert-True -Condition ($protected -match 'REDACTED') -Message 'Redaction did not leave an auditable marker'
    }

    Invoke-TestCase -Name 'Genie handoff is deterministic for identical normalized input' -Body {
        $normalizedModel = [pscustomobject][ordered]@{
            modelName = 'Deterministic Model'
            counts = [pscustomobject][ordered]@{
                tables = 1
                columns = 2
                measures = 1
                relationships = 0
                expressions = 0
                roles = 0
            }
            tables = @(
                [pscustomobject][ordered]@{
                    name = 'Calendar'
                    columns = @('Date', 'Month')
                    measures = @('Revenue')
                }
            )
            relationships = @()
            expressions = @()
            roles = @()
        }
        $firstPath = Join-Path $sandboxRoot 'handoff first.md'
        $secondPath = Join-Path $sandboxRoot 'handoff second.md'
        $first = New-GenieHandoff -NormalizedModel $normalizedModel -PbixName 'Deterministic.pbix' -OutputPath $firstPath
        $second = New-GenieHandoff -NormalizedModel $normalizedModel -PbixName 'Deterministic.pbix' -OutputPath $secondPath
        if ($null -ne $first -or $null -ne $second) {
            Assert-Equal -Actual ([string]$first) -Expected ([string]$second) -Message 'Returned handoff text changed across identical calls'
        }
        Assert-Equal -Actual (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash -Expected (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash -Message 'Handoff bytes changed across identical calls'
    }

    Invoke-TestCase -Name 'Genie handoff explicitly disclaims the report layer and complete-PBIX recreation' -Body {
        $normalizedModel = [pscustomobject][ordered]@{
            modelName = 'Scope Model'
            counts = [pscustomobject][ordered]@{
                tables = 0
                columns = 0
                measures = 0
                relationships = 0
                expressions = 0
                roles = 0
            }
            tables = @()
            relationships = @()
            expressions = @()
            roles = @()
        }
        $handoffPath = Join-Path $sandboxRoot 'scope handoff.md'
        $generated = New-GenieHandoff -NormalizedModel $normalizedModel -PbixName 'Scope.pbix' -OutputPath $handoffPath
        $handoff = if ($generated -is [string] -and -not [string]::IsNullOrWhiteSpace($generated)) {
            [string]$generated
        }
        else {
            Get-Content -LiteralPath $handoffPath -Raw
        }
        Assert-True -Condition ($handoff -match '(?i)report layer') -Message 'Handoff does not name the excluded report layer'
        Assert-True -Condition ($handoff -match '(?i)(not captured|not collected|out of scope)') -Message 'Handoff does not clearly say the report layer is absent'
        Assert-True -Condition ($handoff -match '(?i)(pages|visuals|slicers|bookmarks)') -Message 'Handoff does not explain missing report artifacts'
        Assert-True -Condition ($handoff -match '(?i)(cannot|does not|not enough|insufficient).{0,80}(complete|full).{0,20}PBIX|complete.{0,20}PBIX.{0,80}(cannot|does not|not)') -Message 'Handoff could overclaim complete PBIX recreation'
    }

    Invoke-TestCase -Name 'Missing registered tool fails with TOOL_MISSING' -Body {
        $missingTool = Join-Path $sandboxRoot 'missing\TabularEditor.exe'
        Assert-ThrowsBlocker -ExpectedCode @('TOOL_MISSING') -Message 'Missing TE2 registration should fail' -Body {
            Assert-ToolRegistration -Kind TE2 -Path $missingTool
        }
    }

    Invoke-TestCase -Name 'Renamed unrelated executable fails tool identity validation' -Body {
        $fakeToolDirectory = Join-Path $sandboxRoot 'fake tool'
        $null = New-Item -ItemType Directory -Path $fakeToolDirectory
        $fakeToolPath = Join-Path $fakeToolDirectory 'TabularEditor.exe'
        Copy-Item -LiteralPath (Get-Command powershell.exe -ErrorAction Stop).Source -Destination $fakeToolPath
        Assert-ThrowsBlocker -ExpectedCode @('TOOL_IDENTITY_INVALID', 'TOOL_SIGNATURE_INVALID') -Message 'Renamed PowerShell must not pass as TE2' -Body {
            Assert-ToolRegistration -Kind TE2 -Path $fakeToolPath
        }
    }
}
catch {
    $script:testResults += [pscustomobject][ordered]@{
        name = 'Harness initialization'
        result = 'FAIL'
        durationMs = [int64]0
        error = $_.Exception.Message
        blockerCode = Get-ExceptionBlockerCode -Exception $_.Exception
    }
    Write-Host "FAIL  Harness initialization - $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    $passed = @($script:testResults | Where-Object { $_.result -eq 'PASS' }).Count
    $failed = @($script:testResults | Where-Object { $_.result -eq 'FAIL' }).Count
    $report = [ordered]@{
        schemaVersion = 1
        suite = 'PBIX Intake Lab adversarial contract'
        result = if ($failed -eq 0 -and $passed -gt 0) { 'PASS' } else { 'FAIL' }
        passed = $passed
        failed = $failed
        modulePath = $ModulePath
        tests = [object[]]$script:testResults
    }
    Write-TestUtf8NoBom -Path $resultPath -Text (($report | ConvertTo-Json -Depth 10) + "`n")

    if (-not $KeepSandbox -and (Test-Path -LiteralPath $sandboxRoot -PathType Container)) {
        $resolvedSandbox = (Resolve-Path -LiteralPath $sandboxRoot).Path
        $resolvedResults = (Resolve-Path -LiteralPath $resolvedResultsRoot).Path
        if ($resolvedSandbox.StartsWith($resolvedResults + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force
        }
        else {
            Write-Warning "Refusing to remove sandbox outside results root: $resolvedSandbox"
        }
    }

    Write-Host "`nAdversarial result: $($report.result) ($passed passed, $failed failed)"
    Write-Host "JSON report: $resultPath"
}

if ($failed -ne 0) {
    exit 1
}
