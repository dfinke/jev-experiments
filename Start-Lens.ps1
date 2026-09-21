#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Path = '.',
    [switch]$Offline,
    [string]$InitialQuery = '',
    [switch]$Sample,
    # Developer smoke check: render the actual WPF window to a PNG, then close.
    [string]$VerifyUiTo
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows) { throw 'Jev Lens requires Windows and PowerShell 7.2 or newer.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with: pwsh -STA -File .\Start-Lens.ps1' }
. "$PSScriptRoot\Lens.Core.ps1"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$isSample = $Sample.IsPresent
if ($isSample) { $Path = Join-Path $PSScriptRoot 'SampleStuff'; Initialize-LensSample $Path }
$script:root = (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName
$script:index = @(Get-LensCandidates $script:root)
if ($null -eq $script:index) { $script:index = [object[]]@() }
$script:online = !$Offline -and ![string]::IsNullOrWhiteSpace($env:TYPESAFE_API_KEY)
$script:client = [Net.Http.HttpClient]::new()
$script:client.Timeout = [timespan]::FromSeconds(8)
if ($script:online) { $script:client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $env:TYPESAFE_API_KEY.Trim()) }
$script:pending = [Collections.Generic.List[object]]::new()
$script:latencies = [Collections.Generic.List[double]]::new()
$script:revision = 0; $script:sentRevision = -1; $script:calls = 0; $script:stale = 0
$script:shortlist = @(); $script:ranked = @(); $script:judgment = $null
$script:changedAt = [datetime]::UtcNow; $script:pausedUntil = [datetime]::MinValue

