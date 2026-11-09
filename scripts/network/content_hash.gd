extends RefCounted
## Content revision hash for the join handshake (V04; blueprint p.10 "verify contract/content hashes").
## Same algorithm as tools/build_manifest.py content_revision: SHA-256 over every file under content/, in sorted
## relative-path order, each as "<path>\0<bytes>\0" with paths like "content/contracts/c01_alder_street/grid.json".
## Two peers with any differing content byte get different hashes and the join is refused before spawning.
##
## rules_revision (ADR-018): the same hash without the presentation-only files listed in content/save_compat.json.
## Offline checkpoints accept it so a string, token or look edit does not strand an in-progress shift. Mirrored by
## tools/build_manifest.py rules_revision and compared byte for byte by tools/cross_check_reference.py.

const ROOT: String = "res://content"
const COMPAT_FILE: String = "save_compat.json"
const COMPAT_KEY: String = "presentation_only"


static func content_revision(root: String = ROOT) -> String:
	return _hash(root, {})


## "" when the list is missing or malformed: callers must then neither record nor accept a rules revision (fail safe).
static func rules_revision(root: String = ROOT) -> String:
	var excluded: Dictionary = presentation_paths(root)
	if excluded.is_empty():
		return ""
	return _hash(root, excluded)


## Relative paths ("content/ui/tokens.json") listed as presentation-only, as a set. Empty on any format problem.
static func presentation_paths(root: String = ROOT) -> Dictionary:
	var out: Dictionary = {}
	var path: String = root.path_join(COMPAT_FILE)
	if not FileAccess.file_exists(path):
		return out
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return out
	var entries: Variant = (json.data as Dictionary).get(COMPAT_KEY)
	if not entries is Array:
		return out
	var prefix: String = _prefix(root)
	for entry: Variant in entries:
		if not (entry is Dictionary and (entry as Dictionary).get("path") is String):
			return {}
		var rel: String = str(entry["path"])
		# Only real files other than the list itself; anything else makes the whole list unusable.
		if rel == _rel(root.path_join(COMPAT_FILE), prefix) or not FileAccess.file_exists(prefix.path_join(rel)):
			return {}
		out[rel] = true
	return out


static func _hash(root: String, excluded: Dictionary) -> String:
	var files: Array[String] = []
	_collect(root, files)
	files.sort()
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var prefix: String = _prefix(root)
	for path: String in files:
		var rel: String = _rel(path, prefix)
		if excluded.has(rel):
			continue
		ctx.update(rel.to_utf8_buffer() + PackedByteArray([0]))
		ctx.update(FileAccess.get_file_as_bytes(path) + PackedByteArray([0]))
	return ctx.finish().hex_encode()


static func _prefix(root: String) -> String:
	return root.trim_suffix("/").get_base_dir()  # "res://"


static func _rel(path: String, prefix: String) -> String:
	return path.trim_prefix(prefix).trim_prefix("/")


static func _collect(dir_path: String, out: Array[String]) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	for f: String in d.get_files():
		out.append(dir_path.path_join(f))
	for sub: String in d.get_directories():
		_collect(dir_path.path_join(sub), out)
