# Jev Lens

A small native Windows / PowerShell demo: describe the file you need and watch Jev's typed micro-decisions change the ranking. Local matches sit beside probability bars and the exact deterministic score. No browser, npm packages, agent framework, or admin rights required.

## Run

Requires Windows and **PowerShell 7.2+** (`pwsh`). Uses the existing `TYPESAFE_API_KEY` environment variable; the key is never written to disk.

```powershell
cd D:\mygit\jev-lens
pwsh -NoProfile -STA -File .\Start-Lens.ps1
```

With no `-Path`, the app scans the current directory (`.`). The command above therefore scans `D:\mygit\jev-lens` itself. Use `-Sample` when you want the repeatable demo folder with 12 tiny files and deliberately different modification times:

```powershell
pwsh -NoProfile -STA -File .\Start-Lens.ps1 -Sample
```

Existing sample files are preserved. The app starts with an empty query. Click an example chip or type naturally.

To explore your own folder (top level, up to the first 200 files; at most 12 sent per query):

```powershell
pwsh -NoProfile -STA -File .\Start-Lens.ps1 -Path "$HOME\Downloads"
```

For local-only mode, add `-Offline`. Missing credentials also use local-only mode. Close and relaunch after changing environment variables. Use **Refresh files** to rescan metadata; there is no background filesystem watcher.

## A two-minute demo

1. **Artwork for the announcement** → `Launch-hero.svg`. Compare the columns: no filename contains those words, so local ranking favors the recent error log; Jev recognizes the likely visual asset.
2. **The latest proposal** → `Atlas-proposal-approved.md` beats the older draft. Try **A proposal** to remove the recency cue.
3. **Logs for troubleshooting** → `Checkout-errors.log`; compare the successful deployment log. The independent “clear” judgment can remain tentative even with a strong target choice.
4. **What did we earn this month?** → `September-revenue.csv`, despite having no literal word overlap with the filename.
5. Try **A recipe for banana bread** → “No convincing match.”

When pointed at a code folder, a query can match file contents too. For example, typing `debounce` in a folder where only `go.mod` and `go.sum` contain that term brings those two files to the top. The local collector reads bounded text/config files; Jev sees only the fact that a query term matched, never the raw contents.

The rows show the target probability; the smaller equation shows the combined ranking score. **CLEAR** is Jev's independent 0–1 judgment that one candidate stands out, not a calibrated guarantee of correctness. **Open file** launches the selected file with Windows' default associated application. Nothing opens, runs, moves, or deletes automatically. Judgments may vary between runs.

## The architecture worth porting

Adapted from `D:\mygit\nader-dabit-jev\jev-launcher\Sources\JevQuestions.swift`, `Ranker.swift`, `JevClient.swift`, `LauncherModel.swift`, and the uploaded **Pasted markdown.md** notes.

```text
Get-ChildItem → literal/recency shortlist → Jev (one request)
             → validate typed answers → weighted rank → optional Explorer reveal
```

Keep five ideas from the Mac app:

- A small candidate snapshot with stable IDs and useful metadata. Keep real paths local.
- One fan-out request: `target` **choice**, `kind` **choice**, `clear` **noul**. Consume the full choice distributions.
- Deterministic composition: `0.65 × P(target) + 0.20 × (P(kind) × local) + 0.15 × local`. The kind signal is gated by local relevance so an unrelated file of the same broad category cannot outrank a direct content match.
- Asynchronous requests and revision checks so stale results never replace the current query's results.
- Visible measured latency and honest local fallback when credentials, network, or response validation fail.

Leave out global hotkeys, launch actions, calculators, clipboard context, persistent preferences, and OS toggles. This is a decision demo over files, not a launcher port.

Differences from the original: a 90 ms input pause coalesces bursts, at most two HTTP requests run at once, and a response must match the **exact current revision**, not merely be newer than the previous answer. Each request owns its candidate snapshot. The previous probabilities clear as soon as the query changes. A reusable `HttpClient` keeps connections warm; a 25 ms WPF dispatcher poll keeps network waits off the UI thread. Requests time out after 8 seconds; HTTP 429 adds a 10-second cooldown.

Local score is 55% filename/category token coverage, 25% bounded local text-match coverage, plus 20% recency (`1 / (1 + ageHours/24)`). For text/config files up to 1 MB, PowerShell checks whether query terms occur in the file. It sends Jev only `content_match_count` and `content_match_terms`; raw contents never leave the machine. Empty/no-key/error states show only this local score, never fabricated AI probabilities. A `none` probability at least as high as the top ranked file suppresses the suggestion action.

The current typed API is documented by [TypeSafe](https://docs.typesafe.ai/introduction). Runtime validation checks expected answer types, candidate IDs, finite 0–1 probabilities, and distribution totals. No model text is executed.

## Data and limitations

Jev receives the query plus up to 12 filenames, file categories, byte sizes, modification ages, and local content-match signals. **No file contents, absolute paths, clipboard data, or credentials appear in the state.** The API key is sent only as the authorization header to `https://api.typesafe.ai/v1/systemone`. Filenames may still be sensitive; use the included sample folder for presentations.

Only the shortlist can win. Large folders are deliberately bounded; this is not a full disk search. File age means modification time, not download time. Filenames suggest purpose but do not prove content or safety. No cost estimate is shown because pricing and token usage can change.

On this machine, a five-query sample probe on 2026-09-21 returned four expected file choices and `none` for the unrelated query. The first call took 469 ms; warm calls took 142–193 ms. These are observations, not a latency promise. The UI reports observed round-trip latency (includes up to about 25 ms polling delay), running p50, and request count; hover for p95 and stale count.

## Files and checks

- `Start-Lens.ps1` — WPF events, bounded asynchronous request loop, safe reveal action.
- `Lens.Core.ps1` — sample data, collection, shortlist, typed request, validation, ranking.
- `Lens.xaml` — native window layout and styling.
- `Test-Lens.ps1` — local contract/edge checks; optional live smoke checks.

```powershell
.\Test-Lens.ps1
.\Test-Lens.ps1 -Live  # five real API calls

# Render the real window after a response, report UI state, then exit.
New-Item -ItemType Directory -Force work | Out-Null
pwsh -NoProfile -STA -File .\Start-Lens.ps1 -InitialQuery "The latest proposal" -VerifyUiTo "$PWD\work\live.png"
pwsh -NoProfile -STA -File .\Start-Lens.ps1 -Offline -VerifyUiTo "$PWD\work\offline.png"
```
