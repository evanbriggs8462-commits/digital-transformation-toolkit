Set-StrictMode -Version 2.0

$script:PbixIntakeRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Throw-PbixIntakeFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BlockerCode,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$NextAction,
        [string]$FailureStage = 'runtime',
        [switch]$Retryable,
        [switch]$RequiresIT
    )

    $exception = New-Object System.InvalidOperationException $Message
    $exception.Data['PbixIntakeFailure'] = $true
    $exception.Data['BlockerCode'] = $BlockerCode
    $exception.Data['FailureStage'] = $FailureStage
    $exception.Data['Retryable'] = $Retryable.IsPresent
    $exception.Data['RequiresIT'] = $RequiresIT.IsPresent
    $exception.Data['NextAction'] = $NextAction
    throw $exception
}

function Get-PbixIntakeFailureInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Exception)

    $candidate = $Exception
    if ($candidate -is [System.Management.Automation.ErrorRecord]) {
        $candidate = $candidate.Exception
    }
    if ($null -eq $candidate -or -not ($candidate -is [System.Exception])) {
        return [pscustomobject][ordered]@{
            blockerCode = 'UNCLASSIFIED_FAILURE'
            message = [string]$Exception
            failureStage = 'runtime'
            retryable = $false
            requiresIT = $false
            nextAction = 'Preserve the complete run folder and extend the failure knowledge base before retrying.'
        }
    }

    $isClassified = $candidate.Data.Contains('PbixIntakeFailure') -and [bool]$candidate.Data['PbixIntakeFailure']
    if (-not $isClassified) {
        return [pscustomobject][ordered]@{
            blockerCode = 'UNCLASSIFIED_FAILURE'
            message = [string]$candidate.Message
            failureStage = 'runtime'
            retryable = $false
            requiresIT = $false
            nextAction = 'Preserve the complete run folder and extend the failure knowledge base before retrying.'
        }
    }

    return [pscustomobject][ordered]@{
        blockerCode = [string]$candidate.Data['BlockerCode']
        message = [string]$candidate.Message
        failureStage = [string]$candidate.Data['FailureStage']
        retryable = [bool]$candidate.Data['Retryable']
        requiresIT = [bool]$candidate.Data['RequiresIT']
        nextAction = [string]$candidate.Data['NextAction']
    }
}

function Write-Utf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($fullPath, $Text, $encoding)
}

function Read-Utf8Text {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($Path), $encoding)
}

function Write-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowNull()][object]$InputObject,
        [ValidateRange(2, 100)][int]$Depth = 100
    )

    $json = $InputObject | ConvertTo-Json -Depth $Depth
    [void](Write-Utf8NoBom -Path $Path -Text ($json.TrimEnd() + "`n"))
}