$reader = [Xml.XmlReader]::Create("$PSScriptRoot\Lens.xaml")
try { $script:window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
$script:ui = @{}
foreach ($name in @('Mode', 'SourceLabel', 'Query', 'Refresh', 'Example1', 'Example2', 'Example3', 'Example4', 'Example5', 'LocalRows', 'Working', 'TopTitle', 'Decision', 'Reveal', 'TargetStat', 'KindStat', 'ClearStat', 'RankedRows', 'Status', 'Metrics')) { $script:ui[$name] = $window.FindName($name) }
$ui.Mode.Text = if ($online) { 'LIVE JEV' } else { 'LOCAL ONLY' }
$ui.SourceLabel.Text = if ($isSample) { "SAMPLE STUFF / $($index.Count) real files" } else { "$([IO.Path]::GetFileName($root)) / $($index.Count) files indexed" }
$ui.SourceLabel.ToolTip = "$root`nTop-level scan, capped at 200 files. Refresh to rescan."

function Update-LensView {
    $script:ranked = @(Get-LensRanking $script:shortlist $script:judgment)
    if ($null -eq $script:ranked) { $script:ranked = [object[]]@() }
    $ui.LocalRows.ItemsSource = @($script:shortlist | ForEach-Object {
            [pscustomobject]@{ Title = $_.Candidate.Title; Detail = $_.Candidate.Detail; LocalLabel = ('{0:0.00}' -f $_.Local) }
        })
    $position = 0
    $ui.RankedRows.ItemsSource = @($script:ranked | ForEach-Object {
            $position++
            $label = if ($null -eq $_.Probability) { '—' } else { '{0:0.0}%' -f ($_.Probability * 100) }
            $breakdown = if ($null -eq $script:judgment) { 'Local order · awaiting typed judgments' } else { 'rank {0:0.000} = .65×{1:0.00} + .20×({2:0.00}×{3:0.00}) + .15×{3:0.00}' -f $_.Score, $_.Probability, $_.KindProbability, $_.Local }
            [pscustomobject]@{ Position = ('{0:00}' -f $position); Title = $_.Candidate.Title; Breakdown = $breakdown; ProbabilityLabel = $label; ProbabilityValue = ([double]$_.Probability * 100) }
        })
    $ui.Reveal.IsEnabled = $false
    if (!$script:shortlist.Count) {
        $ui.TopTitle.Text = if (!$script:index.Count) { 'This folder has no files.' } else { 'Start with a little intent.' }
    }
    elseif ($null -eq $script:judgment) { $ui.TopTitle.Text = 'Local matches, ready for Jev.' }
    if ($null -eq $script:judgment) {
        $ui.TargetStat.Text = 'TARGET  —'; $ui.KindStat.Text = 'KIND  —'; $ui.ClearStat.Text = 'CLEAR  —'
        $ui.Decision.Text = 'Three typed questions. One round trip.'
    }
    else {
        $top = $script:ranked[0]
        $noMatch = $script:judgment.None -ge $top.Probability
        $ui.TopTitle.Text = if ($noMatch) { 'No convincing match.' } else { $top.Candidate.Title }
        $ui.TargetStat.Text = if ($noMatch) { 'NONE  {0:0}%' -f ($script:judgment.None * 100) } else { 'TARGET  {0:0}%' -f ($top.Probability * 100) }
        $ui.KindStat.Text = "KIND  $($script:judgment.KindChoice.ToUpperInvariant())"
        $ui.ClearStat.Text = 'CLEAR  {0:0}%' -f ($script:judgment.Clear * 100)
        $ui.Decision.Text = if ($noMatch) { 'Try a different description. No action selected.' } elseif ($script:judgment.Clear -lt .6) { 'A tentative lead. Compare the alternatives below.' } else { 'A clear lead. You decide what happens next.' }
        $ui.Reveal.IsEnabled = !$noMatch
    }
}

function Set-LensQuery {
    $script:revision++
    $script:changedAt = [datetime]::UtcNow
    $script:judgment = $null
    $query = $ui.Query.Text.Trim()
    $script:shortlist = if ($query) { @(Get-LensShortlist $script:index $query) } else { [object[]]@() }
    # PowerShell unwraps an empty array to $null during assignment. Keep an
    # actual empty collection so strict mode can safely use .Count below.
    if ($null -eq $script:shortlist) { $script:shortlist = [object[]]@() }
    $ui.Working.Text = if ($script:online -and $query -and $script:shortlist.Count) { 'JUDGING…' } else { 'LOCAL' }
    $ui.Status.Text = if (!$script:online) { 'Local ranking only. Set TYPESAFE_API_KEY and restart for live judgments.' } elseif (!$query) { 'Type a description or choose an example.' } elseif (!$script:shortlist.Count) { 'No candidates to send. Choose a folder with files.' } else { 'Matching intent against file metadata…' }
    Update-LensView
}

$ui.Query.Add_TextChanged({ Set-LensQuery })
foreach ($name in @('Example1', 'Example2', 'Example3', 'Example4', 'Example5')) {
    $ui[$name].Add_Click({ param($sender, $eventArgs) $ui.Query.Text = [string]$sender.Content; [void]$ui.Query.Focus(); $ui.Query.CaretIndex = $ui.Query.Text.Length })
}
$ui.Refresh.Add_Click({
        try {
            $script:index = @(Get-LensCandidates $script:root)
            if ($null -eq $script:index) { $script:index = [object[]]@() }
            $ui.SourceLabel.Text = if ($isSample) { "SAMPLE STUFF / $($index.Count) real files" } else { "$([IO.Path]::GetFileName($root)) / $($index.Count) files indexed" }
            Set-LensQuery
        }
        catch { $ui.Status.Text = 'Could not refresh this folder. Check that it still exists and is readable.' }
    })
$ui.Reveal.Add_Click({
        if (!$ui.Reveal.IsEnabled -or !$script:ranked.Count -or $null -eq $script:judgment) { return }
        $file = $script:ranked[0].Candidate.Path
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            # Only a known, locally collected path is used. Never execute model output.
            # Windows chooses the user's configured default application for the file type.
            Start-Process -FilePath $file
        }
        else { $ui.Status.Text = 'That file moved. Refresh the folder.' }
    })

