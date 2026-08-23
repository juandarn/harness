---
type: tool_order
before: "Edit|Write on *test*"
after: "Edit|Write on *slugify* (non-test)"
target: trace
---

The test file must be edited/written before the source file. Fail if the
source implementation file is created or edited before its test file
exists.