function Normalize-PbixName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$PbixName)

    $value = $PbixName.Trim()
    $invalid = [string]::IsNullOrWhiteSpace($value) -or
        $value.StartsWith('-', [System.StringComparison]::Ordinal) -or
        $value.StartsWith('~$', [System.StringComparison]::Ordinal) -or
        $value -match '[\\/]' -or
        $value -match '[\x00-\x1f]' -or
        $value -in @('.', '..') -or
        -not [System.IO.Path]::GetFileName($value).Equals($value, [System.StringComparison]::Ordinal)
    if ($invalid -or -not [System.IO.Path]::GetExtension($value).Equals('.pbix', [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_TARGET_INVALID' -FailureStage 'discovery' `
            -Message 'PBIX target must be one exact .pbix filename, not a path or switch-like value.' `
            -NextAction 'Supply one exact .pbix filename only.'
    }
    return $value
}

function Convert-DesktopWindowTitleToPbixName {
    [CmdletBinding()]
    param([AllowNull()][string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    $value = [regex]::Replace($Title.Trim(), '(?i)\s+-\s+Power BI Desktop(?:\s*\(.*\))?$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    if ($value -match '(?i)^(untitled|new report)$') { return $null }
    if (-not [System.IO.Path]::GetExtension($value).Equals('.pbix', [System.StringComparison]::OrdinalIgnoreCase)) {
        $value += '.pbix'
    }
    if ($value -match '[\\/]') { return $null }
    return $value
}

function Read-DesktopBridgeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.IO.Pipes.NamedPipeClientStream]$Pipe,
        [Parameter(Mandatory = $true)][byte[]]$Buffer,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(Mandatory = $true)][datetime]$DeadlineUtc
    )

    $remainingMs = [int][Math]::Ceiling(($DeadlineUtc - [datetime]::UtcNow).TotalMilliseconds)
    if ($remainingMs -le 0) { throw 'Desktop Bridge response timed out.' }
    $task = $Pipe.ReadAsync($Buffer, $Offset, $Count)
    if (-not $task.Wait($remainingMs)) { throw 'Desktop Bridge response timed out.' }
    return [int]$task.Result
}

function Invoke-DesktopBridgeRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$Method,
        [hashtable]$Parameters = @{},
        [ValidateRange(50, 10000)][int]$TimeoutMs = 750
    )

    $pipe = $null
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', "pbi-desktop-bridge-$ProcessId", [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
        $pipe.Connect($TimeoutMs)
        $pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Byte
        $request = [ordered]@{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Parameters } | ConvertTo-Json -Depth 8 -Compress
        $body = [System.Text.Encoding]::UTF8.GetBytes($request)
        $header = [System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($body.Length)`r`n`r`n")
        $pipe.Write($header, 0, $header.Length)
        $pipe.Write($body, 0, $body.Length)
        $pipe.Flush()
        $deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMs)

        [byte[]]$headerBytes = @()
        $lastFour = New-Object byte[] 4
        $lastCount = 0
        while ($true) {
            $one = New-Object byte[] 1
            $read = Read-DesktopBridgeBytes -Pipe $pipe -Buffer $one -Offset 0 -Count 1 -DeadlineUtc $deadline
            if ($read -le 0) { throw 'Desktop Bridge closed before the header completed.' }
            $headerBytes += $one[0]
            if ($lastCount -lt 4) { $lastFour[$lastCount] = $one[0]; $lastCount++ }
            else { $lastFour[0] = $lastFour[1]; $lastFour[1] = $lastFour[2]; $lastFour[2] = $lastFour[3]; $lastFour[3] = $one[0] }
            if ($lastCount -eq 4 -and $lastFour[0] -eq 13 -and $lastFour[1] -eq 10 -and $lastFour[2] -eq 13 -and $lastFour[3] -eq 10) { break }
            if ($headerBytes.Length -gt 8192) { throw 'Desktop Bridge response header is unexpectedly large.' }
        }
        $headerText = [System.Text.Encoding]::ASCII.GetString($headerBytes)
        $match = [regex]::Match($headerText, '(?im)^Content-Length:\s*(\d+)\s*$')
        if (-not $match.Success) { throw 'Desktop Bridge response omitted Content-Length.' }
        $contentLength = [int]$match.Groups[1].Value
        if ($contentLength -lt 1 -or $contentLength -gt 16777216) { throw 'Desktop Bridge response length is invalid.' }

        $responseBytes = New-Object byte[] $contentLength
        $offset = 0
        while ($offset -lt $contentLength) {
            $read = Read-DesktopBridgeBytes -Pipe $pipe -Buffer $responseBytes -Offset $offset -Count ($contentLength - $offset) -DeadlineUtc $deadline
            if ($read -le 0) { throw 'Desktop Bridge closed before the body completed.' }
            $offset += $read
        }
        $response = [System.Text.Encoding]::UTF8.GetString($responseBytes) | ConvertFrom-Json
        if ($null -ne $response.PSObject.Properties['error'] -and $null -ne $response.error) { throw "Desktop Bridge request failed: $($response.error.message)" }
        if ($null -eq $response.PSObject.Properties['result']) { throw 'Desktop Bridge response omitted result.' }
        return $response.result
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $pipe) { $pipe.Dispose() }
    }
}

function Get-PbixPathFromCommandLine {
    [CmdletBinding()]
    param([AllowNull()][string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $quoted = [regex]::Matches($CommandLine, '(?i)"([^"\r\n]+\.pbix)"')
    if ($quoted.Count -gt 0) { return [string]$quoted[$quoted.Count - 1].Groups[1].Value }
    $unquoted = [regex]::Match($CommandLine, '(?i)([A-Za-z]:\\[^"\r\n]*?\.pbix)(?:\s*$)')
    if ($unquoted.Success) { return [string]$unquoted.Groups[1].Value.Trim() }
    return $null
}

function Get-PowerBIDesktopTargets {
    [CmdletBinding()]
    param(
        [switch]$DisableDesktopBridge,
        [switch]$DisableCommandLine,
        [switch]$IncludeIgnored
    )

    $commandLines = @{}
    try {
        if ($DisableCommandLine) { throw 'Command-line discovery disabled for this test.' }
        foreach ($row in @(Get-CimInstance Win32_Process -Filter "Name='PBIDesktop.exe'" -ErrorAction Stop)) {
            $commandLines[[int]$row.ProcessId] = [string]$row.CommandLine
        }
    }
    catch { }

    $output = @()
    foreach ($process in @(Get-Process -Name 'PBIDesktop' -ErrorAction SilentlyContinue)) {
        $bridge = if ($DisableDesktopBridge) { $null } else { Invoke-DesktopBridgeRequest -ProcessId $process.Id -Method 'application.state.get/v1' }
        $bridgePath = $null
        $bridgeName = $null
        $hasUnsavedChanges = $null
        if ($null -ne $bridge) {
            if ($null -ne $bridge.PSObject.Properties['currentFilePath']) { $bridgePath = [string]$bridge.currentFilePath }
            if (-not [string]::IsNullOrWhiteSpace($bridgePath) -and [System.IO.Path]::GetExtension($bridgePath).Equals('.pbix', [System.StringComparison]::OrdinalIgnoreCase)) {
                $bridgeName = [System.IO.Path]::GetFileName($bridgePath)
            }
            if ($null -ne $bridge.PSObject.Properties['hasUnsavedChanges']) { $hasUnsavedChanges = [bool]$bridge.hasUnsavedChanges }
        }

        $commandLine = if ($commandLines.ContainsKey([int]$process.Id)) { [string]$commandLines[[int]$process.Id] } else { $null }
        $commandLinePath = Get-PbixPathFromCommandLine -CommandLine $commandLine
        $commandLineName = if ([string]::IsNullOrWhiteSpace($commandLinePath)) { $null } else { [System.IO.Path]::GetFileName($commandLinePath) }
        $windowTitle = [string]$process.MainWindowTitle
        $windowName = Convert-DesktopWindowTitleToPbixName -Title $windowTitle

        $names = @($bridgeName, $commandLineName, $windowName) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        $distinct = @($names | ForEach-Object { ([string]$_).ToUpperInvariant() } | Select-Object -Unique)
        $identityConflict = $distinct.Count -gt 1
        $chosenName = if ($bridgeName) { $bridgeName } elseif ($commandLineName) { $commandLineName } else { $windowName }
        $source = if ($bridgeName) { 'desktop-bridge' } elseif ($commandLineName) { 'command-line' } elseif ($windowName) { 'window-title' } else { 'unresolved' }
        $currentPath = if ($bridgePath) { $bridgePath } else { $commandLinePath }
        $isUnsaved = [string]::IsNullOrWhiteSpace($chosenName) -and ($windowTitle -match '(?i)\b(untitled|new report)\b')
        $ignoredReason = $null
        if ((-not [string]::IsNullOrWhiteSpace($chosenName) -and [System.IO.Path]::GetFileName($chosenName).StartsWith('~$', [System.StringComparison]::Ordinal)) -or
            (-not [string]::IsNullOrWhiteSpace($currentPath) -and $currentPath -match '(?i)[\\/]Power BI Desktop[^\\/]*[\\/]TempSaves[\\/]') -or
            (-not [string]::IsNullOrWhiteSpace($currentPath) -and $currentPath -match '(?i)[\\/]TempSaves[\\/]' -and $windowTitle -match '(?i)\bUntitled\b')) {
            $ignoredReason = 'internal-temp-recovery-model'
        }

        $target = [pscustomobject][ordered]@{
            ProcessId = [int]$process.Id
            PbixName = $chosenName
            CurrentFilePath = $currentPath
            Path = $currentPath
            HasUnsavedChanges = $hasUnsavedChanges
            IsUnsaved = [bool]$isUnsaved
            DiscoverySource = $source
            IdentityConflict = [bool]$identityConflict
            BridgePath = $bridgePath
            BridgeName = $bridgeName
            BridgeCurrentFilePath = $bridgePath
            BridgePbixName = $bridgeName
            CommandLine = $commandLine
            CommandLinePath = $commandLinePath
            CommandLineName = $commandLineName
            CommandLineFilePath = $commandLinePath
            CommandLinePbixName = $commandLineName
            WindowTitle = $windowTitle
            WindowName = $windowName
            WindowPbixName = $windowName
            DiscoveryEvidence = [pscustomobject][ordered]@{
                bridge = [pscustomobject][ordered]@{ path = $bridgePath; name = $bridgeName; available = ($null -ne $bridge) }
                commandLine = [pscustomobject][ordered]@{ path = $commandLinePath; name = $commandLineName; available = (-not [string]::IsNullOrWhiteSpace($commandLine)) }
                window = [pscustomobject][ordered]@{ title = $windowTitle; name = $windowName }
                conflict = [bool]$identityConflict
                selectedSource = $source
            }
            IgnoredReason = $ignoredReason
        }
        if ($IncludeIgnored -or [string]::IsNullOrWhiteSpace($ignoredReason)) { $output += $target }
    }
    return $output
}

function Select-PbixTarget {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$PbixName,
        [Parameter()][AllowEmptyCollection()][object[]]$Targets
    )

    [object[]]$items = @()
    if ($PSBoundParameters.ContainsKey('Targets')) { $items = [object[]]@($Targets) }
    else { $items = [object[]]@(Get-PowerBIDesktopTargets) }
    if ($items.Count -eq 0) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_NOT_OPEN' -FailureStage 'discovery' -Message 'No durable PBIX window is open.' -NextAction 'Open a PBIX in Power BI Desktop and wait for its Data pane.' -Retryable
    }

    [object[]]$ignoredItems = @($items | Where-Object {
        $candidateName = [string]$_.PbixName
        $candidatePath = if ($null -ne $_.PSObject.Properties['CurrentFilePath']) { [string]$_.CurrentFilePath } elseif ($null -ne $_.PSObject.Properties['Path']) { [string]$_.Path } else { '' }
        $explicitIgnore = $null -ne $_.PSObject.Properties['IgnoredReason'] -and -not [string]::IsNullOrWhiteSpace([string]$_.IgnoredReason)
        $explicitIgnore -or $candidateName.StartsWith('~$', [System.StringComparison]::Ordinal) -or $candidatePath -match '(?i)[\\/]TempSaves[\\/]'
    })
    [object[]]$items = @($items | Where-Object {
        $candidateName = [string]$_.PbixName
        $candidatePath = if ($null -ne $_.PSObject.Properties['CurrentFilePath']) { [string]$_.CurrentFilePath } elseif ($null -ne $_.PSObject.Properties['Path']) { [string]$_.Path } else { '' }
        $explicitIgnore = $null -ne $_.PSObject.Properties['IgnoredReason'] -and -not [string]::IsNullOrWhiteSpace([string]$_.IgnoredReason)
        -not ($explicitIgnore -or $candidateName.StartsWith('~$', [System.StringComparison]::Ordinal) -or $candidatePath -match '(?i)[\\/]TempSaves[\\/]')
    })
    if (@($items).Count -eq 0) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_TARGET_UNSAVED' -FailureStage 'discovery' -Message 'Only an internal TempSaves/unsaved model was found; it is not a durable selectable PBIX.' -NextAction 'Save or open the real PBIX and retry.'
    }

    foreach ($item in $items) {
        $conflictProperty = $item.PSObject.Properties['IdentityConflict']
        if ($null -ne $conflictProperty -and [bool]$conflictProperty.Value) {
            Throw-PbixIntakeFailure -BlockerCode 'PBIX_IDENTITY_MISMATCH' -FailureStage 'discovery' -Message "Discovery evidence conflicts for Power BI Desktop PID $($item.ProcessId)." -NextAction 'Close stale Desktop instances and reopen the intended PBIX before retrying.'
        }
    }

    if ($PSBoundParameters.ContainsKey('PbixName')) {
        $requested = Normalize-PbixName -PbixName $PbixName
        $matches = @($items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.PbixName) -and ([string]$_.PbixName).Equals($requested, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($matches.Count -eq 0) {
            Throw-PbixIntakeFailure -BlockerCode 'PBIX_TARGET_NOT_FOUND' -FailureStage 'discovery' -Message "Exact PBIX filename '$requested' is not open." -NextAction 'Use one of the exact open filenames recorded in run.json.'
        }
        if ($matches.Count -gt 1) {
            Throw-PbixIntakeFailure -BlockerCode 'PBIX_TARGET_DUPLICATE' -FailureStage 'discovery' -Message "The same PBIX basename '$requested' is open in more than one Desktop process." -NextAction 'Close one copy and retry.'
        }
        return $matches[0]
    }

    $durable = @($items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.PbixName) })
    if ($durable.Count -eq 0) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_TARGET_UNSAVED' -FailureStage 'discovery' -Message 'Power BI Desktop is open, but no durable PBIX filename can be proven.' -NextAction 'Save the model as a PBIX first.'
    }
    $groups = @($durable | Group-Object { ([string]$_.PbixName).ToUpperInvariant() })
    if (@($groups | Where-Object { $_.Count -gt 1 }).Count -gt 0) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_TARGET_DUPLICATE' -FailureStage 'discovery' -Message 'The same PBIX basename is open in more than one Desktop process.' -NextAction 'Close one duplicate copy or provide a uniquely open PBIX.'
    }
    if ($groups.Count -gt 1) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_TARGET_AMBIGUOUS' -FailureStage 'discovery' -Message 'Several distinct PBIX files are open and no exact target was supplied.' -NextAction 'Rerun with -PbixName and one exact filename.'
    }
    return $durable[0]
}

function Get-ListeningTcpPortsForProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $ports = @()
    if ($null -ne (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        try {
            $ports += @(Get-NetTCPConnection -State Listen -OwningProcess $ProcessId -ErrorAction Stop | ForEach-Object { [int]$_.LocalPort })
        }
        catch { }
    }
    if ($ports.Count -eq 0) {
        try {
            foreach ($line in @(& netstat.exe -ano -p tcp 2>$null)) {
                $match = [regex]::Match([string]$line, '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$')
                if ($match.Success -and [int]$match.Groups[2].Value -eq $ProcessId) { $ports += [int]$match.Groups[1].Value }
            }
        }
        catch { }
    }
    return @($ports | Where-Object { $_ -gt 0 -and $_ -le 65535 } | Sort-Object -Unique)
}

function Get-LocalDesktopModelContexts {
    [CmdletBinding()]
    param()

    try {
        $processes = @(Get-CimInstance Win32_Process -Filter "Name='msmdsrv.exe'" -ErrorAction Stop | Select-Object ProcessId, ParentProcessId, CommandLine)
    }
    catch { $processes = @() }
    $contexts = @()
    foreach ($proc in $processes) {
        $commandLine = [string]$proc.CommandLine
        $pathMatch = [regex]::Match($commandLine, '(?i)(?:^|\s)-s\s+"([^"]+)"')
        if (-not $pathMatch.Success) { $pathMatch = [regex]::Match($commandLine, '(?i)(?:^|\s)-s\s+(\S+)') }
        $dataPath = if ($pathMatch.Success) { [string]$pathMatch.Groups[1].Value } else { $null }
        $issueCode = $null
        $issueMessage = $null
        if ([string]::IsNullOrWhiteSpace($dataPath) -or -not (Test-Path -LiteralPath $dataPath -PathType Container)) {
            $issueCode = 'PBIX_MODEL_NOT_READY'; $issueMessage = 'Analysis Services data directory could not be resolved.'
        }

        $portFilePath = if ($dataPath) { Join-Path $dataPath 'msmdsrv.port.txt' } else { $null }
        $portFilePort = $null
        if ($portFilePath -and (Test-Path -LiteralPath $portFilePath -PathType Leaf)) {
            $candidate = ((Read-Utf8Text -Path $portFilePath) -replace "`0", '').Trim()
            if ($candidate -match '^\d+$' -and [int]$candidate -gt 0 -and [int]$candidate -le 65535) { $portFilePort = [int]$candidate }
        }
        [object[]]$listenerPorts = @(Get-ListeningTcpPortsForProcess -ProcessId ([int]$proc.ProcessId))
        $port = $null
        $portSource = $null
        if ($listenerPorts.Count -gt 1) {
            $issueCode = 'PBIX_CONTEXT_AMBIGUOUS'; $issueMessage = 'The Analysis Services child owns more than one distinct TCP listener.'
        }
        elseif ($listenerPorts.Count -eq 1) {
            $port = [int]$listenerPorts[0]; $portSource = 'tcp-listener'
            if ($null -ne $portFilePort -and [int]$portFilePort -ne $port) {
                # The live socket is owned by this exact msmdsrv PID. A stale
                # port file is retained as evidence but never overrides it.
                $portSource = 'tcp-listener-overrode-port-file'
            }
            elseif ($null -ne $portFilePort) { $portSource = 'tcp-listener+port-file' }
        }
        elseif ($null -ne $portFilePort) {
            $issueCode = 'PBIX_MODEL_NOT_READY'; $issueMessage = 'A port file exists, but no live listener owned by the model process was found.'
        }
        else {
            $issueCode = 'PBIX_MODEL_NOT_READY'; $issueMessage = 'No live Analysis Services listener was found.'
        }

        [object[]]$dbFiles = @()
        if ($dataPath -and (Test-Path -LiteralPath $dataPath -PathType Container)) {
            $dbFiles = [object[]]@(Get-ChildItem -LiteralPath $dataPath -Filter '*.db.xml' -File -ErrorAction SilentlyContinue)
        }
        $catalog = $null
        $databaseName = $null
        $dbXmlPath = $null
        if ($dbFiles.Count -eq 0) {
            if (-not $issueCode) { $issueCode = 'PBIX_MODEL_NOT_READY'; $issueMessage = 'No database metadata file exists yet.' }
        }
        elseif ($dbFiles.Count -gt 1) {
            $issueCode = 'PBIX_CONTEXT_AMBIGUOUS'; $issueMessage = 'More than one database metadata file exists for the selected model process.'
        }
        else {
            $dbXmlPath = $dbFiles[0].FullName
            try {
                $xml = New-Object System.Xml.XmlDocument
                $xml.Load($dbXmlPath)
                $databaseNode = $xml.SelectSingleNode("//*[local-name()='ObjectDefinition']/*[local-name()='Database']")
                if ($null -eq $databaseNode) { $databaseNode = $xml.SelectSingleNode("//*[local-name()='Database']") }
                if ($null -ne $databaseNode) {
                    $idNode = $databaseNode.SelectSingleNode("./*[local-name()='ID']")
                    $nameNode = $databaseNode.SelectSingleNode("./*[local-name()='Name']")
                    if ($null -ne $idNode) { $catalog = [string]$idNode.InnerText }
                    if ($null -ne $nameNode) { $databaseName = [string]$nameNode.InnerText }
                }
                if ([string]::IsNullOrWhiteSpace($catalog)) { $issueCode = 'PBIX_MODEL_NOT_READY'; $issueMessage = 'The database catalog ID is not available yet.' }
            }
            catch { $issueCode = 'PBIX_MODEL_NOT_READY'; $issueMessage = 'The database metadata file could not be parsed.' }
        }

        $desktopWindowTitle = $null
        $desktopProcess = Get-Process -Id ([int]$proc.ParentProcessId) -ErrorAction SilentlyContinue
        if ($null -ne $desktopProcess -and $desktopProcess.ProcessName -like 'PBIDesktop*') { $desktopWindowTitle = [string]$desktopProcess.MainWindowTitle }
        $contexts += [pscustomobject][ordered]@{
            Server = if ($null -ne $port) { "localhost:$port" } else { $null }
            Catalog = $catalog
            Port = $port
            DesktopProcessId = [int]$proc.ParentProcessId
            ParentProcessId = [int]$proc.ParentProcessId
            ModelProcessId = [int]$proc.ProcessId
            ProcessId = [int]$proc.ProcessId
            DataPath = $dataPath
            CommandLine = $commandLine
            PortFilePath = $portFilePath
            PortFilePort = $portFilePort
            ListenerPorts = [object[]]$listenerPorts
            PortSource = $portSource
            DbXmlPath = $dbXmlPath
            DatabaseName = $databaseName
            CatalogSource = if ($catalog) { 'db.xml' } else { $null }
            DesktopWindowTitle = $desktopWindowTitle
            CatalogCount = $dbFiles.Count
            IssueCode = $issueCode
            IssueMessage = $issueMessage
            DiscoveryEvidence = [pscustomobject][ordered]@{
                desktopProcessId = [int]$proc.ParentProcessId
                modelProcessId = [int]$proc.ProcessId
                dataPath = $dataPath
                listenerPorts = [object[]]$listenerPorts
                portFilePort = $portFilePort
                selectedPort = $port
                portSource = $portSource
                dbXmlPaths = [object[]]@($dbFiles | ForEach-Object { $_.FullName })
                selectedCatalog = $catalog
            }
        }
    }
    return $contexts
}

