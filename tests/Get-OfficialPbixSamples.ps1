[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'RevenueOpportunities',
        'AdventureWorksSales',
        'FuzzyMatchingLegacy',
        'SalesReturnsFeatureHeavy'
    )]
    [string[]]$SampleId = @('RevenueOpportunities'),

    [string]$DestinationRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = Join-Path $PSScriptRoot 'downloads'
}

# These are immutable files in Microsoft's MIT-licensed sample repository. Keep
# both the commit and each byte-level identity pinned: a successful HTTP request
# is not evidence that the expected PBIX was downloaded.
$repositoryUrl = 'https://github.com/microsoft/powerbi-desktop-samples'
$pinnedCommit = '2b6de5e08496edbb543f059cc171f35b47322899'
$licenseUrl = "https://raw.githubusercontent.com/microsoft/powerbi-desktop-samples/$pinnedCommit/LICENSE"

$catalog = @{
    RevenueOpportunities = [ordered]@{
        id = 'RevenueOpportunities'
        fileName = 'Revenue Opportunities.pbix'
        repositoryPath = '2026 Power BI Samples Revamp/Revenue Opportunities.pbix'
        sourceUrl = "https://raw.githubusercontent.com/microsoft/powerbi-desktop-samples/$pinnedCommit/2026%20Power%20BI%20Samples%20Revamp/Revenue%20Opportunities.pbix"
        expectedBytes = [int64]245930
        expectedSha256 = '3C95C4FB5A261E9D13A7152A2E14B18EA9E9EFAC0105DBD9ED46BA0137489C27'
        purpose = 'Small current sample for the fastest live smoke test.'
    }
    AdventureWorksSales = [ordered]@{
        id = 'AdventureWorksSales'
        fileName = 'AdventureWorks Sales.pbix'
        repositoryPath = '2026 Power BI Samples Revamp/AdventureWorks Sales.pbix'
        sourceUrl = "https://raw.githubusercontent.com/microsoft/powerbi-desktop-samples/$pinnedCommit/2026%20Power%20BI%20Samples%20Revamp/AdventureWorks%20Sales.pbix"
        expectedBytes = [int64]8390782
        expectedSha256 = '76C89B64CD1C5A9514B43CC5EA356EFC82F8E92F9A96B49F6679D9CCD57FC4F5'
        purpose = 'Richer current semantic model for broader extraction coverage.'
    }
    FuzzyMatchingLegacy = [ordered]@{
        id = 'FuzzyMatchingLegacy'
        fileName = '2018SU10 Fuzzy Matching Demo - October.pbix'
        repositoryPath = 'Monthly Desktop Blog Samples/2018/2018SU10 Fuzzy Matching Demo - October.pbix'
        sourceUrl = "https://raw.githubusercontent.com/microsoft/powerbi-desktop-samples/$pinnedCommit/Monthly%20Desktop%20Blog%20Samples/2018/2018SU10%20Fuzzy%20Matching%20Demo%20-%20October.pbix"
        expectedBytes = [int64]45177
        expectedSha256 = 'B04EF67CE8B113A9199F6C849667FF390DF95B0E6C8A97F5017D2C1F4078AF4D'
        purpose = 'Small legacy sample for compatibility and error-path testing.'
    }
    SalesReturnsFeatureHeavy = [ordered]@{
        id = 'SalesReturnsFeatureHeavy'
        fileName = 'Sales & Returns Sample v201912.pbix'
        repositoryPath = 'Sample Reports/Sales & Returns Sample v201912.pbix'
        sourceUrl = "https://raw.githubusercontent.com/microsoft/powerbi-desktop-samples/$pinnedCommit/Sample%20Reports/Sales%20%26%20Returns%20Sample%20v201912.pbix"
        expectedBytes = [int64]6530381
        expectedSha256 = 'C0A51FBAE6C9E3C3CF0FF0564CC3408DAD614449B5B27EC3E47FBAEA4BA7F04B'
        purpose = 'Feature-heavy report for optional future report-layer tests.'
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-VerifiedFileIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int64]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Downloaded PBIX is missing: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($item.Length -ne $ExpectedBytes) {
        throw "Size verification failed for '$($item.Name)': expected $ExpectedBytes bytes, got $($item.Length)."
    }
    if ($actualHash -ne $ExpectedSha256.ToUpperInvariant()) {
        throw "SHA-256 verification failed for '$($item.Name)': expected $ExpectedSha256, got $actualHash."
    }

    return [ordered]@{
        bytes = [int64]$item.Length
        sha256 = $actualHash
    }
}

