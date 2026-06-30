## save_serializer.gd — the on-disk envelope around a GameState payload (ADR-0005 §d).
##
## Pure, headless (RefCounted, no scene tree). Wraps the dict produced by
## `GameState.to_dict()` in a validated envelope and reverses it on read:
##
##   {
##     "magic":        "AETHER",          # format sentinel
##     "save_version":  <int>,            # mirrors payload.save_version (build-format check)
##     "checksum":     "<sha256 hex>",    # hash over MAGIC + version + payload JSON
##     "payload":      "<json string>"    # the GameState dict, serialized verbatim
##   }
##
## The payload is stored as an exact JSON *string* and the checksum is taken over that
## same string (plus magic+version), so validation is independent of dictionary key
## ordering and detects ANY tamper of magic, version, or payload bytes.
class_name SaveSerializer
extends RefCounted

const MAGIC := "AETHER"
## Current on-disk format version. Mirrors GameState.SAVE_VERSION; bumped with the schema.
const CURRENT_VERSION := 1

## Wrap a GameState payload dict into the validated on-disk envelope (as UTF-8 bytes).
static func encode(payload: Dictionary) -> PackedByteArray:
	var version := int(payload.get("save_version", CURRENT_VERSION))
	var payload_json := JSON.stringify(payload)
	var envelope := {
		"magic": MAGIC,
		"save_version": version,
		"checksum": _checksum(version, payload_json),
		"payload": payload_json,
	}
	return JSON.stringify(envelope).to_utf8_buffer()

## Validate the envelope and return the inner GameState payload dict.
## Result.ok -> Dictionary payload ; Result.err -> human-readable reason.
static func decode(bytes: PackedByteArray) -> Result:
	if bytes.is_empty():
		return Result.make_err("empty save bytes")
	var text := bytes.get_string_from_utf8()
	var env: Variant = JSON.parse_string(text)
	if typeof(env) != TYPE_DICTIONARY:
		return Result.make_err("envelope is not a JSON object")
	var envelope: Dictionary = env
	if str(envelope.get("magic", "")) != MAGIC:
		return Result.make_err("bad magic (not an Aetherbound save)")
	if not (envelope.has("save_version") and envelope.has("checksum") and envelope.has("payload")):
		return Result.make_err("envelope missing required fields")
	var version := int(envelope.get("save_version", -1))
	var payload_json := str(envelope.get("payload", ""))
	var expected := _checksum(version, payload_json)
	if str(envelope.get("checksum", "")) != expected:
		# Detects payload tamper AND tampered magic/version (both are in the hash scope).
		return Result.make_err("checksum mismatch (corrupt or tampered save)")
	var parsed: Variant = JSON.parse_string(payload_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return Result.make_err("payload is not a JSON object")
	return Result.make_ok(parsed)

## Cheap structural check used by AtomicFileIO to choose main vs backup.
static func is_valid(bytes: PackedByteArray) -> bool:
	return decode(bytes).is_ok()

## SHA-256 hex over the magic + version + payload string. String tamper => different hash.
static func _checksum(version: int, payload_json: String) -> String:
	return ("%s:%d:%s" % [MAGIC, version, payload_json]).sha256_text()
