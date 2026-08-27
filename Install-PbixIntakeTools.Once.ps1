[CmdletBinding()]
param(
    [Parameter()]
    [string]$ToolConfigPath,

    [Parameter()]
    [ValidateRange(60, 900)]
    [int]$TimeoutSeconds = 300
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'powershell\PbixIntake.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "PBIX Intake Lab core module is missing: $modulePath"
}
Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop

function Get-PinnedToolPackages {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject][ordered]@{
            kind                    = 'TE2'
            id                      = 'TabularEditor.TabularEditor.2'
            version                 = '2.28.0'
            scope                   = 'user'
            architecture            = 'x86'
            installerType           = 'portable'
            installerUrl            = 'https://github.com/TabularEditor/TabularEditor/releases/download/2.28.0/TabularEditor.Portable.zip'
            installerSha256         = 'BA85F4653C850B06687E6E0B3C8AF3D7C951921EC281DEB5DF615B2CE43D4EF2'
            executableName          = 'TabularEditor.exe'
            executableSha256        = '8DA4E0C153F4E176B4DBA75577E4AB70ADD14667EBA61C984A8FC8B56DD979E4'
            uninstallKeyPattern     = 'TabularEditor.TabularEditor.2_Microsoft.Winget.Source_*'
            relativeExecutablePath  = 'TabularEditor.exe'
            skipDependencies        = $true
        },
        [pscustomobject][ordered]@{
            kind                    = 'DAX'
            id                      = 'DaxStudio.DaxStudio'
            version                 = '3.6.0'
            scope                   = 'user'
            architecture            = 'x64'
            installerType           = 'inno'
            installerUrl            = 'https://github.com/DaxStudio/DaxStudio/releases/download/v3.6.0/DaxStudio_3_6_0_setup.exe'
            installerSha256         = '61B8CEF9743ECCDFB3486ACA5BDD6EF339E20BDD63C552D2EAFB5F19A108944F'
            executableName          = 'dscmd.exe'
            executableSha256        = '81EFA7030D2EF7368D64EF3EB928303676868944E35F95ABF8D2400E66711404'
            uninstallKeyPattern     = '{CE2CEA93-9DD3-4724-8FE3-FCBF0A0915C1}_is1'
            relativeExecutablePath  = 'dscmd.exe'
            skipDependencies        = $false
        }
    )
}

function Get-WinGetShowArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Package)

    return [string[]]@(
        'show',
        '--id', [string]$Package.id,
        '--exact',
        '--version', [string]$Package.version,
        '--source', 'winget',
        '--scope', [string]$Package.scope,
        '--architecture', [string]$Package.architecture,
        '--installer-type', [string]$Package.installerType,
        '--accept-source-agreements',
        '--disable-interactivity'
    )
}

function Get-WinGetInstallArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Package)

    [string[]]$arguments = @(
        'install',
        '--id', [string]$Package.id,
        '--exact',
        '--version', [string]$Package.version,
        '--source', 'winget',
        '--scope', [string]$Package.scope,
        '--architecture', [string]$Package.architecture,
        '--installer-type', [string]$Package.installerType,
        '--silent',
        '--disable-interactivity',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--verbose-logs'
    )
    if ([bool]$Package.skipDependencies) {
        $arguments += '--skip-dependencies'
    }
    return $arguments
}

function Assert-NonElevatedInteractiveUser {
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion -lt [version]'5.1') {
        throw 'PROVISION_SHELL_UNSUPPORTED: PowerShell 5.1 or later is required.'
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'PROVISION_OS_UNSUPPORTED: DAX Studio 3.6.0 requires 64-bit Windows.'
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or $identity.User.Value -eq 'S-1-5-18') {
        throw 'PROVISION_USER_CONTEXT_INVALID: Run as the logged-in user, not SYSTEM.'
    }
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'PROVISION_ELEVATED_SESSION: Close this shell and run from a normal non-elevated user session.'
    }
}