function Resolve-PbixModelContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Target,
        [Parameter()][AllowEmptyCollection()][object[]]$Contexts
    )

    if ($null -eq $Target.PSObject.Properties['ProcessId'] -or [int]$Target.ProcessId -le 0) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_IDENTITY_MISMATCH' -FailureStage 'model-context' -Message 'The selected PBIX has no verified Desktop process ID.' -NextAction 'Rediscover the open PBIX and do not guess its endpoint.'
    }
    [object[]]$items = @()
    if ($PSBoundParameters.ContainsKey('Contexts')) { $items = [object[]]@($Contexts) }
    else { $items = [object[]]@(Get-LocalDesktopModelContexts) }
    $matches = @($items | Where-Object {
        ($null -ne $_.PSObject.Properties['DesktopProcessId'] -and [int]$_.DesktopProcessId -eq [int]$Target.ProcessId) -or
        ($null -ne $_.PSObject.Properties['ParentProcessId'] -and [int]$_.ParentProcessId -eq [int]$Target.ProcessId)
    })
    if ($matches.Count -eq 0) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_MODEL_NOT_READY' -FailureStage 'model-context' -Message 'The selected Desktop process has no verified Analysis Services child context.' -NextAction 'Wait for the Data pane to finish loading and retry once.' -Retryable
    }
    if ($matches.Count -gt 1) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_CONTEXT_AMBIGUOUS' -FailureStage 'model-context' -Message 'More than one Analysis Services child context maps to the selected Desktop PID.' -NextAction 'Close extra Desktop instances and retry.'
    }
    $context = $matches[0]
    if ($null -ne $context.PSObject.Properties['IssueCode'] -and -not [string]::IsNullOrWhiteSpace([string]$context.IssueCode)) {
        $message = if ([string]::IsNullOrWhiteSpace([string]$context.IssueMessage)) { 'The selected model context failed identity validation.' } else { [string]$context.IssueMessage }
        $next = if ([string]$context.IssueCode -eq 'PBIX_MODEL_NOT_READY') { 'Wait for the Data pane to finish loading and retry once.' } else { 'Close stale or extra Desktop instances, reopen the intended PBIX, and retry.' }
        Throw-PbixIntakeFailure -BlockerCode ([string]$context.IssueCode) -FailureStage 'model-context' -Message $message -NextAction $next -Retryable:([string]$context.IssueCode -eq 'PBIX_MODEL_NOT_READY')
    }
    if ([string]::IsNullOrWhiteSpace([string]$context.Server) -or [string]::IsNullOrWhiteSpace([string]$context.Catalog)) {
        Throw-PbixIntakeFailure -BlockerCode 'PBIX_MODEL_NOT_READY' -FailureStage 'model-context' -Message 'The verified server and catalog are incomplete.' -NextAction 'Wait for the Data pane to finish loading and retry once.' -Retryable
    }
    return $context
}

