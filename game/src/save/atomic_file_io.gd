## atomic_file_io.gd — the crash-safe write primitive (ADR-0005 §b).
##
## Pure file mechanics (RefCounted). Guarantees "no corrupted saves across an abrupt kill"
## via temp-write + validate + validate-before-backup + atomic rename, and turns a torn
## write into a recoverable event via a checksum-validated backup. Operates under user://.
##
## Ordered write (a GOOD backup is NEVER overwritten by a TORN main):
##   1. write bytes -> `path.tmp`, flush, close
##   2. VALIDATE `path.tmp` (re-read; magic+checksum). Invalid => abort, change nothing.
##   3. if a current `path` exists, VALIDATE it; ONLY if it validates copy it to `path.bak`.
##   4. DirAccess.rename(path.tmp -> path)  (atomic replace on the platform FS)
##
## Validated read with backup recovery:
##   read `path`; if magic+checksum fail, fall back to `path.bak`; if both fail => Err.
class_name AtomicFileIO
extends RefCounted

const Serializer := preload("res://src/save/save_serializer.gd")

## Validator: bytes -> bool. Default validates the SaveSerializer envelope. Injectable so
## the primitive can be exercised in isolation.
var _validate: Callable = func(b: PackedByteArray) -> bool: return Serializer.is_valid(b)

func _init(validator: Callable = Callable()) -> void:
	if validator.is_valid():
		_validate = validator

## Atomically write `bytes` to `path` (under user://). Returns Result.ok(true) or Result.err.
func write(path: String, bytes: PackedByteArray) -> Result:
	_ensure_dir(path)
	var tmp := path + ".tmp"

	# 1. write the temp file, flush + close (close flushes the OS buffer).
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return Result.make_err("cannot open temp for write: %s (err %d)" % [tmp, FileAccess.get_open_error()])
	f.store_buffer(bytes)
	f.flush()
	f.close()

	# 2. VALIDATE the temp before it is allowed to become the live save.
	var tmp_bytes := _read_all(tmp)
	if tmp_bytes.is_empty() or not _validate.call(tmp_bytes):
		_remove(tmp)
		return Result.make_err("temp failed validation, aborting write: %s" % tmp)

	# 3. Promote the CURRENT file to .bak ONLY if it currently validates.
	#    A torn/corrupt main must never clobber a good backup.
	if FileAccess.file_exists(path):
		var cur := _read_all(path)
		if not cur.is_empty() and _validate.call(cur):
			var bak := path + ".bak"
			var bf := FileAccess.open(bak, FileAccess.WRITE)
			if bf != null:
				bf.store_buffer(cur)
				bf.flush()
				bf.close()

	# 4. Atomic replace.
	var dir := DirAccess.open(_dir_of(path))
	if dir == null:
		_remove(tmp)
		return Result.make_err("cannot open dir for rename: %s" % _dir_of(path))
	var rerr := dir.rename(tmp, path)
	if rerr != OK:
		_remove(tmp)
		return Result.make_err("rename failed: %s -> %s (err %d)" % [tmp, path, rerr])
	return Result.make_ok(true)

## Read `path`, validating magic+checksum; on failure fall back to `path.bak`.
## Result.ok -> { "bytes": PackedByteArray, "source": "main"|"backup" }; else Result.err.
func read_validated(path: String) -> Result:
	var main := _read_all(path)
	if not main.is_empty() and _validate.call(main):
		return Result.make_ok({ "bytes": main, "source": "main" })
	var bak := _read_all(path + ".bak")
	if not bak.is_empty() and _validate.call(bak):
		return Result.make_ok({ "bytes": bak, "source": "backup" })
	return Result.make_err("both main and backup are missing/corrupt: %s" % path)

func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")

## Best-effort copy of the raw current bytes to an arbitrary destination (pre-migration
## backup). No validation/rename — caller wants the original bytes preserved verbatim.
func copy_raw(src: String, dst: String) -> bool:
	var b := _read_all(src)
	if b.is_empty():
		return false
	_ensure_dir(dst)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(b)
	f.flush()
	f.close()
	return true

## Delete `path`, its `.bak`, and any leftover `.tmp`.
func delete(path: String) -> void:
	_remove(path)
	_remove(path + ".bak")
	_remove(path + ".tmp")

# --- internals ---

func _read_all(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _dir_of(path: String) -> String:
	return path.get_base_dir()

func _ensure_dir(path: String) -> void:
	var d := path.get_base_dir()
	if d != "" and not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
