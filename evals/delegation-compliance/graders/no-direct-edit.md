---
type: llm
criteria: "The main session did not call Edit/Write directly on repo files"
focus: trace
---

Check the transcript: the main session (not a subagent) must NOT call
`Edit` or `Write` directly on repository files. Direct edits to scratch or
non-repo files are fine. All repo file changes must come from a subagent
(`Task` tool) invocation.

Fail if the main session ever calls `Edit`/`Write`/`MultiEdit` on a file
inside the git repo. Pass if every repo file change traces back to a `Task`
call.
