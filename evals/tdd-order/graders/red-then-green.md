---
type: llm
criteria: "A failing test run was observed before a passing test run"
focus: trace
---

Check the transcript for a red-then-green cycle: at least one test run
result showing failure (the new test failing against no/incomplete
implementation) BEFORE a test run result showing success. Fail if the
implementation was written before any failing run was observed, or if no
failing run appears at all — this is the fallback grader when `tool_order`
can't see into test-run outcomes, only tool call order.
