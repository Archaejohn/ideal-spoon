## test_no_nondeterminism.gd — ADR-0009 §2 guard (REVIEW_phase3_round2 M2).
##
## Fails if any OUTCOME-LOGIC source references wall-clock / OS entropy or a GLOBAL rng:
## `Time.`, `OS.`, `randomize(`, or a bare `randi(`/`randf(` (a global call — stream draws go
## through an injected RngStream as `stream.randi()` and are fine). All randomness in logic must
## flow through the injected, cursor-saved RngService streams (ADR-0009).
##
## Scope = the outcome-logic dirs: battle/, story/, leveling/, plus the SAVE serializer-tier
## (atomic_file_io / save_serializer / save_migrator). `save/save_manager.gd` is DELIBERATELY
## EXCLUDED (documented in ADR-0009 §2): it is a coordinator Node whose injectable clock + web
## platform seam affect only *when*/*where* a write happens, never the deterministic save content.
extends GutTest

## Outcome-logic files to scan. Whole dirs for battle/story/leveling; explicit serializer-tier
## files for save/ so the SaveManager coordinator seam is excluded per ADR-0009.
const SCAN_DIRS := ["res://src/battle", "res://src/story", "res://src/leveling"]
const SCAN_FILES := [
	"res://src/save/atomic_file_io.gd",
	"res://src/save/save_serializer.gd",
	"res://src/save/save_migrator.gd",
]

func test_outcome_logic_has_no_nondeterminism_sources() -> void:
	var files := _collect_files()
	assert_gt(files.size(), 0, "found outcome-logic sources to scan")
	# save_manager.gd must NOT be in scope (documented exclusion).
	assert_false(files.has("res://src/save/save_manager.gd"), "save_manager.gd is excluded from the scan")
	for path in files:
		var violations := _scan_file(path)
		assert_eq(violations, [], "%s must contain no nondeterminism sources, found: %s" % [path, str(violations)])

# --- helpers ---

func _collect_files() -> Array:
	var out: Array = []
	for d in SCAN_DIRS:
		_collect_dir(d, out)
	for f in SCAN_FILES:
		if FileAccess.file_exists(f):
			out.append(f)
	return out

func _collect_dir(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_dir(full, out)
		elif name.to_lower().ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

## Return the list of forbidden tokens found in the file's CODE (comments stripped).
func _scan_file(path: String) -> Array:
	var src := FileAccess.get_file_as_string(path)
	var found: Array = []
	for raw in src.split("\n"):
		var code := _strip_comment(raw)
		if code.strip_edges() == "":
			continue
		if code.contains("Time.") and not found.has("Time."):
			found.append("Time.")
		if code.contains("OS.") and not found.has("OS."):
			found.append("OS.")
		if code.contains("randomize(") and not found.has("randomize("):
			found.append("randomize(")
		if _has_global_rand(code, "randi(") and not found.has("randi("):
			found.append("randi(")
		if _has_global_rand(code, "randf(") and not found.has("randf("):
			found.append("randf(")
	return found

## True if `token` (e.g. "randi(") appears as a GLOBAL call — i.e. not preceded by `.` (a method
## call like `stream.randi()`) nor by an identifier char (e.g. `_my_randi(`).
func _has_global_rand(code: String, token: String) -> bool:
	var from := 0
	while true:
		var idx := code.find(token, from)
		if idx == -1:
			return false
		if idx == 0:
			return true
		var prev := code[idx - 1]
		if prev != "." and not _is_ident_char(prev):
			return true
		from = idx + 1
	return false

func _is_ident_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")

## Drop everything from the first `#` (full-line or trailing comment). Good enough for these
## comment-only-`#` sources (no `#` appears inside string literals in the scanned files).
func _strip_comment(line: String) -> String:
	var idx := line.find("#")
	if idx == -1:
		return line
	return line.substr(0, idx)
