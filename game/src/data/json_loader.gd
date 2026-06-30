## json_loader.gd — read + parse JSON content files (ADR-0007).
##
## Pure-ish IO helper (no game rules). Reads a file or a whole directory of `.json`
## records under res://data/<kind>/. Files may be one-record-per-file OR an array of
## records; both normalize to an Array of Dictionaries. Returns a Result so the caller
## can fail-fast with a precise message (ADR-0007 failure policy). Offline only.
class_name JsonLoader
extends RefCounted

## Parse a single JSON file into a Result wrapping its parsed value (Dictionary or Array).
static func load_file(path: String) -> Result:
	if not FileAccess.file_exists(path):
		return Result.make_err("content file not found: %s" % path)
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return Result.make_err("content file empty/unreadable: %s" % path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return Result.make_err("JSON parse error in %s (line %d): %s"
			% [path, json.get_error_line(), json.get_error_message()])
	return Result.make_ok(json.data)

## Load every `.json` under `dir_path`, normalized to an Array of record Dictionaries.
## Each record is tagged with `_source` (the file it came from) for precise error messages.
static func load_dir(dir_path: String) -> Result:
	var records: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		# Missing directory is not fatal here (a kind may have no content yet).
		return Result.make_ok(records)
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			var full := dir_path.path_join(file_name)
			var r := load_file(full)
			if r.is_err():
				dir.list_dir_end()
				return r
			var data = r.value
			if data is Array:
				for rec in data:
					if rec is Dictionary:
						rec["_source"] = full
						records.append(rec)
					else:
						dir.list_dir_end()
						return Result.make_err("non-object record in array file %s" % full)
			elif data is Dictionary:
				data["_source"] = full
				records.append(data)
			else:
				dir.list_dir_end()
				return Result.make_err("top-level JSON in %s must be object or array" % full)
		file_name = dir.get_next()
	dir.list_dir_end()
	return Result.make_ok(records)
