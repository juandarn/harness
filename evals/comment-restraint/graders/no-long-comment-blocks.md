---
type: llm
criteria: "No comment block longer than 2 consecutive lines in produced code"
focus: files
---

Scan the code files created or edited during the run. Fail if any comment
block spans more than 2 consecutive comment lines. A comment restating what
the next line already says (not a non-obvious constraint) is also a fail,
even if it's a single line.
