# Jev Eval Lab

> **Give Jev a question, an answer, and a rubric. Get back a judgment you can see.**

Jev Eval Lab is a small Windows/PowerShell experiment for exploring Jev as an evaluator. Type a question, paste an answer, describe the ordered rubric levels, and press Enter. Jev returns a probability-weighted score, confidence, and a gauge for every level.

This is the evaluator counterpart to [Jev Lens](../jev-lens): Lens uses Jev to rank files; Eval Lab uses Jev to judge an answer.

## Run

Requirements:

- Windows
- PowerShell 7.2 or newer (`pwsh`)
- `TYPESAFE_API_KEY` for live scoring

```powershell
cd path\to\jev-experiments\jev-eval-lab
pwsh -NoProfile -STA -File .\Start-EvalLab.ps1
```

The window opens with a sample question, answer, and four-level rubric. Choose a saved scenario from **Try an example** to populate all fields, or edit any field yourself. Press Enter in the answer box or click **Evaluate with Jev**.

For ready-to-try prompts, see [TRY-IT-EXAMPLES.md](TRY-IT-EXAMPLES.md).

Without an API key, use `-Offline` to inspect the UI without making a request:

```powershell
pwsh -NoProfile -STA -File .\Start-EvalLab.ps1 -Offline
```

## What the score means

Jev’s `Score` is a position on the ordered rubric, not a percentage. With four levels, the result ranges from `0` to `3` and can be fractional. The probability bars show how the judgment is distributed across the levels; confidence describes how concentrated that distribution is.

For example, a score of `2.4` with probability spread across levels 2 and 3 says something different from a score of `2.4` concentrated entirely on one level. Read the score, bars, and confidence together.

The UI sends one `score` question with the exact rubric order supplied by the user. Jev evaluates every level against the same state and returns typed data; PowerShell validates the response before rendering it.

## Files

- `Start-EvalLab.ps1` — WPF window, input handling, asynchronous API call, and result rendering.
- `EvalLab.Core.ps1` — Score request construction, response validation, and gauge shaping.
- `EvalLab.xaml` — native Windows layout and visual styling.
- `EvalExamples.json` — saved question, answer, and rubric examples used by the example picker.
- `TRY-IT-EXAMPLES.md` — the same examples in a copy-and-paste friendly format.
- `Test-EvalLab.ps1` — local request, validation, and gauge tests.

## Checks

```powershell
.\Test-EvalLab.ps1
```

Jev’s Score primitive is documented in the [TypeSafe Score guide](https://docs.typesafe.ai/primitives/score). The experiment follows the useful constraint from that guide: keep each rubric one-dimensional and describe concrete situations rather than vague numeric degrees.
