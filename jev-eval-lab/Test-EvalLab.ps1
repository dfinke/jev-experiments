#requires -Version 7.2
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\EvalLab.Core.ps1"
function Assert($Condition, [string]$Message) { if (!$Condition) { throw "FAIL: $Message" }; Write-Output "PASS: $Message" }
function Assert-Rejected([scriptblock]$Action, [string]$Message) { $rejected = $false; try { & $Action | Out-Null } catch { $rejected = $true }; Assert $rejected $Message }
$rubric = @('Does not answer the request','Partially answers the request','Mostly answers the request','Fully answers the request')
$request = New-EvalRequest 'How useful is the answer?' 'It answers directly and includes an example.' $rubric
$wire = $request | ConvertTo-Json -Depth 12
Assert ($request.questions.score.type -eq 'score') 'Builds a typed Score question'
Assert ($request.questions.score.criteria.Count -eq 4) 'Preserves ordered rubric levels'
Assert ($wire -notmatch 'D:\\') 'Request contains no local path'
$probabilities = @{ '0'=0.0; '1'=0.1; '2'=0.3; '3'=0.6 }
$response = @{ model='test-fixture'; answers=@{ score=@{ type='score'; score=2.5; confidence=0.7; probabilities=$probabilities; legend=@{ '0'=$rubric[0]; '1'=$rubric[1]; '2'=$rubric[2]; '3'=$rubric[3] } } } }
$judgment = ConvertFrom-EvalResponse $response $rubric
$bars = @(Get-EvalBars $judgment)
Assert ($judgment.Score -eq 2.5) 'Reads the fractional Score value'
Assert ($bars.Count -eq 4 -and $bars[3].Percent -eq 60) 'Creates one probability gauge per level'
$response.answers.score.probabilities['3'] = 1.2
Assert-Rejected { ConvertFrom-EvalResponse $response $rubric } 'Rejects out-of-range probabilities'
$response.answers.score.probabilities['3'] = 0.6
$response.answers.score.probabilities['foreign'] = 0.0
Assert-Rejected { ConvertFrom-EvalResponse $response $rubric } 'Rejects unknown rubric levels'
$examples = @(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'EvalExamples.json') | ConvertFrom-Json)
Assert ($examples.Count -ge 5 -and @($examples.name | Sort-Object -Unique).Count -eq $examples.Count) 'Loads distinct saved examples'
Assert (@($examples | Where-Object { @($_.rubric).Count -ne 4 }).Count -eq 0) 'Every saved example has four rubric levels'