function Get-NetFramework48Release {
    [CmdletBinding()]
    param()

    $baseKey = $null
    $fullKey = $null
    try {
        $view = if ([Environment]::Is64BitOperatingSystem) {
            [Microsoft.Win32.RegistryView]::Registry64
        }
        else {
            [Microsoft.Win32.RegistryView]::Registry32
        }
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        $fullKey = $baseKey.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full')
        if ($null -eq $fullKey) { return $null }
        $release = $fullKey.GetValue('Release', $null)
        if ($null -eq $release) { return $null }
        return [int]$release
    }
    finally {
        if ($null -ne $fullKey) { $fullKey.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
}

function Assert-NetFramework48Runtime {
    [CmdletBinding()]
    param()

    $release = Get-NetFramework48Release
    if ($null -eq $release -or $release -lt 528040) {
        throw "PROVISION_DOTNET_PREREQUISITE_MISSING: Tabular Editor 2.28.0 targets .NET Framework 4.8 (Release >= 528040); found '$release'. Ask IT to provision the runtime."
    }
    return [int]$release
}

function Invoke-WinGetStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WingetPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogDirectory,
        [int[]]$AcceptedExitCode = @(0),
        [ValidateRange(10, 900)][int]$BoundSeconds = 120
    )

    $safeName = [regex]::Replace($Name.ToLowerInvariant(), '[^a-z0-9.-]+', '-')
    Write-Host "WinGet: $Name"
    $result = Invoke-BoundedProcess `
        -FilePath $WingetPath `
        -ArgumentList $Arguments `
        -TimeoutSeconds $BoundSeconds `
        -StdoutPath (Join-Path $LogDirectory "$safeName.stdout.log") `
        -StderrPath (Join-Path $LogDirectory "$safeName.stderr.log") `
        -TimeoutBlockerCode 'WINGET_TIMEOUT'
    if ($AcceptedExitCode -notcontains [int]$result.ExitCode) {
        $combined = (([string]$result.Stdout) + "`n" + ([string]$result.Stderr)).Trim()
        throw "WINGET_STEP_FAILED: '$Name' returned $($result.ExitCode). $combined Logs: $($result.StdoutPath); $($result.StderrPath)"
    }
    return $result
}

function Assert-WinGetCapabilities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WingetPath,
        [Parameter(Mandatory = $true)][string]$LogDirectory
    )

    $result = Invoke-WinGetStep `
        -WingetPath $WingetPath `
        -Name 'install-help' `
        -Arguments @('install', '--help') `
        -LogDirectory $LogDirectory `
        -BoundSeconds 30
    $help = ([string]$result.Stdout) + "`n" + ([string]$result.Stderr)
    foreach ($requiredOption in @(
        '--id', '--exact', '--version', '--source', '--scope', '--architecture',
        '--installer-type', '--silent', '--disable-interactivity',
        '--accept-source-agreements', '--accept-package-agreements',
        '--skip-dependencies', '--verbose-logs'
    )) {
        if ($help.IndexOf($requiredOption, [StringComparison]::Ordinal) -lt 0) {
            throw "WINGET_CAPABILITY_MISSING: This WinGet client does not expose required option '$requiredOption'. Update App Installer through the approved company channel."
        }
    }
}

function Assert-WinGetSourceRefreshResult {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Result)

    $combined = (([string]$Result.Stdout) + "`n" + ([string]$Result.Stderr)).Trim()
    if ([int]$Result.ExitCode -ne 0 -or
        $combined -match '(?im)(^|\b)(failed|cancelled|canceled)(\b|\s*:)' -or
        $combined -match '(?i)\b0x8[0-9a-f]{7}\b' -or
        $combined -notmatch '(?im)^\s*Done\s*$') {
        throw "WINGET_SOURCE_REFRESH_FAILED: The canonical source did not report an unambiguous successful refresh. Output: $combined"
    }
    return $true
}

function Resolve-TrustedWingetPath {
    [CmdletBinding()]
    param()

    $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
        throw "WINGET_MISSING: The App Installer alias does not exist at '$expectedPath'."
    }
    $command = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        throw "WINGET_MISSING: WinGet is not discoverable through the App Installer alias at '$expectedPath'."
    }
    if (-not ([string]$command.Source).Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "WINGET_IDENTITY_INVALID: WinGet must resolve through the App Installer alias at '$expectedPath'."
    }
    $item = Get-Item -LiteralPath $expectedPath -Force -ErrorAction Stop
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw 'WINGET_IDENTITY_INVALID: The expected WinGet app-execution alias is not a reparse point.'
    }
    try {
        $appInstaller = @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop | Where-Object {
            $_.PackageFamilyName -eq 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -and
            -not [string]::IsNullOrWhiteSpace([string]$_.InstallLocation) -and
            [string]$_.InstallLocation -like (Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*')
        })
    }
    catch {
        throw "WINGET_IDENTITY_INVALID: Microsoft Desktop App Installer identity could not be verified: $($_.Exception.Message)"
    }
    if ($appInstaller.Count -ne 1) {
        throw 'WINGET_IDENTITY_INVALID: Exactly one Microsoft Desktop App Installer package was not found.'
    }
    return $expectedPath
}

