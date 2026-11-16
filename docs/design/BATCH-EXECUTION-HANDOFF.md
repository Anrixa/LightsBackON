# Lights Back On — Owner-approved consolidated engineering cadence

- Decision: 16 November 2026 (owner request, retained for future project-chat handoffs).
- Scope: continuation of the DS11–DS14 design and subsequent unlocked roadmap phases.
- Priority: implement a **substantial, cohesive batch of production code, original assets, content, automated regressions and evidence** before invoking computationally expensive full-suite or repeated CI runs.
- Do **not** interrupt work with routine tests after every tiny edit. Tests should be authored **alongside** the implementation and executed **once the batch is significant**.
- An exception is allowed for a **genuine testing need**: a high-risk save, security, authority, crash, irreversible action, or incompatible API/engine issue that cannot responsibly wait. Tell the owner exactly why this early test is necessary and what it covers.
- Preserve the project's **hard merge gates**: no PR merge and no DONE/CLOUD_VERIFIED upgrade before the exact final source passes the required Linux and Windows CI, plus other applicable release/hardware evidence. Defer tests, **never waive** them.
- One milestone phase remains one reviewable branch/PR. Multiple coherent internal development steps and commits may be accumulated in the branch before a single test cycle.
- Physically rendered visual checks, actual controller feel, GTX1650/Intel UHD P95 performance, and human/V09/F02 Steam gates are separately recorded as pending, not inferred from CI.
- Keep host-authority, status honesty, accessibility, original licensed assets and saved-data preservation. Do not start Steam publishing, enable telemetry or delete/migrate user data.
- When moving to a new chat: read `CLAUDE.md`, `docs/design/DS07-design-plan.md`, `docs/design/quality-workstream.json`, this file, current milestone evidence and latest `main`. Summarize completed internal steps, unrun test gates, outstanding design tasks, exact branch/PR SHA, and the next executable step. Do **not** restart from a previous chat's older ZIP or checkpoint.
- Owner's test cadence governs how work is grouped; it does not change any locked gameplay, design, billing or release decisions.