if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $DestinationRoot -Force
}
$resolvedDestinationRoot = (Resolve-Path -LiteralPath $DestinationRoot).Path

# Windows PowerShell 5.1 can otherwise negotiate an obsolete TLS version on
# older hosts. This affects only the explicit download operation in this script.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$records = New-Object System.Collections.Generic.List[object]
foreach ($id in ($SampleId | Select-Object -Unique)) {
    $sample = $catalog[$id]
    $destinationPath = Join-Path $resolvedDestinationRoot $sample.fileName
    $disposition = 'already-present'

    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        try {
            $identity = Get-VerifiedFileIdentity `
                -Path $destinationPath `
                -ExpectedBytes $sample.expectedBytes `
                -ExpectedSha256 $sample.expectedSha256
        }
        catch {
            throw "Refusing to overwrite an existing unverified file at '$destinationPath'. $($_.Exception.Message)"
        }
    }
    else {
        $temporaryPath = Join-Path $resolvedDestinationRoot ('.{0}.{1}.download' -f $sample.fileName, [Guid]::NewGuid().ToString('N'))
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $sample.sourceUrl -OutFile $temporaryPath
            $identity = Get-VerifiedFileIdentity `
                -Path $temporaryPath `
                -ExpectedBytes $sample.expectedBytes `
                -ExpectedSha256 $sample.expectedSha256
            Move-Item -LiteralPath $temporaryPath -Destination $destinationPath
            $disposition = 'downloaded'
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }

    $records.Add([pscustomobject][ordered]@{
        id = $sample.id
        fileName = $sample.fileName
        localPath = $destinationPath
        disposition = $disposition
        bytes = $identity.bytes
        sha256 = $identity.sha256
        sourceUrl = $sample.sourceUrl
        repositoryPath = $sample.repositoryPath
        repository = $repositoryUrl
        pinnedCommit = $pinnedCommit
        license = 'MIT'
        licenseUrl = $licenseUrl
        purpose = $sample.purpose
    })
}

$requestedDisposition = @{}
foreach ($record in [object[]]$records.ToArray()) {
    $requestedDisposition[[string]$record.id] = [string]$record.disposition
}

# Rebuild provenance from bytes on disk on every invocation. Do not merge or
# trust an older provenance.json: it may describe a file that was changed after
# the earlier verification. Known samples that are present but fail verification
# stop the operation even when they were not requested this time.
$allVerifiedRecords = @()
foreach ($catalogId in @($catalog.Keys | Sort-Object)) {
    $sample = $catalog[$catalogId]
    $localPath = Join-Path $resolvedDestinationRoot $sample.fileName
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        continue
    }

    $identity = Get-VerifiedFileIdentity `
        -Path $localPath `
        -ExpectedBytes $sample.expectedBytes `
        -ExpectedSha256 $sample.expectedSha256
    $disposition = if ($requestedDisposition.ContainsKey($catalogId)) {
        $requestedDisposition[$catalogId]
    }
    else {
        'verified-existing'
    }

    $allVerifiedRecords += [pscustomobject][ordered]@{
        id = $sample.id
        fileName = $sample.fileName
        localPath = $localPath
        disposition = $disposition
        bytes = $identity.bytes
        sha256 = $identity.sha256
        sourceUrl = $sample.sourceUrl
        repositoryPath = $sample.repositoryPath
        repository = $repositoryUrl
        pinnedCommit = $pinnedCommit
        license = 'MIT'
        licenseUrl = $licenseUrl
        purpose = $sample.purpose
    }
}

$provenance = [ordered]@{
    schemaVersion = 1
    policy = 'Explicit pinned Microsoft samples only; samples remain under tests/downloads and are never bundled.'
    repository = $repositoryUrl
    pinnedCommit = $pinnedCommit
    license = 'MIT'
    licenseUrl = $licenseUrl
    requestedSamples = [string[]]@($SampleId | Select-Object -Unique)
    samples = [object[]]$allVerifiedRecords
}
$provenancePath = Join-Path $resolvedDestinationRoot 'provenance.json'
Write-Utf8NoBom -Path $provenancePath -Text (($provenance | ConvertTo-Json -Depth 8) + "`n")

$records | Format-Table id, disposition, bytes, sha256, localPath -AutoSize
Write-Host "Verified provenance: $provenancePath"