function Get-TrustedWindowsPowerShellPath {
    [CmdletBinding()]
    param()

    $windowsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $path = [System.IO.Path]::GetFullPath((Join-Path $windowsDirectory 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "PROVISION_SHELL_UNSUPPORTED: Trusted Windows PowerShell was not found at '$path'."
    }
    return $path
}

function Save-ProvisioningState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory = $true)][string]$Path
    )

    Write-JsonFile -Path $Path -InputObject ([pscustomobject]$State) -Depth 30
}

function Get-HkcuUninstallEntries {
    [CmdletBinding()]
    param()

    $entries = @()
    foreach ($path in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $entries += @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)
    }
    return [object[]]$entries
}

function Resolve-PinnedInstalledExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Package,
        [object[]]$UninstallEntries
    )

    if ($null -eq $UninstallEntries) {
        $UninstallEntries = @(Get-HkcuUninstallEntries)
    }
    $matchingEntries = @(
        $UninstallEntries | Where-Object {
            [string]$_.PSChildName -like [string]$Package.uninstallKeyPattern
        }
    )
    [string[]]$candidates = @(
        @(
            foreach ($entry in $matchingEntries) {
                if ([string]::IsNullOrWhiteSpace([string]$entry.InstallLocation)) { continue }
                $candidate = Join-Path ([string]$entry.InstallLocation) ([string]$Package.relativeExecutablePath)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    (Get-Item -LiteralPath $candidate -ErrorAction Stop).FullName
                }
            }
        ) | Sort-Object -Unique
    )
    if ($candidates.Count -ne 1) {
        throw "TOOL_MISSING_AFTER_INSTALL: Expected exactly one user-scoped $($Package.kind) executable from $($Package.id); found $($candidates.Count)."
    }
    return [string]$candidates[0]
}

