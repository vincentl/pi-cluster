# ai/ — material for Claude Code sessions

Everything here is for driving AI sessions on this repo. Nothing in here runs on the cluster.

| Path | What | Who writes it |
|------|------|---------------|
| `prompts/` | One-shot kickoff prompts, dated. Paste the one-liner below into a new session. | Planning session (Fable) |
| `audit/` | Point-in-time findings about the repo, with `file:line` refs. Dated. | Planning session |
| `decisions.md` | Open questions with defaults, and the answers once given. Running log. | Vincent answers; sessions update |
| `plans/` | Per-phase plans written by the working session before it edits anything. | Working session (Opus) |
| `test-logs/` | Results of hardware test runs, dated. | Working session, from Vincent's pasted output |

## Start the next phase

Open a Claude Code session in this repo with Opus and send:

```
Read ai/prompts/2026-09-22-trixie-refresh.md and carry it out, starting with Phase 0.
```

Before that, answer the questions in `ai/decisions.md` (at least D2, D3, D6, D9). Unanswered
questions fall back to their stated default.

## Conventions

- Date files `YYYY-MM-DD-slug.md`.
- A prompt names the phases, the definition of done for each, and the decisions it depends on.
- An audit states facts with `file:line` and marks anything unverified as VERIFY.
- `CLAUDE.md` at the repo root is the standing instruction set; keep it short and true to the current tree.
