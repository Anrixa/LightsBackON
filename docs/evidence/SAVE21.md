# SAVE21 — bounded local save-file intake and emission

## Root cause
`SaveService._inspect()` used `FileAccess.get_file_as_string(path)` before checking any size. A damaged or externally replaced `user://` checkpoint/profile could therefore allocate unbounded memory during menu startup, resume, or autosave validation.

## Code
- Add an explicit 2 MiB UTF-8 record ceiling.
- Open each record once and read at most `MAX_RECORD_BYTES + 1` from that descriptor. Reject oversized current/temp/backup files before JSON parsing.
- Refuse an oversized outgoing envelope **before** writing a temp file, moving the current record, or altering backups.
- Preserve existing checksum, crash recovery, readable-backup fallback, and newer-schema refusal behavior.

## Regression
`tests/unit/test_G06_save.gd`: oversized current with intact backup, non-destructive rejection of an outgoing oversized record, and oversized only-copy fail-closed behavior.

## Gates and nonclaims
CI on the *final exact source head*: complete Python + Godot reference validation, Linux and Windows tests, Windows release export/headless smoke, CodeQL and relevant resource probes. Real disk power-loss, malware races and physical GPU/controller acceptance are not claimed. No save schema, user data migration or external telemetry changes.

## Resume notes
If any test or build fails, fix and rerun exact-head CI before merge. Do not automatically delete oversized inputs; a human owner must decide retention/recovery.