function Assert-PinnedInstalledExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Package,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $record = Assert-ToolRegistration `
        -Kind ([string]$Package.kind) `
        -Path $Path `
        -ExpectedSha256 ([string]$Package.executableSha256)
    $actual = [regex]::Match([string]$record.productVersion, '\d+(?:\.\d+){2,3}')
    if (-not $actual.Success) {
        throw "TOOL_VERSION_UNSUPPORTED: Could not parse $($Package.kind) product version '$($record.productVersion)'."
    }
    $actualVersion = [version]$actual.Value
    $pinnedVersion = [version]([string]$Package.version)
    if ($actualVersion.Major -ne $pinnedVersion.Major -or
        $actualVersion.Minor -ne $pinnedVersion.Minor -or
        $actualVersion.Build -ne $pinnedVersion.Build) {
        throw "TOOL_VERSION_UNSUPPORTED: Expected $($Package.id) $($Package.version); found '$($record.productVersion)'."
    }
    return $record
}

function Invoke-PbixIntakeToolProvisioning {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [ValidateRange(60, 900)][int]$InstallTimeoutSeconds = 300
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $PSScriptRoot 'config\tools.json'
    }
    elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
        $ConfigPath = Join-Path $PSScriptRoot $ConfigPath
    }
    $configFullPath = [System.IO.Path]::GetFullPath($ConfigPath)
    $configDirectory = Split-Path -Parent $configFullPath
    $runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss.fffffffZ') + '-' + [Guid]::NewGuid().ToString('N')
    $logDirectory = Join-Path (Join-Path $configDirectory 'provisioning-logs') $runId
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

    $resultPath = Join-Path $logDirectory 'result.json'
    $isElevated = $null
    try {
        $evidenceIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $evidencePrincipal = New-Object Security.Principal.WindowsPrincipal($evidenceIdentity)
        $isElevated = [bool]$evidencePrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { }
    $state = [ordered]@{
        schemaVersion = 1
        runId = $runId
        status = 'running'
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
        completedAtUtc = $null
        shell = [ordered]@{
            edition = [string]$PSVersionTable.PSEdition
            version = [string]$PSVersionTable.PSVersion
            processArchitecture = if ([Environment]::Is64BitProcess) { 'x64' } else { 'x86' }
            elevated = $isElevated
        }
        winget = $null
        dotNetFrameworkRelease = $null
        packages = @()
        toolConfigPath = $configFullPath
        error = $null
    }
    Save-ProvisioningState -State $state -Path $resultPath

    try {
        Assert-NonElevatedInteractiveUser
        $wingetPath = Resolve-TrustedWingetPath
        $versionResult = Invoke-WinGetStep -WingetPath $wingetPath -Name 'version' -Arguments @('--version') -LogDirectory $logDirectory -BoundSeconds 30
        $state.winget = [ordered]@{
            path = $wingetPath
            version = ([string]$versionResult.Stdout).Trim()
            sourceName = 'winget'
            sourceArgument = 'https://cdn.winget.microsoft.com/cache'
            sourceIdentifier = 'Microsoft.Winget.Source_8wekyb3d8bbwe'
        }
        Assert-WinGetCapabilities -WingetPath $wingetPath -LogDirectory $logDirectory

        $sourceResult = Invoke-WinGetStep `
            -WingetPath $wingetPath `
            -Name 'source-identity' `
            -Arguments @('source', 'list', '--name', 'winget', '--disable-interactivity') `
            -LogDirectory $logDirectory `
            -BoundSeconds 30
        $sourceText = ([string]$sourceResult.Stdout) + "`n" + ([string]$sourceResult.Stderr)
        foreach ($requiredSourceValue in @('https://cdn.winget.microsoft.com/cache', 'Microsoft.Winget.Source_8wekyb3d8bbwe')) {
            if ($sourceText.IndexOf($requiredSourceValue, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                throw "WINGET_SOURCE_IDENTITY_INVALID: Source 'winget' does not expose expected value '$requiredSourceValue'."
            }
        }
        $refreshResult = Invoke-WinGetStep `
            -WingetPath $wingetPath `
            -Name 'source-refresh' `
            -Arguments @('source', 'update', '--name', 'winget', '--disable-interactivity') `
            -LogDirectory $logDirectory `
            -BoundSeconds 120
        [void](Assert-WinGetSourceRefreshResult -Result $refreshResult)

        $state.dotNetFrameworkRelease = Assert-NetFramework48Runtime
        $packages = @(Get-PinnedToolPackages)
        $packageStates = @()
        foreach ($package in $packages) {
            $packageStates += [pscustomobject][ordered]@{
                kind = [string]$package.kind
                id = [string]$package.id
                packageVersion = [string]$package.version
                scope = [string]$package.scope
                architecture = [string]$package.architecture
                installerType = [string]$package.installerType
                installerUrl = [string]$package.installerUrl
                installerSha256 = [string]$package.installerSha256
                showArguments = [object[]]@(Get-WinGetShowArguments -Package $package)
                installArguments = [object[]]@(Get-WinGetInstallArguments -Package $package)
                status = 'planned'
                installExitCode = $null
                executable = $null
                distributionFileCount = $null
                error = $null
            }
        }
        $state.packages = [object[]]$packageStates
        Save-ProvisioningState -State $state -Path $resultPath

        for ($index = 0; $index -lt $packages.Count; $index++) {
            $package = $packages[$index]
            $packageState = $packageStates[$index]
            $packageState.status = 'checking-manifest'
            Save-ProvisioningState -State $state -Path $resultPath
            try {
                $showResult = Invoke-WinGetStep `
                    -WingetPath $wingetPath `
                    -Name ("show-" + [string]$package.kind) `
                    -Arguments (Get-WinGetShowArguments -Package $package) `
                    -LogDirectory $logDirectory `
                    -BoundSeconds 60
                $showText = ([string]$showResult.Stdout) + "`n" + ([string]$showResult.Stderr)
                foreach ($expectedManifestValue in @([string]$package.installerUrl, [string]$package.installerSha256)) {
                    if ($showText.IndexOf($expectedManifestValue, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                        throw "WINGET_MANIFEST_CHANGED: $($package.id) $($package.version) no longer exposes audited value '$expectedManifestValue'. Stop for review."
                    }
                }
                $packageState.status = 'manifest-verified'
                Save-ProvisioningState -State $state -Path $resultPath
            }
            catch {
                $packageState.status = 'manifest-failed'
                $packageState.error = [string]$_.Exception.Message
                Save-ProvisioningState -State $state -Path $resultPath
                throw
            }
        }

        $pathsByKind = @{}
        for ($index = 0; $index -lt $packages.Count; $index++) {
            $package = $packages[$index]
            $packageState = $packageStates[$index]
            # 0x8A15002B means the exact pinned version is already installed and no update applies.
            # It is accepted only because the executable is independently checked below.
            $packageState.status = 'installing'
            Save-ProvisioningState -State $state -Path $resultPath
            try {
                $installResult = Invoke-WinGetStep `
                    -WingetPath $wingetPath `
                    -Name ("install-" + [string]$package.kind) `
                    -Arguments (Get-WinGetInstallArguments -Package $package) `
                    -LogDirectory $logDirectory `
                    -AcceptedExitCode @(0, -1978335189) `
                    -BoundSeconds $InstallTimeoutSeconds
                $packageState.installExitCode = [int]$installResult.ExitCode
                $packageState.status = 'installed-or-current'
                Save-ProvisioningState -State $state -Path $resultPath

                $path = Resolve-PinnedInstalledExecutable -Package $package
                $toolRecord = Assert-PinnedInstalledExecutable -Package $package -Path $path
                $pathsByKind[[string]$package.kind] = $path
                $packageState.executable = $toolRecord
                $packageState.status = 'executable-validated'
                Save-ProvisioningState -State $state -Path $resultPath
            }
            catch {
                $packageState.status = 'install-or-validation-failed'
                $packageState.error = [string]$_.Exception.Message
                Save-ProvisioningState -State $state -Path $resultPath
                throw
            }
        }

        $windowsPowerShell = Get-TrustedWindowsPowerShellPath
        $initializerPath = Join-Path $PSScriptRoot 'Initialize-PbixIntakeLab.ps1'
        [string[]]$initializerArguments = @(
            '-NoProfile',
            '-File', $initializerPath,
            '-Te2Path', [string]$pathsByKind['TE2'],
            '-DscmdPath', [string]$pathsByKind['DAX'],
            '-ToolConfigPath', $configFullPath,
            '-ProvisioningLogDirectory', $logDirectory
        )
        $initializerResult = Invoke-BoundedProcess `
            -FilePath $windowsPowerShell `
            -ArgumentList $initializerArguments `
            -TimeoutSeconds 120 `
            -StdoutPath (Join-Path $logDirectory 'initializer.stdout.log') `
            -StderrPath (Join-Path $logDirectory 'initializer.stderr.log') `
            -TimeoutBlockerCode 'TOOL_REGISTRATION_TIMEOUT'
        if ([int]$initializerResult.ExitCode -ne 0) {
            throw "TOOL_REGISTRATION_FAILED: Initializer returned $($initializerResult.ExitCode). Logs: $($initializerResult.StdoutPath); $($initializerResult.StderrPath)"
        }

        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $registeredConfig = [System.IO.File]::ReadAllText($configFullPath, $utf8) | ConvertFrom-Json -ErrorAction Stop
        foreach ($packageState in $packageStates) {
            $configRecord = if ($packageState.kind -eq 'TE2') { $registeredConfig.tools.te2 } else { $registeredConfig.tools.dax }
            $packageState.distributionFileCount = @($configRecord.distributionFiles).Count
            $packageState.status = 'registered'
        }

        $state.status = 'succeeded'
        $state.completedAtUtc = [DateTime]::UtcNow.ToString('o')
        Save-ProvisioningState -State $state -Path $resultPath

        Write-Host ''
        Write-Host "PBIX Intake Lab provisioning succeeded: $configFullPath" -ForegroundColor Green
        Write-Host "Evidence: $resultPath"
        Write-Host 'All package selections were exact, user-scoped, and launched from a non-elevated shell. No machine-scope or elevation fallback exists.'
        return [pscustomobject]$state
    }
    catch {
        $state.status = 'failed'
        $state.completedAtUtc = [DateTime]::UtcNow.ToString('o')
        $state.error = [string]$_.Exception.Message
        try { Save-ProvisioningState -State $state -Path $resultPath } catch { }
        throw
    }
}

# Dot-sourcing loads the argument builders for adversarial tests without provisioning.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-PbixIntakeToolProvisioning -ConfigPath $ToolConfigPath -InstallTimeoutSeconds $TimeoutSeconds | Out-Null
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
