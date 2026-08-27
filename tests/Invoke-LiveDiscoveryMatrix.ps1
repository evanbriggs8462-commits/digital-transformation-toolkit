[CmdletBinding()]
param(
    [string]$ModulePath,
    [string]$ResultsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $repositoryRoot 'powershell\PbixIntake.Core.psm1'
}
if ([string]::IsNullOrWhiteSpace($ResultsRoot)) {
    $ResultsRoot = Join-Path $PSScriptRoot 'results'
}
if (-not (Test-Path -LiteralPath $ResultsRoot -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $ResultsRoot -Force
}
$resultPath = Join-Path (Resolve-Path -LiteralPath $ResultsRoot).Path 'live-discovery-matrix.json'

$script:testResults = @()
$script:routeEvidence = [ordered]@{}
$script:blockedReason = $null

function Write-TestUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-PropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$Name
    )

    if ($null -eq $InputObject) { return $null }
    foreach ($candidate in $Name) {
        if ($InputObject.PSObject.Properties.Name -contains $candidate) {
            return $InputObject.$candidate
        }
    }
    return $null
}

function Get-BlockerCode {
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

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw "ASSERT_TRUE_FAILED: $Message" }
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

function Assert-ThrowsBlocker {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Body,
        [Parameter(Mandatory = $true)][string]$ExpectedCode,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $caught = $null
    try { & $Body } catch { $caught = $_.Exception }
    Assert-True -Condition ($null -ne $caught) -Message "$Message (expected an exception)"
    Assert-Equal -Actual (Get-BlockerCode -Exception $caught) -Expected $ExpectedCode -Message $Message
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    try {
        & $Body
        $script:testResults += [pscustomobject][ordered]@{
            name = $Name
            result = 'PASS'
            error = $null
            blockerCode = $null
        }
        Write-Host "PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:testResults += [pscustomobject][ordered]@{
            name = $Name
            result = 'FAIL'
            error = $_.Exception.Message
            blockerCode = Get-BlockerCode -Exception $_.Exception
        }
        Write-Host "FAIL  $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

function ConvertTo-SafeTargetEvidence {
    param([Parameter(Mandatory = $true)][object[]]$Target)

    $safe = @()
    foreach ($item in $Target) {
        $bridgeName = [string](Get-PropertyValue -InputObject $item -Name @('BridgeName'))
        $commandLineName = [string](Get-PropertyValue -InputObject $item -Name @('CommandLineName'))
        $windowName = [string](Get-PropertyValue -InputObject $item -Name @('WindowName'))
        $safe += [pscustomobject][ordered]@{
            pbixName = [string](Get-PropertyValue -InputObject $item -Name @('PbixName', 'Name'))
            desktopProcessId = Get-PropertyValue -InputObject $item -Name @('ProcessId', 'DesktopProcessId', 'Pid')
            nameSource = [string](Get-PropertyValue -InputObject $item -Name @('DiscoverySource', 'NameSource', 'Source', 'IdentitySource'))
            bridgeObserved = -not [string]::IsNullOrWhiteSpace($bridgeName)
            commandLineObserved = -not [string]::IsNullOrWhiteSpace($commandLineName)
            windowTitleObserved = -not [string]::IsNullOrWhiteSpace($windowName)
            identityConflict = [bool](Get-PropertyValue -InputObject $item -Name @('IdentityConflict'))
        }
    }
    return [object[]]$safe
}

function Get-Names {
    param([Parameter(Mandatory = $true)][object[]]$Target)

    return [string[]]@(
        $Target |
            ForEach-Object { [string](Get-PropertyValue -InputObject $_ -Name @('PbixName', 'Name')) } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Get-TargetIdentityPairs {
    param([Parameter(Mandatory = $true)][object[]]$Target)

    [string[]]$pairs = @(
        foreach ($item in $Target) {
            $name = [string](Get-PropertyValue -InputObject $item -Name @('PbixName', 'Name'))
            $processId = [string](Get-PropertyValue -InputObject $item -Name @('ProcessId', 'DesktopProcessId', 'Pid'))
            if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($processId)) {
                "$processId`t$name"
            }
        }
    )
    return [string[]]@($pairs | Sort-Object -Unique)
}

function Get-ExpectedFallbackPairs {
    param(
        [Parameter(Mandatory = $true)][object[]]$Target,
        [Parameter(Mandatory = $true)][ValidateSet('CommandLineOrWindow', 'WindowOnly')][string]$Route
    )

    [string[]]$pairs = @(
        foreach ($item in $Target) {
            $processId = [string](Get-PropertyValue -InputObject $item -Name @('ProcessId', 'DesktopProcessId', 'Pid'))
            $commandLineName = [string](Get-PropertyValue -InputObject $item -Name @('CommandLineName'))
            $windowName = [string](Get-PropertyValue -InputObject $item -Name @('WindowName'))
            $fallbackName = $null
            if ($Route -eq 'CommandLineOrWindow') {
                if (-not [string]::IsNullOrWhiteSpace($commandLineName)) { $fallbackName = $commandLineName }
                elseif (-not [string]::IsNullOrWhiteSpace($windowName)) { $fallbackName = $windowName }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($windowName)) {
                $fallbackName = $windowName
            }
            if (-not [string]::IsNullOrWhiteSpace($fallbackName) -and -not [string]::IsNullOrWhiteSpace($processId)) {
                "$processId`t$fallbackName"
            }
        }
    )
    return [string[]]@($pairs | Sort-Object -Unique)
}

function Assert-RouteModelContexts {
    param(
        [Parameter(Mandatory = $true)][object[]]$Target,
        [Parameter(Mandatory = $true)][object[]]$Context,
        [Parameter(Mandatory = $true)][string]$RouteLabel
    )

    foreach ($item in $Target) {
        $processId = [string](Get-PropertyValue -InputObject $item -Name @('ProcessId', 'DesktopProcessId', 'Pid'))
        $name = [string](Get-PropertyValue -InputObject $item -Name @('PbixName', 'Name'))
        $resolved = Resolve-PbixModelContext -Target $item -Contexts $Context
        $contextProcessId = [string](Get-PropertyValue -InputObject $resolved -Name @('DesktopProcessId', 'ProcessId'))
        Assert-Equal -Actual $contextProcessId -Expected $processId -Message "$RouteLabel model-context PID mismatch for '$name'"
    }
}

try {
    if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
        throw "Core module is missing: $ModulePath"
    }
    Import-Module -Name $ModulePath -Force -DisableNameChecking -ErrorAction Stop
    foreach ($commandName in @('Get-PowerBIDesktopTargets', 'Get-LocalDesktopModelContexts', 'Select-PbixTarget', 'Resolve-PbixModelContext')) {
        if ($null -eq (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            throw "Core module does not export required command '$commandName'."
        }
    }

    $allRoutes = @(Get-PowerBIDesktopTargets)
    $bridgeDisabled = @(Get-PowerBIDesktopTargets -DisableDesktopBridge)
    $windowOnly = @(Get-PowerBIDesktopTargets -DisableDesktopBridge -DisableCommandLine)

    $script:routeEvidence.allRoutes = ConvertTo-SafeTargetEvidence -Target $allRoutes
    $script:routeEvidence.bridgeDisabled = ConvertTo-SafeTargetEvidence -Target $bridgeDisabled
    $script:routeEvidence.windowOnly = ConvertTo-SafeTargetEvidence -Target $windowOnly

    $allNames = @(Get-Names -Target $allRoutes)
    $expectedBridgeDisabledPairs = @(Get-ExpectedFallbackPairs -Target $allRoutes -Route CommandLineOrWindow)
    $expectedWindowOnlyPairs = @(Get-ExpectedFallbackPairs -Target $allRoutes -Route WindowOnly)
    Invoke-TestCase -Name 'Discovery excludes TempSaves and lock-file PBIX identities' -Body {
        foreach ($route in @($allRoutes, $bridgeDisabled, $windowOnly)) {
            foreach ($target in @($route)) {
                $name = [string](Get-PropertyValue -InputObject $target -Name @('PbixName', 'Name'))
                Assert-True -Condition (-not $name.StartsWith('~$', [StringComparison]::Ordinal)) -Message "Lock-file PBIX identity leaked into discovery: '$name'"
                foreach ($pathProperty in @('CurrentFilePath', 'Path', 'BridgePath', 'CommandLinePath')) {
                    $candidatePath = [string](Get-PropertyValue -InputObject $target -Name @($pathProperty))
                    Assert-True -Condition ($candidatePath -notmatch '(?i)[\\/]TempSaves[\\/]') -Message "TempSaves path leaked into discovered target PID $($target.ProcessId)"
                }
            }
        }
    }

    if ($allNames.Count -lt 2 -or $expectedBridgeDisabledPairs.Count -lt 2 -or $expectedWindowOnlyPairs.Count -lt 2) {
        $script:blockedReason = 'Open at least two distinct saved PBIX files with visible titled windows and wait for both Data panes. This script never opens or closes them. Bridge-only background windows remain valid intake targets but cannot prove the window fallback.'
    }
    else {
        $contexts = @(Get-LocalDesktopModelContexts)
        Invoke-TestCase -Name 'All-routes discovery sees at least two distinct open PBIX files' -Body {
            Assert-True -Condition ($allRoutes.Count -ge 2) -Message 'Fewer than two Desktop targets were discovered'
            Assert-True -Condition ($allNames.Count -ge 2) -Message 'Fewer than two distinct durable PBIX names were discovered'
        }

        Invoke-TestCase -Name 'Bridge-disabled discovery recovers exact names from command line/window evidence' -Body {
            $routePairs = @(Get-TargetIdentityPairs -Target $bridgeDisabled)
            Assert-Equal -Actual ($routePairs -join "`n") -Expected ($expectedBridgeDisabledPairs -join "`n") -Message 'Bridge-disabled PBIX/PID pairs differ from baseline command-line/window evidence'
            Assert-RouteModelContexts -Target $bridgeDisabled -Context $contexts -RouteLabel 'Bridge-disabled'
        }

        Invoke-TestCase -Name 'Bridge-and-commandline-disabled discovery recovers exact names from window titles' -Body {
            $routePairs = @(Get-TargetIdentityPairs -Target $windowOnly)
            Assert-Equal -Actual ($routePairs -join "`n") -Expected ($expectedWindowOnlyPairs -join "`n") -Message 'Window-only PBIX/PID pairs differ from baseline window evidence'
            Assert-RouteModelContexts -Target $windowOnly -Context $contexts -RouteLabel 'Window-only'
        }

        Invoke-TestCase -Name 'No target name with multiple open PBIX files is PBIX_TARGET_AMBIGUOUS' -Body {
            Assert-ThrowsBlocker -ExpectedCode 'PBIX_TARGET_AMBIGUOUS' -Message 'Unqualified multi-target selection must fail closed' -Body {
                Select-PbixTarget -Targets $allRoutes
            }
        }

        Invoke-TestCase -Name 'Every exact PBIX name maps to one unique Desktop PID and one model context' -Body {
            $seenProcessIds = @{}
            foreach ($name in $allNames) {
                $selected = Select-PbixTarget -PbixName $name -Targets $allRoutes
                $processId = [string](Get-PropertyValue -InputObject $selected -Name @('ProcessId', 'DesktopProcessId', 'Pid'))
                Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($processId)) -Message "No Desktop PID for '$name'"
                Assert-True -Condition (-not $seenProcessIds.ContainsKey($processId)) -Message "Desktop PID '$processId' was reused by more than one exact name"
                $seenProcessIds[$processId] = $name

                $context = Resolve-PbixModelContext -Target $selected -Contexts $contexts
                $contextProcessId = [string](Get-PropertyValue -InputObject $context -Name @('DesktopProcessId', 'ProcessId'))
                Assert-Equal -Actual $contextProcessId -Expected $processId -Message "Model context PID mismatch for '$name'"
                Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -InputObject $context -Name @('Server')))) -Message "No server for '$name'"
                Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -InputObject $context -Name @('Catalog')))) -Message "No catalog for '$name'"
            }
        }

        Invoke-TestCase -Name 'Misspelled PBIX name is never fuzzily corrected' -Body {
            $missingName = 'Definitely Not An Open PBIX.pbix'
            if ($allNames -contains $missingName) {
                $missingName = 'Definitely Not An Open PBIX 2.pbix'
            }
            Assert-ThrowsBlocker -ExpectedCode 'PBIX_TARGET_NOT_FOUND' -Message 'Misspelled name must not match an open PBIX' -Body {
                Select-PbixTarget -PbixName $missingName -Targets $allRoutes
            }
        }
    }
}
catch {
    $script:testResults += [pscustomobject][ordered]@{
        name = 'Live discovery matrix initialization'
        result = 'FAIL'
        error = $_.Exception.Message
        blockerCode = Get-BlockerCode -Exception $_.Exception
    }
}
finally {
    $failed = @($script:testResults | Where-Object { $_.result -eq 'FAIL' }).Count
    $passed = @($script:testResults | Where-Object { $_.result -eq 'PASS' }).Count
    $overall = if (-not [string]::IsNullOrWhiteSpace($script:blockedReason)) {
        'BLOCKED'
    }
    elseif ($failed -gt 0 -or $passed -eq 0) {
        'FAIL'
    }
    else {
        'PASS'
    }
    $report = [ordered]@{
        schemaVersion = 1
        suite = 'PBIX Intake Lab live discovery matrix'
        result = $overall
        safety = 'Read-only. This script never opens, closes, saves, refreshes, or modifies a PBIX.'
        prerequisite = 'At least two distinct saved PBIX files with visible titled windows must already be open and model-ready; bridge-only background targets are allowed but excluded from fallback-route equality.'
        blockedReason = $script:blockedReason
        passed = $passed
        failed = $failed
        routes = $script:routeEvidence
        tests = [object[]]$script:testResults
    }
    Write-TestUtf8NoBom -Path $resultPath -Text (($report | ConvertTo-Json -Depth 10) + "`n")
    Write-Host "Live discovery matrix: $overall ($passed passed, $failed failed)"
    Write-Host "JSON evidence: $resultPath"
}

if ($overall -eq 'BLOCKED') { exit 2 }
if ($overall -eq 'FAIL') { exit 1 }
