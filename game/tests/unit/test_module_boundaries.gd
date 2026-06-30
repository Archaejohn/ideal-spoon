## test_module_boundaries.gd — ADR-0009 module-boundary guard (REVIEW_phase3_round2 N2).
##
## The headless outcome-logic modules must stay decoupled from the scene/coordinator layer:
## they take deps by injection and never reach for an autoload singleton, nor `preload` a `ui/`
## or `overworld/` script. This keeps the core pure (and the >=80% coverage target attainable).
##
## Scope = the LOGIC modules only: battle/ (minus the BattleController bridge Node), story/,
## leveling/, and the save serializer-tier (atomic_file_io / save_serializer / save_migrator).
## The coordinator Nodes — battle/battle_controller.gd and save/save_manager.gd — are EXCLUDED:
## they are the intended bridges to the tree and legitimately use autoloads (documented in
## ADR-0009 §"Module-boundary guard" / §2).
extends GutTest

const AUTOLOAD_NAMES := [
	"Log", "RngService", "EventBus", "ContentDB", "SettingsService", "GameState",
	"SaveManager", "SceneRouter", "GameCoordinator", "BattleController",
]

## Files excluded from the boundary scan (coordinator / bridge Nodes).
const EXCLUDED := [
	"res://src/battle/battle_controller.gd",
	"res://src/save/save_manager.gd",
]

const SCAN_DIRS := ["res://src/battle", "res://src/story", "res://src/leveling"]
const SCAN_FILES := [
	"res://src/save/atomic_file_io.gd",
	"res://src/save/save_serializer.gd",
	"res://src/save/save_migrator.gd",
]

func test_logic_modules_do_not_reference_autoloads_or_ui_scripts() -> void:
	var files := _collect_files()
	assert_gt(files.size(), 0, "found logic modules to scan")
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		var code := _strip_comments(src)
		# No autoload singleton references (whole-word, in code).
		for autoload_name in AUTOLOAD_NAMES:
			assert_false(_references_identifier(code, autoload_name),
				"%s must not reference autoload '%s'" % [path, autoload_name])
		# No preload/load of ui/ or overworld/ scripts.
		assert_false(code.contains("res://src/ui/"), "%s must not reference ui/ scripts" % path)
		assert_false(code.contains("res://src/overworld/"), "%s must not reference overworld/ scripts" % path)
		# Logic modules are RefCounted (injected deps), not tree-bound Nodes.
		assert_true(code.contains("extends RefCounted"), "%s should be a RefCounted logic module" % path)

func test_excluded_bridges_are_not_in_scope() -> void:
	var files := _collect_files()
	for ex in EXCLUDED:
		assert_false(files.has(ex), "%s is excluded from the boundary scan (coordinator/bridge)" % ex)

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
		elif name.to_lower().ends_with(".gd") and not EXCLUDED.has(full):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

## True if `ident` appears as a whole-word identifier in the code (not as a substring of a
## longer identifier, and not preceded by `.` as a member access).
func _references_identifier(code: String, ident: String) -> bool:
	var from := 0
	while true:
		var idx := code.find(ident, from)
		if idx == -1:
			return false
		var before_ok := idx == 0 or (not _is_ident_char(code[idx - 1]) and code[idx - 1] != ".")
		var after_idx := idx + ident.length()
		var after_ok := after_idx >= code.length() or not _is_ident_char(code[after_idx])
		if before_ok and after_ok:
			return true
		from = idx + 1
	return false

func _is_ident_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")

func _strip_comments(src: String) -> String:
	var out: Array = []
	for line in src.split("\n"):
		var idx := line.find("#")
		if idx == -1:
			out.append(line)
		else:
			out.append(line.substr(0, idx))
	return "\n".join(PackedStringArray(out))
