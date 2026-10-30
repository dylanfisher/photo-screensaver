# agentic-starter-kit

A minimal foundation for projects built with AI coding agents. Stack-agnostic: it sets up how the
work is done, not what it's written in.

## Use it

```sh
git clone --depth 1 https://github.com/dylanfisher/agentic-starter-kit my-thing
cd my-thing
rm -rf .git
git init && git add -A && git commit -m "first commit"
```

Then open Claude Code and run `/scaffold`. It interviews you through
[docs/scaffold.md](docs/scaffold.md) — stack, tooling, the `check` gate, boundaries — fills in
AGENTS.md, and deletes the scaffolding files as its last step.

## What's here

| Path | Purpose |
|---|---|
| `AGENTS.md` | The point of the repo. Read by every agent, every session. Kept under ~50 lines. |
| `CLAUDE.md` | Imports AGENTS.md; holds Claude Code-only notes. |
| `scripts/check` | The gate — AGENTS.md limits, map and link integrity, scaffolding residue, format, lint, typecheck, arch, test. One command to remember. |
| `scripts/setup`, `scripts/dev`, `scripts/test` | Bootstrap, run, test. Stubs until scaffolded. `dev` is the only place the run command — `op run` wrapper and all — is written down. |
| `.github/workflows/check.yml` | CI runs the same gate. Needs its language setup step filled in. |
| `.github/pull_request_template.md` | Why, what to look at, how it was verified. |
| `docs/scaffold.md` | Post-clone checklist — the single source for the setup procedure. Deleted once used. |
| `docs/map.md` | Where things live and how to find one before building a second. Conventions, not an inventory. |
| `docs/principles.md` | Rationale behind the principles in AGENTS.md. |
| `docs/writing.md` | Voice for comments and docs, and the commit message format. |
| `docs/decisions/` | ADRs — why things are the way they are. |
| `.claude/` | Permission allowlist and the `/scaffold` command. |

## The two ideas

**One gate.** `./scripts/check` means AGENTS.md can say "run `./scripts/check` before declaring
done" and never change again, whatever the stack becomes. Agents follow one named command far more
reliably than a list of four. It runs every step even after one fails, so fixing four problems costs
one run instead of four.

**One file, kept small.** AGENTS.md accretes a rule every time an agent misbehaves, and a few
hundred iterations later it's a wall of special cases that performs *worse* than the short version.
The ~50-line limit is the mechanism against that; anything longer moves to `docs/` and is linked.
Everything a formatter or linter can enforce stays out of it entirely — including that limit, which
`./scripts/check` enforces rather than trusting anyone to remember.

The principles baked into AGENTS.md — single source of truth, match the surrounding code, DRY on the
third occurrence, smallest viable change, fail loudly — don't change per project, so they ship
filled in. Everything else is a placeholder for `/scaffold`.


## Tips & Tricks

- Change, adapt, and remove these files to fit your project! This repo is just here to help set up a solid foundation.
- Create a retrospective skill that will analyze your last set of prompts and help you identify slow
  areas in your feedback loop. Make sure agents don't spend unnecessary time tripping over the same things.
- AGENTS.md ships with a **Pre-release** boundary: breaking changes are ok, and stored data has one shape with no
  migrations. It stops agents writing compatibility code for data nobody has yet. Delete it when you launch.
- Review and refactor often. Check for code duplication and ensure DRY. Keep the core clean so future code doesn't drift.
  Try to automate this: e.g. every N commits run an automated scan with cheap and fast agents.
- Plan out large behaviors extensively. Start with a quick list of features, have an agent improve these based on
  context awareness of the app, then create a multi-step plan.md file. Craft a prompt the will instruct an orchestrator
  to implement each step using subagent(s).
- For a performance-oriented app, measure and profile often. Watch for performance drift and fix before changes get merged.
- For a typographic website, use AGENT rules to make sure typography is only applied via distinct class names and never
  one-off line-height, letter-spacing, or font-sizing adjustments.
- Encourage a particular comment style and language usage early on (e.g. try to avoid claudisms). I've found myself in
  situations where a fully agentic project with lots of stored memories and documentation can develop a tendency towards
  esoteric language tendencies. Imagine simple code documentation that sounds like riddles, and it grows and perpetuates
  because the code tries to match the style of existing code.
