# Running Claude Code against a local Qwen, in the same window, with the same login

> Draft for publication. Portuguese docs in `docs/` are the deep dive; numbers below are
> measured on one machine (MacBook Pro M5 Pro, 48 GB) in September 2026.

Claude Code lets you point `ANTHROPIC_BASE_URL` at any server that speaks the Anthropic
Messages API. Most guides stop there, and lose the cloud model, the claude.ai login and the
connectors in the process. This repo is what it took to make **`/model qwen3.8-27b-gguf-nothink`
switch to a local model inside the same VS Code conversation**, with `/model claude-...` switching
back, and what actually broke along the way.

## Three things nobody tells you

**1. With five claude.ai connectors enabled, Claude Code sent 152 tool definitions in every
request.** 117 of them were connector schemas (Notion, Gmail, HubSpot, Drive, Calendar):
about 100K tokens before your first message. A 27B model with a 119K context cannot take a
single turn. A tiny transparent router (`router/router.py`) strips only those `mcp__claude_ai_*`
tools on the local path (an explicit, opt-in choice), leaving the cloud path untouched. Payload:
534 KB → 154 KB.

**2. Qwen3.8's chat template defaults to `reasoning_effort: xhigh`, and LM Studio ignores every
API knob that would turn it off** (`thinking.type`, `chat_template_kwargs.enable_thinking`,
`reasoning_effort`, `/no_think`, all tested on both engines). The fix is a template variant of
the same weights. Same task (a CPF validator with two pytest tests): xhigh **did not finish
thinking in 238 s**; `low` answered in 57 s; `nothink` in 39 s.

**3. LM Studio's MLX engine is 2× faster at prefill but its memory peaks kill long agentic sessions
on 48 GB.** A single 90K-token prompt: MLX peaks at 37 GB (29 GB retained afterwards), free RAM
hits 10 %; llama.cpp (GGUF) stays around 26 GB RSS with 33 % free. Decode speed is identical
(~17 tok/s; llama.cpp reaches ~21 with MTP speculative decoding). For coding-agent sessions,
llama.cpp wins. Claude Code also sends a `system`-role message *after* the user message; the
Qwen template raises on it under llama.cpp's minja. The GGUF variants patch that too.

## Does it actually ship code?

Replays with a known answer: take a shipped card from a real Next.js 16 project, reset to the
parent commit, hand the local model the card's spec as a plan, and grade it with the *reference*
tests from the real commit (hidden during execution) plus `npm run check` and `npm run build`.

| Card | Regime | Turns | Time | check | build | reference e2e |
|---|---|---|---|---|---|---|
| LUM-114 · scroll hint + JSON-LD (UI debt) | nothink | 44 | **15.5 min** | ✓ | ✓ | 54 passed, 0 failed |
| LUM-114 | low | 46 | 36 min | ✓ | ✓ | 54 passed, 0 failed |
| LUM-114 | xhigh | 57 | 55 min | ✓ | ✓ | 54 passed, 0 failed |
| LUM-103 · error states (P1 bug, 7 files) | nothink | 61 (cap) | 28 min | ✓ | ✗ | unit 19/19 ✓; build broke: client hook in a server component |
| LUM-103 | low | 61 (cap) | 68 min | ✓ | ✓ | 41 passed, 0 failed; unit 19/19; it split the banner into a `"use client"` component |
| LUM-111 · light theme + 3-state toggle, CSP hash (feature) | nothink | 53 | 23 min | ✓ | ✓ | 60 passed, 0 failed |
| LUM-111 | low | n/a | **timeout (90 min)** | ✗ | ✓ | 27 failed / 33 passed; 2.5 min per turn of deliberation, first write at minute 67 |
| LUM-128 · a11y lint (jsx-a11y) + Lefthook hooks (live card, no reference tests) | nothink | 61 (cap) | 12.5 min | ✗ | ✓ | deps installed, ESLint config right (worked around a plugin-redefinition clash with `eslint-config-next`), 1 of 3 a11y findings fixed; hooks never written; ~25 turns went to tooling discovery |
| LUM-128 | low | 61 (cap) | 56 min | ✗ | ✓ | cleaner ESLint config, lint + typecheck green with all 3 findings handled; hooks never written; `npm test` broke because `--legacy-peer-deps` (its answer to an ERESOLVE) pruned `vite`, vitest's peer; `nothink` made the same mistake |

Every run was fully autonomous (`claude -p`, nobody in the loop), so "interventions" is zero by
construction. Each cell is a single run: treat the table as evidence, not as a benchmark. The
model is the 4-bit UD-Q4_K_S quant on llama.cpp. The test code was hidden from the model; what
the tests check is described in the card, as it would be for any developer.

The pattern so far. `nothink` is the right default for well-specified UI/debt cards. `low`
(brief reasoning) pays for itself where an architecture boundary is involved: on LUM-103 it
created a `"use client"` component where `nothink` called a client hook from a server component
and could not recover. `xhigh` bought nothing but time. `low` can also over-deliberate: on
LUM-111 it read for 67 minutes and timed out on a card `nothink` shipped in 23. Neither regime
dominates. Five of seven valid replay runs shipped. The live card (LUM-128) shipped in neither
regime: both spent about 40% of the 60-turn cap learning three unfamiliar tools and both fell
into the same `--legacy-peer-deps` trap, the kind of project fact the retrieval layer exists to
carry. Baseline for LUM-114 on the untouched tree: 5 reference tests failing. Per-run summaries:
`evals/results/replays.md` (raw transcripts are not published; they contain the target
project's code).

## What is in here

- `router/router.py`: a 170-line Anthropic-API router. `claude-*` → api.anthropic.com with your
  OAuth headers passed through (login and connectors keep working), anything else → LM Studio.
  Streams SSE. Installed as a LaunchAgent. `tests/smoke.sh` exercises it against fake upstreams.
- `bin/gguf-variant.sh`: builds `low`/`nothink`/`base` template variants of a GGUF (the MLX
  variants are symlinked directories with an edited `chat_template.jinja`).
- `bin/memguard.sh`: the memory guard that stopped the machine from freezing again (LM Studio's
  load guardrail only acts at load time; the engine's prompt cache grows after).
- `evals/run.sh`: the replay harness (detached worktree at the parent commit, hidden reference
  tests, memory sampling). `evals/results.md` and `evals/results/replays.md`: the numbers.
- `mcp/`: two small MCP servers: `knowledge` (vector search over your conventions/plans via
  BGE-M3 in LM Studio) and `web` (DuckDuckGo search + page text; Claude Code's own WebSearch
  needs the Anthropic API and does not work with a local model).

## Install

macOS / Apple Silicon, LM Studio 0.4+, Claude Code.

```sh
git clone https://github.com/vieiradiego/cernyn-llm-local-router
cd cernyn-llm-local-router && ./install.sh --dry-run   # then without --dry-run
```

Then the one VS Code setting: `"claudeCode.environmentVariables": [{"name": "ANTHROPIC_BASE_URL",
"value": "http://localhost:4000"}]`, reload the window, `/model qwen3.8-27b-gguf-nothink`.

**Read before using:** the router forwards *your own* Claude Code credentials to Anthropic on
your behalf. It binds to `localhost` only, never expose it, never use those tokens outside
Claude Code (that violates Anthropic's terms). Nothing here trains on Claude's outputs. The
knowledge pipeline is retrieval only.

## The decisions, with evidence

`docs/04-decisoes.md` (PT-BR) records every choice, including the ones that were reverted and
the hypotheses that were tested and refuted (language costs, prompt-cache reuse, parallel slots,
beta headers). MIT.