function ConvertTo-NormalizedVersion {
    param([Parameter(Mandatory = $true)][string]$Value)
    $match = [regex]::Match($Value, '\d+(?:\.\d+){1,3}')
    if (-not $match.Success) { return $null }
    try { return [version]$match.Value } catch { return $null }
}

function Get-ToolDistributionFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)

    $executable = [System.IO.Path]::GetFullPath($ExecutablePath)
    $root = [System.IO.Path]::GetDirectoryName($executable).TrimEnd([char[]]@('\', '/'))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_MISSING' -FailureStage 'tool-validation' -Message 'Registered tool distribution root is missing.' -NextAction 'Restore the complete approved distribution and rerun the initializer.' -RequiresIT
    }

    $executableName = [System.IO.Path]::GetFileName($executable)
    if ($executableName.Equals('dscmd.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        # dscmd.exe probes the adjacent bin directory. Hash the launcher/config, every
        # directly probed managed dependency, the x64 native dependency, and the
        # current UI-culture satellite directory. Other culture-only resources and
        # unrelated DAX Studio GUI/uninstaller files are intentionally excluded so
        # repeated read-only intake does not hash hundreds of unused satellite files.
        $candidates = @()
        foreach ($launcherPath in @($executable, "$executable.config")) {
            if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
                $candidates += Get-Item -LiteralPath $launcherPath -ErrorAction Stop
            }
        }
        $binPath = Join-Path $root 'bin'
        if (Test-Path -LiteralPath $binPath -PathType Container) {
            $candidates += @(Get-ChildItem -LiteralPath $binPath -File -ErrorAction Stop)
            $nativePath = Join-Path $binPath 'runtimes\win-x64\native'
            if (Test-Path -LiteralPath $nativePath -PathType Container) {
                $candidates += @(Get-ChildItem -LiteralPath $nativePath -File -ErrorAction Stop)
            }
            $cultureNames = @(
                [System.Globalization.CultureInfo]::CurrentUICulture.Name,
                [System.Globalization.CultureInfo]::CurrentUICulture.Parent.Name
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique
            foreach ($cultureName in $cultureNames) {
                $culturePath = Join-Path $binPath $cultureName
                if (Test-Path -LiteralPath $culturePath -PathType Container) {
                    $candidates += @(Get-ChildItem -LiteralPath $culturePath -File -ErrorAction Stop)
                }
            }
        }
        [object[]]$files = @($candidates | Sort-Object -Property FullName -Unique)
    }
    else {
        [object[]]$files = @(
            @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction Stop | Where-Object {
                # Ignore operational/corporate log residue that is not loaded as program code or configuration.
                $_.Extension -ine '.log' -and $_.Name -notlike 'WindowsLaps*'
            }) | Sort-Object -Property FullName
        )
    }
    return [object[]]$files
}

function New-ToolDistributionRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)

    $executable = [System.IO.Path]::GetFullPath($ExecutablePath)
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_MISSING' -FailureStage 'tool-validation' -Message 'Tool executable is missing while recording its distribution.' -NextAction 'Restore the complete approved distribution.' -RequiresIT
    }
    $root = [System.IO.Path]::GetDirectoryName($executable).TrimEnd([char[]]@('\', '/'))
    $entries = @()
    foreach ($file in @(Get-ToolDistributionFiles -ExecutablePath $executable)) {
        $relative = $file.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^|/)\.\.(/|$)') {
            Throw-PbixIntakeFailure -BlockerCode 'TOOL_IDENTITY_INVALID' -FailureStage 'tool-validation' -Message 'Tool distribution contains an invalid relative path.' -NextAction 'Restore the genuine complete distribution.' -RequiresIT
        }
        $entries += [pscustomobject][ordered]@{
            path = $relative
            bytes = [int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        }
    }
    if ($entries.Count -eq 0) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_RUNTIME_INCOMPLETE' -FailureStage 'tool-validation' -Message 'Tool distribution contains no registered files.' -NextAction 'Restore the complete approved distribution.' -RequiresIT
    }
    return [pscustomobject][ordered]@{
        root = $root
        files = [object[]]$entries
    }
}

