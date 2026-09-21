#requires -Version 7.2
[CmdletBinding()]
param(
    [switch]$Offline,
    [string]$InitialQuestion = 'How well does the answer satisfy the request?',
    [string]$InitialAnswer = 'The export works in Chrome but fails in Safari. I explained the workaround and included the browser version.',
    [string]$VerifyUiTo
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows) { throw 'Jev Eval Lab requires Windows and PowerShell 7.2 or newer.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with: pwsh -STA -File .\Start-EvalLab.ps1' }
. "$PSScriptRoot\EvalLab.Core.ps1"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$script:online = !$Offline -and ![string]::IsNullOrWhiteSpace($env:TYPESAFE_API_KEY)
$script:client = [Net.Http.HttpClient]::new(); $script:client.Timeout = [timespan]::FromSeconds(12)
if ($script:online) { $script:client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $env:TYPESAFE_API_KEY.Trim()) }
$script:calls = 0; $script:latencies = [Collections.Generic.List[double]]::new(); $script:pending = [Collections.Generic.List[object]]::new()
$reader = [Xml.XmlReader]::Create("$PSScriptRoot\EvalLab.xaml")
try { $script:window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
$script:ui = @{}
foreach ($name in @('Mode','ModelLabel','ExamplePicker','Question','Answer','Level0','Level1','Level2','Level3','Evaluate','Working','ScoreLabel','ScoreSub','ConfidenceLabel','LatencyLabel','TopLevelLabel','ScoreRangeLabel','CallLabel','Gauges','Status','Footer')) { $script:ui[$name] = $window.FindName($name) }
$ui.Mode.Text = if ($script:online) { 'LIVE JEV' } else { 'LOCAL ONLY' }
$ui.Question.Text = $InitialQuestion; $ui.Answer.Text = $InitialAnswer
$ui.Level0.Text = 'Does not address the request or is unusable'
$ui.Level1.Text = 'Partially addresses the request; major gaps remain'
$ui.Level2.Text = 'Mostly addresses the request; minor gaps remain'
$ui.Level3.Text = 'Fully addresses the request with clear, useful detail'
$ui.ScoreRangeLabel.Text = 'RANGE  0–3'

$script:examples = @()
$examplesPath = Join-Path $PSScriptRoot 'EvalExamples.json'
if (Test-Path -LiteralPath $examplesPath) {
    try {
        $script:examples = @(Get-Content -Raw -LiteralPath $examplesPath | ConvertFrom-Json)
        $ui.ExamplePicker.ItemsSource = @($script:examples | ForEach-Object { [string]$_.name })
    } catch {
        $ui.Status.Text = "Examples could not be loaded: $($_.Exception.Message)"
    }
}

function Set-ExampleFields {
    param([int]$ExampleIndex)
    if ($ExampleIndex -lt 0 -or $ExampleIndex -ge $script:examples.Count) { return }
    $Example = $script:examples[$ExampleIndex]
    $ui.Question.Text = [string]$Example.question
    $ui.Answer.Text = [string]$Example.answer
    $rubric = @($Example.rubric)
    for ($i = 0; $i -lt 4; $i++) { $ui["Level$i"].Text = [string]$rubric[$i] }
    Reset-Result
    $ui.Status.Text = "Loaded example: $($Example.name). Press Enter to evaluate it."
}

function Get-CurrentRubric {
    @($ui.Level0.Text.Trim(), $ui.Level1.Text.Trim(), $ui.Level2.Text.Trim(), $ui.Level3.Text.Trim())
}

function Reset-Result {
    $ui.ScoreLabel.Text = '—'; $ui.ScoreSub.Text = 'Enter an answer and press Evaluate.'; $ui.ConfidenceLabel.Text = 'CONFIDENCE  —'; $ui.LatencyLabel.Text = 'ROUND TRIP  —'; $ui.TopLevelLabel.Text = 'TOP LEVEL  —'; $ui.Gauges.ItemsSource = @(); $ui.Status.Text = if ($script:online) { 'Ready for a typed judgment.' } else { 'Local-only mode. Set TYPESAFE_API_KEY for live Jev scoring.' }
}

$ui.ExamplePicker.Add_SelectionChanged({ Set-ExampleFields $ui.ExamplePicker.SelectedIndex })

function Show-Judgment {
    param($Judgment, [double]$LatencyMs)
    $bars = @(Get-EvalBars $Judgment)
    $top = $bars | Sort-Object Probability -Descending | Select-Object -First 1
    $ui.ScoreLabel.Text = '{0:0.00} / {1}' -f $Judgment.Score, ($Judgment.Rubric.Count - 1)
    $ui.ScoreSub.Text = 'Probability-weighted position on your rubric'
    $ui.ConfidenceLabel.Text = 'CONFIDENCE  {0:0}%' -f ($Judgment.Confidence * 100)
    $ui.LatencyLabel.Text = 'ROUND TRIP  {0:0}ms' -f $LatencyMs
    $ui.TopLevelLabel.Text = "TOP LEVEL  $($top.Level)"
    $ui.Gauges.ItemsSource = $bars
    $ui.CallLabel.Text = "CALLS  $script:calls"
    $ui.Status.Text = "$($Judgment.Model) · $($Judgment.Rubric.Count) ordered levels · probabilities sum to 1"
}

function Submit-Evaluation {
    $question = $ui.Question.Text.Trim(); $answer = $ui.Answer.Text.Trim(); $rubric = @(Get-CurrentRubric)
    $emptyLevels = @($rubric | Where-Object { !$_.Trim() })
    if (!$question -or !$answer -or $emptyLevels.Count -gt 0) { $ui.Status.Text = 'Question, answer, and every rubric level are required.'; return }
    if (!$script:online) { $ui.Status.Text = 'Set TYPESAFE_API_KEY and relaunch for a live Jev judgment.'; return }
    $request = New-EvalRequest $question $answer $rubric | ConvertTo-Json -Depth 12 -Compress
    $content = [Net.Http.StringContent]::new($request, [Text.Encoding]::UTF8, 'application/json')
    $watch = [Diagnostics.Stopwatch]::StartNew(); $task = $script:client.PostAsync('https://api.typesafe.ai/v1/systemone', $content); $script:calls++
    $script:pending.Add(@{ Task = $task; Watch = $watch; Content = $content; Rubric = $rubric })
    $ui.Working.Text = 'SCORING…'; $ui.Evaluate.IsEnabled = $false; $ui.Status.Text = 'Jev is evaluating the answer against each rubric level…'
}

$ui.Evaluate.Add_Click({ Submit-Evaluation })
$ui.Answer.Add_PreviewKeyDown({ param($sender,$event) if ($event.Key -eq 'Enter' -and !$event.KeyboardDevice.Modifiers.ToString().Contains('Shift')) { $event.Handled = $true; Submit-Evaluation } })
$ui.Question.Add_TextChanged({ if ($ui.ScoreLabel.Text -ne '—') { Reset-Result } })

$script:timer = [Windows.Threading.DispatcherTimer]::new(); $timer.Interval = [timespan]::FromMilliseconds(25)
$timer.Add_Tick({
    foreach ($entry in @($script:pending.ToArray())) {
        if (!$entry.Task.IsCompleted) { continue }
        [void]$script:pending.Remove($entry); $entry.Watch.Stop(); $response = $null
        try {
            $response = $entry.Task.GetAwaiter().GetResult(); if (!$response.IsSuccessStatusCode) { throw "HTTP $([int]$response.StatusCode)" }
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -AsHashtable
            $judgment = ConvertFrom-EvalResponse $body $entry.Rubric
            $script:latencies.Add($entry.Watch.Elapsed.TotalMilliseconds); Show-Judgment $judgment $entry.Watch.Elapsed.TotalMilliseconds; $ui.Working.Text = 'DECIDED'
        } catch { $ui.Working.Text = 'ERROR'; $ui.Status.Text = "Jev could not score this input: $($_.Exception.Message)" } finally { if ($null -ne $response) { $response.Dispose() }; $entry.Content.Dispose(); $ui.Evaluate.IsEnabled = $true }
    }
})
$window.Add_Closed({ $script:timer.Stop(); $script:client.CancelPendingRequests(); $script:client.Dispose() })
$window.Add_ContentRendered({ [void]$ui.Question.Focus() })
if ($VerifyUiTo) {
    $script:verifySubmitted = $false
    $script:verifyTimer = [Windows.Threading.DispatcherTimer]::new(); $verifyTimer.Interval = [timespan]::FromMilliseconds(300)
    $verifyTimer.Add_Tick({ if ($ui.ScoreLabel.Text -eq '—' -and $script:online -and !$script:verifySubmitted) { $script:verifySubmitted = $true; Submit-Evaluation; return }; if ($ui.ScoreLabel.Text -eq '—' -and $script:online) { return }; $verifyTimer.Stop(); $window.UpdateLayout(); $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($window); $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create($VerifyUiTo); try{$encoder.Save($stream)}finally{$stream.Dispose()}; $window.Close() })
    $verifyTimer.Start()
}
Reset-Result; $timer.Start(); try { [void]$window.ShowDialog() } finally { $timer.Stop(); $client.Dispose() }
