## log.gd — leveled, ring-buffered local logging (ARCHITECTURE §2 autoload #1).
##
## Offline & quiet: writes ONLY to the local console + an in-memory ring buffer.
## Never opens a socket, never touches the network (DoD #8). Registered as the `Log`
## autoload. Logic modules may call it, but the core logic classes themselves avoid it
## to stay headless-pure; it is mainly for coordinators/boot/UI.
extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

## Minimum level that is emitted to the console. The ring buffer keeps everything.
var min_level: int = Level.DEBUG
var _ring: Array[String] = []
var _ring_max: int = 512

const _LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]

func debug(msg: String, tag: String = "") -> void:
	_emit(Level.DEBUG, msg, tag)

func info(msg: String, tag: String = "") -> void:
	_emit(Level.INFO, msg, tag)

func warn(msg: String, tag: String = "") -> void:
	_emit(Level.WARN, msg, tag)

func error(msg: String, tag: String = "") -> void:
	_emit(Level.ERROR, msg, tag)

func _emit(level: int, msg: String, tag: String) -> void:
	var prefix := "[%s]" % _LEVEL_NAMES[level]
	if tag != "":
		prefix += "[%s]" % tag
	var line := "%s %s" % [prefix, msg]
	_ring.append(line)
	if _ring.size() > _ring_max:
		_ring.pop_front()
	if level >= min_level:
		if level >= Level.ERROR:
			push_error(line)
		elif level >= Level.WARN:
			push_warning(line)
		else:
			print(line)

## Returns a copy of the in-memory log (for QA dumps / tests). No network.
func tail(n: int = 50) -> Array[String]:
	var start := maxi(0, _ring.size() - n)
	return _ring.slice(start)

func clear() -> void:
	_ring.clear()
