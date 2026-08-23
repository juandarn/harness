---
type: regex
pattern: "(^\\s*(#|//|\\*).*\\n){4,}"
flags: m
match: not_contains
target: files
---

Negative-check hint for the LLM grader above: a regex match here (4+
consecutive comment-marker lines) is a strong signal of a doc-comment block
that should have been trimmed to 1-2 lines.
