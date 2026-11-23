extends RefCounted
## SAVE23 (owner-approved 23 Nov 2026, ADR-018 amendment): set aside a C01 checkpoint that was written by different
## mission rules. Such a record (CONTENT_MISMATCH) can never be resumed, and autosave refuses to overwrite it, so it used
## to block every new solo shift. After the player confirms, its file and .bak/.tmp siblings are MOVED into
## checkpoints/archived/ under a unique timestamped name. Nothing is deleted or rewritten. A corrupt, newer-schema or
## foreign record is never archivable. A failed move rolls back the files already moved.
## Kept apart from offline_persistence.gd, whose reviewed blob is pinned by the EXP014 A10 protected-source audit.

const OfflinePersistence := preload("res://scripts/persistence/offline_persistence.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")

const ARCHIVE_DIR: String = "archived"
const ARCHIVABLE_CODE: String = "CONTENT_MISMATCH"


static func archive_mismatched_checkpoint(store: OfflinePersistence, utc_now: String = "") -> Dictionary:
	if store == null:
		return _failure("NOT_ARCHIVABLE", "no local save store")
	var status: Dictionary = store.checkpoint_status()
	if str(status.get("code", "")) != ARCHIVABLE_CODE:
		return _failure("NOT_ARCHIVABLE", "only a checkpoint from different mission content can be set aside")
	var source: String = store.checkpoint_path()
	var archive_dir: String = source.get_base_dir().path_join(ARCHIVE_DIR)
	if DirAccess.make_dir_recursive_absolute(archive_dir) != OK:
		return _failure("ARCHIVE_FAILED", "could not create the archive folder; the checkpoint was preserved")
	var stamp: String = utc_now if utc_now != "" else Time.get_datetime_string_from_system(true, false) + "Z"
	var stem: String = "%s-%s" % [OfflinePersistence.CHECKPOINT_ID, stamp.replace(":", "").replace("-", "")]
	var target: String = archive_dir.path_join(stem + ".json")
	var serial: int = 1
	while _any_exists(target):
		serial += 1
		target = archive_dir.path_join("%s-%d.json" % [stem, serial])
	var moved: Array[Array] = []
	for suffix: String in ["", SaveService.BAK_SUFFIX, SaveService.TMP_SUFFIX]:
		if not FileAccess.file_exists(source + suffix):
			continue
		if DirAccess.rename_absolute(source + suffix, target + suffix) != OK:
			for done: Array in moved:
				DirAccess.rename_absolute(str(done[1]), str(done[0]))
			return _failure("ARCHIVE_FAILED", "could not move the checkpoint; nothing was changed")
		moved.append([source + suffix, target + suffix])
	return {"ok": true, "archived_path": target, "files": moved.size()}


static func _any_exists(target: String) -> bool:
	for suffix: String in ["", SaveService.BAK_SUFFIX, SaveService.TMP_SUFFIX]:
		if FileAccess.file_exists(target + suffix):
			return true
	return false


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
