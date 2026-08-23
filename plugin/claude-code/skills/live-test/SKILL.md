---
name: live-test
description: "Trigger: \"live test\", \"prueba en vivo\", \"test in docker\", or finishing a feature in a repo with harness.gates.json. Runs the service in Docker against the real deploy shape before PR and writes .harness/live-test.md evidence."
---

## Why

Unit tests lie by omission: mocked DB, mocked queue, mocked config. Before
PR, run the service in Docker replicating the deploy environment as closely
as practical — real DB/cache/queue via docker compose, env config mirroring
the deploy manifests.

## Procedure

1. **Detect the compose setup**: look for `compose.yaml`, `docker-compose.yml`,
   or a `Makefile` target (`make up`, `make dev`, etc.). Use what the repo
   already has — don't invent a new compose file.
2. **Build and bring up** the stack with real dependencies (DB, cache,
   queue), not stubs.
3. **Wait for health** — poll the service's health endpoint or container
   healthcheck before hitting anything else.
4. **Run smoke tests** against the real endpoints: the feature's happy path,
   plus at least one failure path (bad input, missing auth, etc.).
5. **On failure**, capture logs (`docker compose logs <service>`) before
   tearing down — don't just report "it failed."

## Evidence

Write `.harness/live-test.md` with:

- Date
- Image/compose ref used
- Endpoints exercised
- Results (pass/fail per check)
- The exact commands run, verbatim

This file is what the Stop gate checks when the repo declares
`live-test-evidence` in `harness.gates.json`. **Never write it without
actually running the test** — a fabricated evidence file defeats the
purpose of the gate and will pass a check that proves nothing.

## Scope

This is a pre-PR gate, not a replacement for unit/integration tests. If the
repo has no compose/Makefile target to run the real stack, say so — don't
simulate a live test with mocks.
