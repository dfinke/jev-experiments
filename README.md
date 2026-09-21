# Jev Lens

> **What if PowerShell could ask AI, “Which file do you mean?” and get a probability back?**

Jev Lens is a small Windows desktop demo that turns a folder into a semantic search surface. Describe what you need in plain language, let Jev make typed micro-decisions over a bounded set of local files, and watch deterministic PowerShell ranking turn those decisions into a useful result.

It is intentionally compact: one PowerShell script, one WPF view, one API request, and a clear local fallback. There is no browser, npm install, agent framework, or administrator permission.

<a href="https://youtu.be/rLLO-umS140"><img src="https://img.youtube.com/vi/rLLO-umS140/hqdefault.jpg" alt="Watch the Jev Lens demo on YouTube" width="480"></a>

[Watch the Jev Lens demo on YouTube](https://youtu.be/rLLO-umS140)

## Try it

Requirements:

- Windows
- PowerShell 7.2 or newer (`pwsh`)
- A TypeSafe API key for live Jev decisions

Set `TYPESAFE_API_KEY` in your environment, then run from the project folder:

```powershell
cd path\to\jev-experiments\jev-lens
pwsh -NoProfile -STA -File .\Start-Lens.ps1
```

With no `-Path`, Jev Lens scans the current directory (`.`). To use another folder:

```powershell
pwsh -NoProfile -STA -File .\Start-Lens.ps1 -Path "$HOME\Downloads"
```

The scan is top-level and bounded to the first 200 files. The request sends at most 12 candidates to Jev.

For a repeatable demo, use the included sample folder:

```powershell
pwsh -NoProfile -STA -File .\Start-Lens.ps1 -Sample
```

You can also run without a key:

```powershell
pwsh -NoProfile -STA -File .\Start-Lens.ps1 -Offline
```

Offline mode keeps the local ranking and UI available without sending anything to the API. If the key is missing or a request fails, the app falls back to the same local behavior.

## The two-minute demo

With `-Sample`, try these prompts:

- **Artwork for the announcement** → `Launch-hero.svg`
- **The latest proposal** → `Atlas-proposal-approved.md`
- **Logs for troubleshooting** → `Checkout-errors.log`
- **What did we earn this month?** → `September-revenue.csv`
- **A recipe for banana bread** → no convincing match

Point it at a code folder and type `debounce`. If the term appears inside `go.mod` and `go.sum` but not in their filenames, those files still rise to the top because the local collector searches bounded text and configuration files. Jev receives only the fact that a query term matched, never the raw contents.

The result panel shows Jev’s target probability, category judgment, clarity judgment, measured latency, and the exact score used to order the rows. **Open file** launches the selected result with Windows’ default associated application. Nothing opens or runs automatically.

## How it works

```text
collect local metadata and bounded text signals
        ↓
build a small candidate snapshot with stable IDs
        ↓
ask Jev: target choice + kind choice + clear noul
        ↓
validate typed answers and probability distributions
        ↓
combine Jev with deterministic local relevance
        ↓
rank results and wait for the user’s explicit action
```

The ranking formula is:

```text
0.65 × target probability
+ 0.20 × (kind probability × local relevance)
+ 0.15 × local relevance
```

The category signal is gated by local relevance. An unrelated PowerShell module does not outrank a Go module that actually contains the requested term just because both are “code.”

The local score combines filename/category token coverage, bounded text-match coverage, and recency. Text and configuration files up to 1 MB are eligible for local term matching. Real paths stay local; the API state contains filenames, categories, sizes, modification ages, and content-match signals only.

Every query revision owns its candidate snapshot. Responses for older revisions are discarded, so a slow network response cannot reorder a newer query. The app coalesces fast typing, keeps at most two requests in flight, reuses its HTTP connection, and reports observed round-trip latency.

Jev’s typed questions follow the [TypeSafe System One model](https://docs.typesafe.ai/introduction): choices return a selected option, a probability distribution, and confidence; `noul` returns a 0–1 truth probability. Multiple questions can be evaluated in one request.

## Privacy and boundaries

- Raw file contents never leave the machine.
- Absolute paths, clipboard contents, and credentials are never included in the Jev state.
- The API key is read from `TYPESAFE_API_KEY` and sent only as an authorization header.
- Only a bounded top-level candidate set is considered.
- File names can still be sensitive; use the sample folder for screenshots or presentations.
- Jev suggestions are decisions for code to consume, not proof that a file is safe or correct.

## Project files

- `Start-Lens.ps1` — WPF window, input events, asynchronous requests, and the explicit open-file action.
- `Lens.Core.ps1` — file collection, local content matching, request construction, validation, and ranking.
- `Lens.xaml` — the native Windows layout and styling.
- `Test-Lens.ps1` — local contract tests and optional live smoke checks.

## Checks

Run the local checks without making API calls:

```powershell
.\Test-Lens.ps1
```

Run the five-query live smoke check:

```powershell
.\Test-Lens.ps1 -Live
```

The test suite covers bounded candidate snapshots, content matching, privacy-safe request state, typed-answer validation, stale-response protection, and ranking behavior when similarly categorized files compete.
