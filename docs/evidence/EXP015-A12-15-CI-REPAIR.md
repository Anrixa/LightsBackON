# EXP015 A12.15 — Source-Authority CI Repair

Root issue: CI #818 rejected `test_EXP015_A12_10_25_regions_all_authenticated_stale_intents_denied`. The new replay fence denied cached responses solely because their originating host was obsolete, including previously **refused** anchor requests. This hid the original `ANCHOR_DISPATCH_CONTEXT_EXPIRED` reason and violated the established idempotent denial protocol.

Correction: preserve the old, already-refused response with `duplicate=true`; refuse only **previously accepted** cached responses with `EXP015_A12_15_STALE_REPLAY` after regional ownership is revoked. Invalid peers, forged sessions, sequence fencing and bind-once authority remain unchanged. The 25-region A12.15 host test now asserts repeatable stale denial as well as refusal of old successes. A12.10's original anchor contract stays intact.

Source host SHA (Git object, review still pending): `53b34e5680e1774930c77c974433cde315f3a0b6`. Previous host SHA remains in the qualified-history allowlist for provenance.

No original C01–C12, EXP04 reward/ledger, regional source topology, save/persistence, physical game, Steam multiplayer, or release promotion was modified. Linux and Windows CI must run against this corrected exact commit; pending results are not a certificate.
