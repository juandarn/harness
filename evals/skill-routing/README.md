# Skill routing eval

Does Claude invoke the right personal skill for a prompt, and does an injected router hint help?

```bash
bash ab.sh <scratch-dir>    # prompts.tsv x 2 reps x {router, norouter}, throwaway git repo per run
```

`prompts.tsv` is held out: the routing regexes were written before these phrasings existed.

## Result (Opus, 2026-09-19, 40 sessions)

| Arm | Right skill invoked | Sessions with no tool use |
|---|---:|---:|
| no router (descriptions only) | **20/20** | 0 |
| router hint via UserPromptSubmit | 12/20 | 4 |

The router was removed. Descriptions starting with "ALWAYS use this skill when ..." plus concrete trigger phrases are enough, and a per-prompt hint costs tokens on every message while measuring worse.

## Measurement traps found the hard way

Three earlier versions of this eval reported 4/30, 0/10 and 3/20 — all artifacts, not model behavior:

1. **Plan mode** (`--permission-mode plan`): the model defers skills while planning.
2. **`--disallowedTools Bash,...`**: a skill whose work needs those tools becomes pointless, so the model answers in prose instead. Sessions showing zero tool calls are the tell.
3. **Parallel sessions**: concurrent `claude -p` runs hit account rate limits and die silently. A dead session looks exactly like "did not invoke the skill". Always record whether the session produced any assistant turn, and run sequentially.