function Assert-ToolDistribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [Parameter(Mandatory = $true)][object]$ExpectedRecord
    )

    if ($null -eq $ExpectedRecord.PSObject.Properties['root'] -or $null -eq $ExpectedRecord.PSObject.Properties['files']) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message 'Tool distribution registration is incomplete.' -NextAction 'Rerun the one-time initializer.'
    }
    $actual = New-ToolDistributionRecord -ExecutablePath $ExecutablePath
    $expectedRoot = [System.IO.Path]::GetFullPath([string]$ExpectedRecord.root).TrimEnd([char[]]@('\', '/'))
    if (-not $actual.root.Equals($expectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_DISTRIBUTION_CHANGED' -FailureStage 'tool-validation' -Message 'Tool distribution root changed after provisioning.' -NextAction 'Review the installation and rerun the initializer explicitly.' -RequiresIT
    }

    $expectedFiles = @($ExpectedRecord.files)
    $actualFiles = @($actual.files)
    if ($expectedFiles.Count -ne $actualFiles.Count) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_DISTRIBUTION_CHANGED' -FailureStage 'tool-validation' -Message "Tool distribution file count changed after provisioning (expected $($expectedFiles.Count), found $($actualFiles.Count))." -NextAction 'Review the installation and rerun the initializer explicitly.' -RequiresIT
    }
    $actualByPath = @{}
    foreach ($entry in $actualFiles) {
        $key = ([string]$entry.path).ToUpperInvariant()
        if ($actualByPath.ContainsKey($key)) {
            Throw-PbixIntakeFailure -BlockerCode 'TOOL_DISTRIBUTION_CHANGED' -FailureStage 'tool-validation' -Message 'Tool distribution contains duplicate normalized paths.' -NextAction 'Restore the genuine complete distribution.' -RequiresIT
        }
        $actualByPath[$key] = $entry
    }
    $expectedPaths = @{}
    foreach ($expected in $expectedFiles) {
        if ($null -eq $expected.PSObject.Properties['path'] -or $null -eq $expected.PSObject.Properties['bytes'] -or $null -eq $expected.PSObject.Properties['sha256']) {
            Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message 'Tool distribution registration contains an invalid entry.' -NextAction 'Rerun the one-time initializer.'
        }
        $key = ([string]$expected.path).ToUpperInvariant()
        if ($expectedPaths.ContainsKey($key)) {
            Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message 'Tool distribution registration contains duplicate normalized paths.' -NextAction 'Rerun the one-time initializer.'
        }
        $expectedPaths[$key] = $true
        if (-not $actualByPath.ContainsKey($key)) {
            Throw-PbixIntakeFailure -BlockerCode 'TOOL_DISTRIBUTION_CHANGED' -FailureStage 'tool-validation' -Message "Tool distribution file disappeared: $($expected.path)" -NextAction 'Review the installation and rerun the initializer explicitly.' -RequiresIT
        }
        $found = $actualByPath[$key]
        if ([int64]$found.bytes -ne [int64]$expected.bytes -or -not ([string]$found.sha256).Equals([string]$expected.sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            Throw-PbixIntakeFailure -BlockerCode 'TOOL_DISTRIBUTION_CHANGED' -FailureStage 'tool-validation' -Message "Tool distribution file changed: $($expected.path)" -NextAction 'Review the installation and rerun the initializer explicitly.' -RequiresIT
        }
    }
    return $actual
}

function Assert-ToolRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('TE2', 'DAX')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExpectedSha256,
        [string]$ExpectedVersion,
        [string]$ExpectedSignerSubject
    )

    $fullPath = try { [System.IO.Path]::GetFullPath($Path) } catch { $null }
    if ([string]::IsNullOrWhiteSpace($fullPath) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_MISSING' -FailureStage 'tool-validation' -Message "$Kind executable is missing at its registered path." -NextAction 'Restore it through the approved provisioning path, then rerun the initializer.' -RequiresIT
    }
    $expectedFile = if ($Kind -eq 'TE2') { 'TabularEditor.exe' } else { 'dscmd.exe' }
    if (-not [System.IO.Path]::GetFileName($fullPath).Equals($expectedFile, [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_IDENTITY_INVALID' -FailureStage 'tool-validation' -Message "$Kind must point to $expectedFile." -NextAction 'Select the genuine vendor executable.' -RequiresIT
    }
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fullPath)
    $productName = [string]$versionInfo.ProductName
    $productRegex = if ($Kind -eq 'TE2') { '(?i)Tabular\s+Editor' } else { '(?i)DAX\s+Studio' }
    if ([string]::IsNullOrWhiteSpace($productName) -or $productName -notmatch $productRegex) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_IDENTITY_INVALID' -FailureStage 'tool-validation' -Message "$Kind product metadata is not the expected vendor product." -NextAction 'Select the genuine vendor executable.' -RequiresIT
    }
    $productVersion = if ([string]::IsNullOrWhiteSpace([string]$versionInfo.ProductVersion)) { [string]$versionInfo.FileVersion } else { [string]$versionInfo.ProductVersion }
    $parsedVersion = ConvertTo-NormalizedVersion -Value $productVersion
    $minimum = if ($Kind -eq 'TE2') { [version]'2.28.0' } else { [version]'3.5.2' }
    if ($null -eq $parsedVersion -or $parsedVersion -lt $minimum) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_VERSION_UNSUPPORTED' -FailureStage 'tool-validation' -Message "$Kind $minimum or later is required; found '$productVersion'." -NextAction 'Provision an approved supported version and rerun the initializer.' -RequiresIT
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and -not $productVersion.Equals($ExpectedVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_CHANGED' -FailureStage 'tool-validation' -Message "$Kind version metadata changed after provisioning." -NextAction 'Review the update and rerun the initializer explicitly.' -RequiresIT
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $fullPath
    $signatureStatus = [string]$signature.Status
    $signerSubject = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    $publisherRegex = if ($Kind -eq 'TE2') { '(?i)(Tabular\s+Editor|Kapacity)' } else { '(?i)(SQLBI|DAX\s+Studio)' }
    if ($signatureStatus -ne 'Valid' -or $signerSubject -notmatch $publisherRegex) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_SIGNATURE_INVALID' -FailureStage 'tool-validation' -Message "$Kind Authenticode signature or publisher is invalid." -NextAction 'Stop and ask IT or the vendor; do not bypass application policy.' -RequiresIT
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSignerSubject) -and -not $signerSubject.Equals($ExpectedSignerSubject, [System.StringComparison]::Ordinal)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_CHANGED' -FailureStage 'tool-validation' -Message "$Kind signer changed after provisioning." -NextAction 'Review the new signature and rerun the initializer explicitly.' -RequiresIT
    }
    $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$' -or -not $hash.Equals($ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            Throw-PbixIntakeFailure -BlockerCode 'TOOL_CHANGED' -FailureStage 'tool-validation' -Message "$Kind SHA-256 changed after provisioning." -NextAction 'Review the binary and rerun the initializer explicitly.' -RequiresIT
        }
    }
    return [pscustomobject][ordered]@{
        kind = $Kind.ToLowerInvariant()
        path = $fullPath
        fileName = [System.IO.Path]::GetFileName($fullPath)
        productName = $productName
        productVersion = $productVersion
        fileVersion = [string]$versionInfo.FileVersion
        signatureStatus = $signatureStatus
        signerSubject = $signerSubject
        sha256 = $hash
    }
}

function Assert-RegisteredTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('TE2', 'DAX')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExpectedSha256,
        [string]$ExpectedVersion,
        [string]$ExpectedSignerSubject
    )
    return Assert-ToolRegistration @PSBoundParameters
}

