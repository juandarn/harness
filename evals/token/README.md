# Token eval

Measures what session settings cost on the **installed** Claude Code config. Arms differ only by a `--settings` overlay (env vars + `autoCompactWindow`). Every task has an executable pass check.

```bash
python3 token_eval.py tasks 3            # 6 short repo tasks x arms x reps
python3 token_eval.py long 2 old new-gate   # 14-turn --resume session over ~1.2k-line modules
```

Long mode counts tokens per request from the session transcript, subagents included. The `-p` JSON reports cumulative totals on `--resume`, so summing it per turn double counts. Run sessions sequentially or with low parallelism: parallel sessions hit account rate limits and fail silently.

## Results (Opus, 2026-09-19)

**Long session** (14 turns, each pulling ~20k tokens of tool output; 2 reps; 14/14 fixes in every run):

| Arm | Input tokens | Max context | Requests |
|---|---:|---:|---:|
| old (delegation gate on, 1M window) | 3.6M | 140k | 44 |
| new (inline edits, `BASH_MAX_OUTPUT_LENGTH=12000`, 200k window) | **1.8M (−50%)** | 56k | 44 |
| compact-only (old + 200k window) | 6.9M (+92%) | 146k | 122 |

- Capping Bash output halves the bill: an oversized output goes to a file with a short preview instead of staying in context for every later turn.
- The compact-only arm hit the delegation gate on its first edit and then spawned one subagent per fix (14 subagents). Same result at nearly double the tokens: **forced delegation is expensive**. The old arm happened to dodge the gate by editing through Bash.
- No arm crossed 200k, so this eval does **not** measure auto-compaction.

**Short tasks** (6 tasks × 3 reps × 3 arms = 54 runs, 54/54 pass): mean input 157k (old) vs 116k (new, gate) vs 125k (new, native Read cap). The paired median delta is ~0%. The difference comes from a few old-config runs that blew up, and short tasks rarely do.

**Read range gate** (`HARNESS_READ_GATE=1`): no measurable gain on the big-file task, so it ships opt-in.
