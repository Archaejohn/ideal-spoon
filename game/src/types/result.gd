## result.gd — tiny Result/Ok/Err helper for loaders & validators (ARCHITECTURE §4 types/).
##
## Pure, engine-only. Lets validators report a precise, structured error (file / id /
## field / rule) instead of throwing, so the content pipeline can fail-fast with a clear
## message (ADR-0007 failure policy).
class_name Result
extends RefCounted

var ok: bool
var value           # payload on success
var error: String   # human-readable message on failure

static func make_ok(v = null) -> Result:
	var r := Result.new()
	r.ok = true
	r.value = v
	return r

static func make_err(msg: String) -> Result:
	var r := Result.new()
	r.ok = false
	r.error = msg
	return r

func is_ok() -> bool:
	return ok

func is_err() -> bool:
	return not ok