function Get-RegisteredTools {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message 'config/tools.json does not exist.' -NextAction 'Run the one-time initializer with approved executable paths.'
    }
    try { $config = Read-Utf8Text -Path $ConfigPath | ConvertFrom-Json -ErrorAction Stop }
    catch { Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message 'config/tools.json is invalid.' -NextAction 'Rerun the one-time initializer with approved executable paths.' }
    if ($null -eq $config.PSObject.Properties['schemaVersion'] -or [int]$config.schemaVersion -ne 2 -or $null -eq $config.PSObject.Properties['tools']) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message 'config/tools.json has an unsupported schema.' -NextAction 'Rerun the one-time initializer.'
    }
    $te2Record = $config.tools.PSObject.Properties['te2']
    $daxRecord = $config.tools.PSObject.Properties['dax']
    if ($null -eq $te2Record -or $null -eq $daxRecord) {
        Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message 'config/tools.json does not register both required tools.' -NextAction 'Rerun the one-time initializer.'
    }
    foreach ($record in @($te2Record.Value, $daxRecord.Value)) {
        foreach ($requiredProperty in @('path', 'sha256', 'productVersion', 'signerSubject', 'distributionRoot', 'distributionFiles')) {
            if ($null -eq $record.PSObject.Properties[$requiredProperty]) {
                Throw-PbixIntakeFailure -BlockerCode 'TOOLS_NOT_PROVISIONED' -FailureStage 'tool-validation' -Message "config/tools.json is missing required tool property '$requiredProperty'." -NextAction 'Rerun the one-time initializer.'
            }
        }
    }
    $te2 = Assert-ToolRegistration -Kind TE2 -Path ([string]$te2Record.Value.path) -ExpectedSha256 ([string]$te2Record.Value.sha256) -ExpectedVersion ([string]$te2Record.Value.productVersion) -ExpectedSignerSubject ([string]$te2Record.Value.signerSubject)
    $dax = Assert-ToolRegistration -Kind DAX -Path ([string]$daxRecord.Value.path) -ExpectedSha256 ([string]$daxRecord.Value.sha256) -ExpectedVersion ([string]$daxRecord.Value.productVersion) -ExpectedSignerSubject ([string]$daxRecord.Value.signerSubject)
    [void](Assert-ToolDistribution -ExecutablePath $te2.path -ExpectedRecord ([pscustomobject][ordered]@{ root = $te2Record.Value.distributionRoot; files = $te2Record.Value.distributionFiles }))
    [void](Assert-ToolDistribution -ExecutablePath $dax.path -ExpectedRecord ([pscustomobject][ordered]@{ root = $daxRecord.Value.distributionRoot; files = $daxRecord.Value.distributionFiles }))
    return [pscustomobject][ordered]@{ SchemaVersion = 2; Te2 = $te2; Dax = $dax }
}

function ConvertTo-WindowsCommandLineArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    if ($Value.Length -eq 0) { return '""' }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]0x5c) {
            $backslashes++
            continue
        }
        if ($character -eq [char]0x22) {
            if ($backslashes -gt 0) { [void]$builder.Append([char]0x5c, $backslashes * 2) }
            [void]$builder.Append([char]0x5c)
            [void]$builder.Append([char]0x22)
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append([char]0x5c, $backslashes)
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append([char]0x5c, $backslashes * 2) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-BoundedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter()][AllowEmptyCollection()][string[]]$ArgumentList = @(),
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 120,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath,
        [string]$TimeoutBlockerCode = 'TOOL_TIMEOUT'
    )

    $stdoutFull = [System.IO.Path]::GetFullPath($StdoutPath)
    $stderrFull = [System.IO.Path]::GetFullPath($StderrPath)
    foreach ($folder in @([System.IO.Path]::GetDirectoryName($stdoutFull), [System.IO.Path]::GetDirectoryName($stderrFull))) {
        if (-not [string]::IsNullOrWhiteSpace($folder) -and -not (Test-Path -LiteralPath $folder -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($folder) }
    }
    $process = $null
    $timedOut = $false
    $terminationConfirmed = $true
    try {
        $nativeArguments = (@($ArgumentList | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value ([string]$_) }) -join ' ')
        $process = Start-Process -FilePath $FilePath -ArgumentList $nativeArguments -PassThru -NoNewWindow -RedirectStandardOutput $stdoutFull -RedirectStandardError $stderrFull
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch { }
            try { $terminationConfirmed = $process.WaitForExit(5000) } catch { $terminationConfirmed = $false }
            if (-not $terminationConfirmed) { try { $process.Kill(); $terminationConfirmed = $process.WaitForExit(5000) } catch { $terminationConfirmed = $false } }
        }
        if ($terminationConfirmed) { try { $process.WaitForExit() } catch { } }
    }
    catch {
        $diagnostic = [string]$_.Exception.Message
        if ($diagnostic -match '(?i)(blocked|applocker|application control|access is denied|unauthorized|policy)') {
            Throw-PbixIntakeFailure -BlockerCode 'TOOL_EXECUTION_BLOCKED' -FailureStage 'tool-execution' -Message "Tool execution was blocked: $diagnostic" -NextAction 'Give the registered executable hash, publisher, and logs to IT; do not bypass policy.' -RequiresIT
        }
        Throw-PbixIntakeFailure -BlockerCode 'TOOL_EXECUTION_BLOCKED' -FailureStage 'tool-execution' -Message "Tool could not start: $diagnostic" -NextAction 'Review the registered executable and captured logs.'
    }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $stdout = ''
    $stderr = ''
    foreach ($logSpec in @(
        [pscustomobject]@{ Path = $stdoutFull; Name = 'stdout' },
        [pscustomobject]@{ Path = $stderrFull; Name = 'stderr' }
    )) {
        $decoded = ''
        if (Test-Path -LiteralPath $logSpec.Path -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($logSpec.Path)
            try { $decoded = $strictUtf8.GetString($bytes) }
            catch { $decoded = [System.Text.Encoding]::Default.GetString($bytes) }
            [System.IO.File]::WriteAllText($logSpec.Path, $decoded, $utf8WithBom)
        }
        if ($logSpec.Name -eq 'stdout') { $stdout = $decoded } else { $stderr = $decoded }
    }
    if ($timedOut) {
        $next = if ($terminationConfirmed) { 'Confirm the target model is ready and retry once.' } else { 'Stop: the timed-out PID may still exist; ask IT to confirm termination.' }
        Throw-PbixIntakeFailure -BlockerCode $TimeoutBlockerCode -FailureStage 'tool-execution' -Message "Process exceeded the $TimeoutSeconds-second bound; terminationConfirmed=$terminationConfirmed." -NextAction $next -Retryable:$terminationConfirmed -RequiresIT:(-not $terminationConfirmed)
    }
    return [pscustomobject][ordered]@{
        FilePath = [System.IO.Path]::GetFullPath($FilePath)
        ArgumentList = [object[]]@($ArgumentList)
        ProcessId = if ($null -ne $process) { [int]$process.Id } else { $null }
        ExitCode = if ($null -ne $process) { [int]$process.ExitCode } else { $null }
        TimedOut = $false
        TerminationConfirmed = [bool]$terminationConfirmed
        StdoutPath = $stdoutFull
        StderrPath = $stderrFull
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Assert-EndpointValue {
    param([Parameter(Mandatory = $true)][string]$Server, [Parameter(Mandatory = $true)][string]$Catalog, [string]$BlockerCode)
    $match = [regex]::Match($Server, '(?i)^localhost:(\d{1,5})$')
    if (-not $match.Success -or [int]$match.Groups[1].Value -lt 1 -or [int]$match.Groups[1].Value -gt 65535 -or [string]::IsNullOrWhiteSpace($Catalog) -or $Catalog.StartsWith('-') -or $Catalog -match '[\r\n\x00]') {
        Throw-PbixIntakeFailure -BlockerCode $BlockerCode -FailureStage 'argument-construction' -Message 'Server/catalog values violate the fixed explicit-endpoint grammar.' -NextAction 'Use the PID-verified localhost port and exact catalog returned by discovery.'
    }
}

function Assert-RootedArgumentPath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$BlockerCode)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.StartsWith('-') -or -not [System.IO.Path]::IsPathRooted($Path)) {
        Throw-PbixIntakeFailure -BlockerCode $BlockerCode -FailureStage 'argument-construction' -Message 'Tool artifact/query paths must be rooted absolute paths.' -NextAction 'Use a rooted path inside the current unique run folder.'
    }
    try { return [System.IO.Path]::GetFullPath($Path) }
    catch { Throw-PbixIntakeFailure -BlockerCode $BlockerCode -FailureStage 'argument-construction' -Message 'A tool artifact/query path is invalid.' -NextAction 'Use a rooted path inside the current unique run folder.' }
}