# HttpClient tasks run off the UI thread. The dispatcher only polls completed tasks.
# At most two in flight; a 90 ms pause coalesces bursts, and only the exact current
# revision (including its candidate snapshot) may update the UI.
$script:timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [timespan]::FromMilliseconds(25)
$timer.Add_Tick({
        foreach ($entry in @($script:pending.ToArray())) {
            if (!$entry.Task.IsCompleted) { continue }
            [void]$script:pending.Remove($entry)
            $entry.Watch.Stop()
            $response = $null
            try {
                $response = $entry.Task.GetAwaiter().GetResult()
                if (!$response.IsSuccessStatusCode) {
                    $code = [int]$response.StatusCode
                    if ($code -eq 429) { $script:pausedUntil = [datetime]::UtcNow.AddSeconds(10) }
                    throw "HTTP $code"
                }
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -AsHashtable
                $answer = ConvertFrom-LensAnswer $body $entry.Shortlist
                $script:latencies.Add($entry.Watch.Elapsed.TotalMilliseconds)
                $sorted = @($script:latencies | Sort-Object)
                $p50 = $sorted[[math]::Floor(($sorted.Count - 1) * .5)]
                $p95 = $sorted[[math]::Ceiling(($sorted.Count - 1) * .95)]
                $ui.Metrics.Text = 'ROUND TRIP {0:0}ms   p50 {1:0}ms   CALLS {2}' -f $entry.Watch.Elapsed.TotalMilliseconds, $p50, $script:calls
                $ui.Metrics.ToolTip = 'p95 {0:0}ms · valid answers {1} · stale {2} · UI sampling includes up to ~25ms polling delay. Cold TLS may be slower.' -f $p95, $sorted.Count, $script:stale
                if (!(Test-LensFresh $entry.Revision $script:revision)) { $script:stale++; continue }
                $script:judgment = $answer
                Update-LensView
                $ui.Working.Text = 'DECIDED'
                $ui.Status.Text = "$($answer.Model) · 2 choices + 1 probability · $($entry.Shortlist.Count) candidates"
            }
            catch {
                if (Test-LensFresh $entry.Revision $script:revision) {
                    $script:judgment = $null
                    Update-LensView
                    $ui.Working.Text = 'LOCAL FALLBACK'
                    $message = if ($_.Exception.Message -match 'HTTP (\d{3})') { "Jev returned HTTP $($Matches[1])." } else { 'Jev timed out or returned an unusable answer.' }
                    $ui.Status.Text = "$message Local ranking remains available; edit the query to retry."
                }
            }
            finally { if ($null -ne $response) { $response.Dispose() }; $entry.Content.Dispose() }
        }
        if (!$script:online -or $script:pending.Count -ge 2 -or $script:sentRevision -eq $script:revision -or !$script:shortlist.Count -or !$ui.Query.Text.Trim()) { return }
        if (([datetime]::UtcNow - $script:changedAt).TotalMilliseconds -lt 90 -or [datetime]::UtcNow -lt $script:pausedUntil) { return }
        $script:sentRevision = $script:revision
        $snapshot = @($script:shortlist)
        $request = New-LensRequest $snapshot $ui.Query.Text.Trim() | ConvertTo-Json -Depth 12 -Compress
        $content = [Net.Http.StringContent]::new($request, [Text.Encoding]::UTF8, 'application/json')
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $task = $script:client.PostAsync('https://api.typesafe.ai/v1/systemone', $content)
        $script:calls++
        $script:pending.Add(@{ Task = $task; Watch = $watch; Revision = $script:revision; Shortlist = $snapshot; Content = $content })
    })
$window.Add_Closed({ $script:timer.Stop(); $script:client.CancelPendingRequests(); $script:client.Dispose() })
$window.Add_ContentRendered({ [void]$ui.Query.Focus() })
$ui.Query.Text = $InitialQuery
if ($VerifyUiTo) {
    $script:verifyStarted = [datetime]::UtcNow
    $script:verifyTimer = [Windows.Threading.DispatcherTimer]::new()
    $verifyTimer.Interval = [timespan]::FromMilliseconds(300)
    $verifyTimer.Add_Tick({
            if ($script:online -and $null -eq $script:judgment -and ([datetime]::UtcNow - $script:verifyStarted).TotalSeconds -lt 15) { return }
            $script:verifyTimer.Stop()
            $window.UpdateLayout()
            $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth, [int]$window.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($window)
            $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream = [IO.File]::Create($VerifyUiTo)
            try { $encoder.Save($stream) } finally { $stream.Dispose() }
            $script:verificationResult = [pscustomobject]@{ Online = $script:online; AnswerApplied = ($null -ne $script:judgment); Top = $ui.TopTitle.Text; Status = $ui.Status.Text; Metrics = $ui.Metrics.Text; Rows = $ui.RankedRows.Items.Count; RevealEnabled = $ui.Reveal.IsEnabled }
            $window.Close()
        })
    $verifyTimer.Start()
}
$timer.Start()
try { [void]$window.ShowDialog() } finally { $timer.Stop(); $client.Dispose() }
if ($VerifyUiTo) { $script:verificationResult | ConvertTo-Json -Compress }
