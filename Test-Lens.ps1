#requires -Version 7.2
[CmdletBinding()]
param([switch]$Live)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Lens.Core.ps1"
function Assert($Condition, [string]$Message) { if (!$Condition) { throw "FAIL: $Message" }; Write-Output "PASS: $Message" }
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert $rejected $Message
}
Initialize-LensSample "$PSScriptRoot\SampleStuff"
$index = @(Get-LensCandidates "$PSScriptRoot\SampleStuff")
$short = @(Get-LensShortlist $index 'visual material')
$request = New-LensRequest $short 'visual material'
$wire = $request | ConvertTo-Json -Depth 12
Assert ($short.Count -eq 12) 'A bounded sample snapshot contains 12 candidates'
Assert ($wire -notmatch 'D:\\|"Path"|retentionDays') 'Wire state excludes absolute paths and file contents'
Assert ($request.questions.Count -eq 3) 'Three typed questions share one request'
Assert (@(Get-LensShortlist @() 'anything').Count -eq 0) 'Empty folders yield an empty shortlist'
$single = @(Get-LensShortlist @($index[0]) 'anything')
Assert ($single.Count -eq 1) 'Single-file folders keep array shape'
$contentHits = @(Get-LensShortlist $index 'retentionDays')
Assert (($contentHits[0].Candidate.Title -eq 'Backup-config.json') -and ($contentHits[0].Candidate.ContentMatchCount -eq 1)) 'Bounded local content search finds terms absent from filenames'
$contentWire = New-LensRequest $contentHits 'retentionDays' | ConvertTo-Json -Depth 12
Assert (($contentWire -match 'content_match_terms') -and ($contentWire -notmatch 'sample\":true')) 'Jev receives a content-match signal without raw file contents'

$hero = $index | Where-Object Title -eq 'Launch-hero.svg'
$probabilities = @{}
foreach ($row in $short) { $probabilities[$row.Candidate.Id] = 0.0 }
$probabilities[$hero.Id] = 1.0; $probabilities.none = 0.0
$response = @{
    model='test-fixture'
    answers=@{
        target=@{type='choice';choice=$hero.Id;probabilities=$probabilities}
        kind=@{type='choice';choice='image';probabilities=@{document=0.0;image=1.0;data=0.0;log=0.0;code=0.0;other=0.0;unclear=0.0}}
        clear=@{type='noul';noul=0.8}
    }
}
$judgment = ConvertFrom-LensAnswer $response $short
$ranked = @(Get-LensRanking $short $judgment)
Assert ($ranked[0].Candidate.Id -eq $hero.Id) 'Validated semantic evidence promotes the visual asset'
$sameKindRows = @(
    [pscustomobject]@{ Candidate = [pscustomobject]@{ Id = 'direct'; Title = 'direct.go'; Kind = 'code' }; Local = 0.32 }
    [pscustomobject]@{ Candidate = [pscustomobject]@{ Id = 'unrelated'; Title = 'unrelated.psm1'; Kind = 'code' }; Local = 0.11 }
)
$sameKindJudgment = @{ Target = @{ direct = 0.08; unrelated = 0.14 }; Kind = @{ code = 0.99 }; None = 0.0 }
Assert ((Get-LensRanking $sameKindRows $sameKindJudgment)[0].Candidate.Id -eq 'direct') 'Local relevance gates the shared kind bonus'
$response.answers.target.probabilities[$hero.Id] = [double]::NaN
Assert-Rejected { ConvertFrom-LensAnswer $response $short } 'NaN cannot enter ranking'
$response.answers.target.probabilities[$hero.Id] = 1.1
Assert-Rejected { ConvertFrom-LensAnswer $response $short } 'Out-of-range probabilities are rejected'
$response.answers.target.probabilities[$hero.Id] = 1.0
$response.answers.target.probabilities['foreign-id'] = 0.0
Assert-Rejected { ConvertFrom-LensAnswer $response $short } 'Foreign candidate IDs cannot be applied to a snapshot'
$response.answers.target.probabilities.Remove('foreign-id')
$response.answers.Remove('clear')
Assert-Rejected { ConvertFrom-LensAnswer $response $short } 'Incomplete responses trigger fallback'
Assert (!(Test-LensFresh 1 3) -and !(Test-LensFresh 2 3) -and (Test-LensFresh 3 3)) 'Only the current query and snapshot can accept a response'

if ($Live) {
    if ([string]::IsNullOrWhiteSpace($env:TYPESAFE_API_KEY)) { throw 'Live check requires TYPESAFE_API_KEY.' }
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [timespan]::FromSeconds(12)
    $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $env:TYPESAFE_API_KEY.Trim())
    try {
        foreach ($case in @(
            @('The latest proposal','Atlas-proposal-approved.md'),
            @('Artwork for the announcement','Launch-hero.svg'),
            @('Logs for troubleshooting','Checkout-errors.log'),
            @('What did we earn this month?','September-revenue.csv'),
            @('A recipe for banana bread','none')
        )) {
            $rows = @(Get-LensShortlist $index $case[0])
            $json = New-LensRequest $rows $case[0] | ConvertTo-Json -Depth 12
            $content = [Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, 'application/json')
            $http = $null
            try {
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $http = $client.PostAsync('https://api.typesafe.ai/v1/systemone', $content).GetAwaiter().GetResult()
                [void]$http.EnsureSuccessStatusCode()
                $answer = $http.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -AsHashtable
                $watch.Stop()
                $parsed = ConvertFrom-LensAnswer $answer $rows
                $hits = @(Get-LensRanking $rows $parsed)
                $selected = if ($parsed.None -ge $hits[0].Probability) { 'none' } else { $hits[0].Candidate.Title }
                Assert ($selected -eq $case[1]) "Live: $($case[0]) -> $selected ($($watch.ElapsedMilliseconds) ms)"
            } finally { if ($null -ne $http) { $http.Dispose() }; $content.Dispose() }
        }
    } finally { $client.Dispose() }
}