function Get-Te2ExportArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Catalog,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][ValidateSet('BIM', 'TMDL')][string]$Format
    )
    Assert-EndpointValue -Server $Server -Catalog $Catalog -BlockerCode 'TE2_ARGUMENT_CONTRACT_FAILED'
    $fullOutput = Assert-RootedArgumentPath -Path $OutputPath -BlockerCode 'TE2_ARGUMENT_CONTRACT_FAILED'
    $mode = if ($Format -eq 'BIM') { '-B' } else { '-TMDL' }
    $arguments = @($Server, $Catalog, $mode, $fullOutput)
    $forbidden = @('-D', '-DEPLOY', '-S', '-SCRIPT', '-E', '-W')
    if (@($arguments | Where-Object { $forbidden -contains ([string]$_).ToUpperInvariant() }).Count -gt 0) {
        Throw-PbixIntakeFailure -BlockerCode 'READ_ONLY_GUARD_VIOLATION' -FailureStage 'argument-construction' -Message 'A forbidden TE2 write/script/deployment token appeared.' -NextAction 'Stop and fix the fixed argument builder; do not hand-edit the command.'
    }
    return [string[]]$arguments
}

function Get-DscmdCsvArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Catalog,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$QueryFile
    )
    Assert-EndpointValue -Server $Server -Catalog $Catalog -BlockerCode 'DAX_ARGUMENT_CONTRACT_FAILED'
    $output = Assert-RootedArgumentPath -Path $OutputPath -BlockerCode 'DAX_ARGUMENT_CONTRACT_FAILED'
    $query = Assert-RootedArgumentPath -Path $QueryFile -BlockerCode 'DAX_ARGUMENT_CONTRACT_FAILED'
    return [string[]]@('csv', $output, '--server', $Server, '--database', $Catalog, '--file', $query)
}

function Get-DscmdVpaxArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Catalog,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )
    Assert-EndpointValue -Server $Server -Catalog $Catalog -BlockerCode 'DAX_ARGUMENT_CONTRACT_FAILED'
    $output = Assert-RootedArgumentPath -Path $OutputPath -BlockerCode 'DAX_ARGUMENT_CONTRACT_FAILED'
    return [string[]]@('vpax', $output, '--server', $Server, '--database', $Catalog, '--donotreadstatsfromdata')
}

function Assert-PbixIntakeArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('File', 'Bim', 'Tmdl', 'CsvConnection')][string]$Kind = 'File'
    )
    if ($Kind -eq 'Tmdl') {
        if (-not (Test-Path -LiteralPath $Path -PathType Container) -or @(Get-ChildItem -LiteralPath $Path -Recurse -Filter '*.tmdl' -File -ErrorAction SilentlyContinue).Count -eq 0) {
            Throw-PbixIntakeFailure -BlockerCode 'MODEL_EXPORT_MISSING' -FailureStage 'artifact-validation' -Message 'TMDL export is missing or contains no .tmdl files.' -NextAction 'Treat tool exit zero as failure and preserve the logs.'
        }
        return $true
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -le 0) {
        $code = if ($Kind -in @('Bim', 'File')) { 'MODEL_EXPORT_MISSING' } else { 'DAX_OUTPUT_INVALID' }
        Throw-PbixIntakeFailure -BlockerCode $code -FailureStage 'artifact-validation' -Message "Expected $Kind artifact is missing or empty." -NextAction 'Treat tool exit zero as failure and preserve the logs.'
    }
    if ($Kind -eq 'Bim') {
        try { $null = Read-Utf8Text -Path $Path | ConvertFrom-Json -ErrorAction Stop }
        catch { Throw-PbixIntakeFailure -BlockerCode 'MODEL_EXPORT_INVALID' -FailureStage 'artifact-validation' -Message 'BIM export is not valid JSON.' -NextAction 'Preserve logs and retry only after model readiness is confirmed.' }
    }
    if ($Kind -eq 'CsvConnection') {
        try { $rows = @(Import-Csv -LiteralPath $Path -ErrorAction Stop) } catch { $rows = @() }
        if ($rows.Count -ne 1 -or $null -eq $rows[0].PSObject.Properties['PbixIntakeConnection'] -or [string]$rows[0].PbixIntakeConnection -ne 'OK') {
            Throw-PbixIntakeFailure -BlockerCode 'DAX_OUTPUT_INVALID' -FailureStage 'artifact-validation' -Message 'DAX connection output is not exactly one PbixIntakeConnection=OK row.' -NextAction 'Preserve logs and do not publish the handoff.'
        }
    }
    return $true
}

function Protect-PbixIntakeText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $result = $Text
    $keyPattern = '(?i)(password|pwd|account\s*key|accountkey|sharedaccesssignature|client[_-]?secret|api[_-]?key|access[_-]?token|refresh[_-]?token|bearer[_-]?token|authorization|token)'
    $sensitiveAssignmentPattern = '(?im)(?<p>["'']?' + $keyPattern + '["'']?\s*[:=]\s*["'']?)(?<v>[^"''`;\r\n,}]+)(?<q>["'']?)'
    $result = [regex]::Replace($result, $sensitiveAssignmentPattern, '${p}[REDACTED]${q}')
    $result = [regex]::Replace($result, '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}', 'Bearer [REDACTED]')
    $result = [regex]::Replace($result, '(?i)\b(?:dapi[a-f0-9]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,})\b', '[REDACTED]')
    $result = [regex]::Replace($result, '(?i)(SharedAccessSignature=)[^;\s\"'']+', '$1[REDACTED]')
    return $result
}

function Test-SensitivePropertyName {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $Name -match '(?i)^(password|pwd|accountkey|account_key|sharedaccesssignature|clientsecret|client_secret|apikey|api_key|accesstoken|access_token|refreshtoken|refresh_token|credential|credentials|secret|token)$'
}

function ConvertTo-RedactedCanonicalObject {
    param([AllowNull()][object]$Value, [string]$PropertyName)
    if ($null -eq $Value) { return $null }
    if (-not [string]::IsNullOrWhiteSpace($PropertyName) -and (Test-SensitivePropertyName -Name $PropertyName)) { return '[REDACTED]' }
    if ($Value -is [string]) { return Protect-PbixIntakeText -Text ([string]$Value) }
    if ($Value -is [bool] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [decimal] -or $Value -is [double] -or $Value -is [single] -or $Value -is [datetime]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object { [string]$_ })) { $ordered[[string]$key] = ConvertTo-RedactedCanonicalObject -Value $Value[$key] -PropertyName ([string]$key) }
        return [pscustomobject]$ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $array = @()
        foreach ($entry in $Value) { $array += ,(ConvertTo-RedactedCanonicalObject -Value $entry -PropertyName $null) }
        return [object[]]$array
    }
    if ($Value -is [psobject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty', 'Property') } | Sort-Object Name)) {
            $ordered[$property.Name] = ConvertTo-RedactedCanonicalObject -Value $property.Value -PropertyName $property.Name
        }
        return [pscustomobject]$ordered
    }
    return Protect-PbixIntakeText -Text ([string]$Value)
}

function Get-NamedItems {
    param([AllowNull()][object]$Container, [Parameter(Mandatory = $true)][string]$PropertyName)
    if ($null -eq $Container -or $null -eq $Container.PSObject.Properties[$PropertyName]) { return @() }
    return @($Container.PSObject.Properties[$PropertyName].Value | Sort-Object { if ($null -ne $_.PSObject.Properties['name']) { [string]$_.name } elseif ($null -ne $_.PSObject.Properties['id']) { [string]$_.id } else { '' } })
}

function ConvertTo-PbixIntakeNormalizedModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BimPath,
        [string]$OutputPath
    )
    Assert-PbixIntakeArtifact -Path $BimPath -Kind Bim | Out-Null
    $bim = Read-Utf8Text -Path $BimPath | ConvertFrom-Json
    $model = if ($null -ne $bim.PSObject.Properties['model']) { $bim.model } else { $bim }
    $tables = @(Get-NamedItems -Container $model -PropertyName 'tables')
    $tableIndex = @()
    foreach ($table in $tables) {
        $tableIndex += [pscustomobject][ordered]@{
            name = [string]$table.name
            isHidden = if ($null -ne $table.PSObject.Properties['isHidden']) { [bool]$table.isHidden } else { $false }
            columns = [object[]]@(Get-NamedItems -Container $table -PropertyName 'columns' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
            measures = [object[]]@(Get-NamedItems -Container $table -PropertyName 'measures' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
            hierarchies = [object[]]@(Get-NamedItems -Container $table -PropertyName 'hierarchies' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
            partitions = [object[]]@(Get-NamedItems -Container $table -PropertyName 'partitions' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
            calculationGroup = if ($null -ne $table.PSObject.Properties['calculationGroup']) { ConvertTo-RedactedCanonicalObject -Value $table.calculationGroup -PropertyName 'calculationGroup' } else { $null }
        }
    }
    $normalized = [pscustomobject][ordered]@{
        schemaVersion = 1
        source = 'model.bim'
        database = [pscustomobject][ordered]@{
            name = if ($null -ne $bim.PSObject.Properties['name']) { [string]$bim.name } else { $null }
            id = if ($null -ne $bim.PSObject.Properties['id']) { [string]$bim.id } else { $null }
            compatibilityLevel = if ($null -ne $bim.PSObject.Properties['compatibilityLevel']) { $bim.compatibilityLevel } else { $null }
        }
        counts = [pscustomobject][ordered]@{
            tables = $tables.Count
            columns = @($tables | ForEach-Object { @(Get-NamedItems -Container $_ -PropertyName 'columns') }).Count
            measures = @($tables | ForEach-Object { @(Get-NamedItems -Container $_ -PropertyName 'measures') }).Count
            relationships = @(Get-NamedItems -Container $model -PropertyName 'relationships').Count
            expressions = @(Get-NamedItems -Container $model -PropertyName 'expressions').Count
            roles = @(Get-NamedItems -Container $model -PropertyName 'roles').Count
        }
        tables = [object[]]$tableIndex
        relationships = [object[]]@(Get-NamedItems -Container $model -PropertyName 'relationships' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
        expressions = [object[]]@(Get-NamedItems -Container $model -PropertyName 'expressions' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
        roles = [object[]]@(Get-NamedItems -Container $model -PropertyName 'roles' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
        dataSources = [object[]]@(Get-NamedItems -Container $model -PropertyName 'dataSources' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
        perspectives = [object[]]@(Get-NamedItems -Container $model -PropertyName 'perspectives' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
        cultures = [object[]]@(Get-NamedItems -Container $model -PropertyName 'cultures' | ForEach-Object { ConvertTo-RedactedCanonicalObject -Value $_ -PropertyName $null })
        semanticModel = ConvertTo-RedactedCanonicalObject -Value $model -PropertyName 'model'
    }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { [void](Write-JsonFile -Path $OutputPath -InputObject $normalized -Depth 100) }
    return $normalized
}

function New-GenieHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$NormalizedModel,
        [string]$PbixName = 'selected model',
        [string]$OutputPath
    )
    $safeName = Protect-PbixIntakeText -Text $PbixName
    [object[]]$tables = @()
    [object[]]$relationships = @()
    [object[]]$expressions = @()
    [object[]]$roles = @()
    if ($null -ne $NormalizedModel.PSObject.Properties['tables']) { $tables = [object[]]@($NormalizedModel.tables) }
    if ($null -ne $NormalizedModel.PSObject.Properties['relationships']) { $relationships = [object[]]@($NormalizedModel.relationships) }
    if ($null -ne $NormalizedModel.PSObject.Properties['expressions']) { $expressions = [object[]]@($NormalizedModel.expressions) }
    if ($null -ne $NormalizedModel.PSObject.Properties['roles']) { $roles = [object[]]@($NormalizedModel.roles) }
    $derivedColumns = 0
    $derivedMeasures = 0
    foreach ($table in $tables) {
        if ($null -ne $table.PSObject.Properties['columns']) { $derivedColumns += @($table.columns).Count }
        if ($null -ne $table.PSObject.Properties['measures']) { $derivedMeasures += @($table.measures).Count }
    }
    $countsProperty = $NormalizedModel.PSObject.Properties['counts']
    $suppliedCounts = if ($null -ne $countsProperty) { $countsProperty.Value } else { $null }
    $counts = [pscustomobject][ordered]@{
        tables = if ($null -ne $suppliedCounts -and $null -ne $suppliedCounts.PSObject.Properties['tables']) { [int]$suppliedCounts.tables } else { @($tables).Count }
        columns = if ($null -ne $suppliedCounts -and $null -ne $suppliedCounts.PSObject.Properties['columns']) { [int]$suppliedCounts.columns } else { $derivedColumns }
        measures = if ($null -ne $suppliedCounts -and $null -ne $suppliedCounts.PSObject.Properties['measures']) { [int]$suppliedCounts.measures } else { $derivedMeasures }
        relationships = if ($null -ne $suppliedCounts -and $null -ne $suppliedCounts.PSObject.Properties['relationships']) { [int]$suppliedCounts.relationships } else { @($relationships).Count }
        expressions = if ($null -ne $suppliedCounts -and $null -ne $suppliedCounts.PSObject.Properties['expressions']) { [int]$suppliedCounts.expressions } else { @($expressions).Count }
        roles = if ($null -ne $suppliedCounts -and $null -ne $suppliedCounts.PSObject.Properties['roles']) { [int]$suppliedCounts.roles } else { @($roles).Count }
    }
    [string[]]$tableNames = @()
    $tableNames = [string[]]@($tables | ForEach-Object { if ($null -ne $_.PSObject.Properties['name']) { [string]$_.name } else { [string]$_ } } | Sort-Object)
    $lines = @(
        '# Genie semantic-model handoff',
        '',
        "Source PBIX: $safeName",
        '',
        '## Captured scope',
        '',
        "- Semantic model metadata: captured and redacted for agent use.",
        "- Tables: $($counts.tables); columns: $($counts.columns); measures: $($counts.measures); relationships: $($counts.relationships); shared expressions: $($counts.expressions); roles: $($counts.roles).",
        '- Canonical machine-readable navigation artifact: `normalized/model.redacted.json`.',
        '- Raw BIM and TMDL are restricted internal evidence because connection metadata can be sensitive.',
        '',
        '## Table index',
        ''
    )
    if (@($tableNames).Count -eq 0) { $lines += '- (none)' } else { foreach ($name in $tableNames) { $lines += "- $name" } }
    $lines += @(
        '',
        '## Required user input',
        '',
        'The report layer was not collected. Pages, visuals, page/visual/report filters, slicers, bookmarks, drill settings, interactions, layout, and visual context must be supplied separately by the user.',
        '',
        'This semantic handoff alone does not recreate a complete PBIX.',
        ''
    )
    $markdown = ($lines -join "`n")
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { [void](Write-Utf8NoBom -Path $OutputPath -Text $markdown) }
    return $markdown
}

function New-PbixIntakeManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [string]$OutputPath,
        [string[]]$ExcludeRelativePath = @('manifest.json', 'run.json')
    )
    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]@('\', '/'))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Manifest root does not exist: $root" }
    $exclude = @($ExcludeRelativePath | ForEach-Object { ([string]$_).Replace('\', '/') })
    $entries = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
        if ($exclude -contains $relative) { continue }
        $entries += [pscustomobject][ordered]@{ path = $relative; bytes = [int64]$file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $manifest = [pscustomobject][ordered]@{ schemaVersion = 1; algorithm = 'SHA-256'; files = [object[]]$entries }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $root 'manifest.json' }
    [void](Write-JsonFile -Path $OutputPath -InputObject $manifest -Depth 10)
    return $manifest
}

Export-ModuleMember -Function @(
    'Throw-PbixIntakeFailure', 'Get-PbixIntakeFailureInfo', 'Write-Utf8NoBom', 'Write-JsonFile',
    'Normalize-PbixName', 'Convert-DesktopWindowTitleToPbixName', 'Invoke-DesktopBridgeRequest',
    'Get-PowerBIDesktopTargets', 'Select-PbixTarget', 'Get-ListeningTcpPortsForProcess',
    'Get-LocalDesktopModelContexts', 'Resolve-PbixModelContext', 'Assert-ToolRegistration',
    'Assert-RegisteredTool', 'New-ToolDistributionRecord', 'Assert-ToolDistribution', 'Get-RegisteredTools', 'Invoke-BoundedProcess', 'Get-Te2ExportArguments',
    'Get-DscmdCsvArguments', 'Get-DscmdVpaxArguments', 'Assert-PbixIntakeArtifact',
    'Protect-PbixIntakeText', 'ConvertTo-PbixIntakeNormalizedModel', 'New-GenieHandoff',
    'New-PbixIntakeManifest'
)
