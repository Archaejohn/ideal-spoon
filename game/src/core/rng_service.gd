## rng_service.gd — the single seeded RNG (ARCHITECTURE §7.1, ADR-0009).
##
## One master seed (set at New Game, saved in GameState). Vends named, independently
## seeded substreams ("battle","ai","loot","dance","encounter","story") so unrelated
## systems never perturb each other's reproducibility. Each stream tracks a cursor (#
## of draws); export/import the master seed + every cursor so checkpoints and ending
## replays continue the EXACT same sequence (ADR-0005 §d / ADR-0006).
##
## Determinism contract (ADR-0009): every high-level draw consumes EXACTLY ONE underlying
## randi() of the stream's RandomNumberGenerator, so set_cursor(n) can fast-forward by
## replaying n draws and reproduce subsequent values bit-for-bit. Outcome logic uses the
## integer API; randf() is cosmetic-only.
extends Node

## The six cursor-saved streams (ADR-0009).
const SAVED_STREAMS := ["battle", "ai", "loot", "dance", "encounter", "story"]

var _master_seed: int = 0
var _streams: Dictionary = {}   # name -> RngStream

## A single named substream. RefCounted so logic classes can hold/inject it (ADR-0009).
class RngStream:
	extends RefCounted

	var _rng: RandomNumberGenerator
	var _base_seed: int
	var _cursor: int = 0

	func _init(base_seed: int) -> void:
		_base_seed = base_seed
		_rng = RandomNumberGenerator.new()
		_rng.seed = base_seed

	# Every draw funnels through here: one underlying randi, cursor +1.
	func _next_u32() -> int:
		_cursor += 1
		return _rng.randi()

	func randi() -> int:
		return _next_u32()

	## Inclusive integer in [a, b]. Deterministic; one underlying draw.
	func randi_range(a: int, b: int) -> int:
		if b <= a:
			return a
		var span := b - a + 1
		return a + int(_next_u32() % span)

	## Integer probability in permille (0..1000). p<=0 => never, p>=1000 => always.
	func chance_permille(p: int) -> bool:
		var roll := int(_next_u32() % 1000)   # 0..999
		return roll < p

	## Integer-weighted index into `weights` (EnemyBrain / dance tables). One draw.
	func weighted_pick(weights: Array) -> int:
		var total := 0
		for w in weights:
			total += maxi(0, int(w))
		if total <= 0:
			return 0
		var roll := int(_next_u32() % total)
		var acc := 0
		for i in weights.size():
			acc += maxi(0, int(weights[i]))
			if roll < acc:
				return i
		return weights.size() - 1

	## COSMETIC-only float in [0,1). Derived from one randi so cursor stays exact.
	func randf() -> float:
		return float(_next_u32()) / 4294967296.0

	func get_cursor() -> int:
		return _cursor

	## Restore: reseed to base and fast-forward by replaying n draws (exact).
	func set_cursor(n: int) -> void:
		_rng.seed = _base_seed
		_cursor = 0
		for _i in maxi(0, n):
			_next_u32()

# --- service API ---

func seed_run(master_seed: int) -> void:
	_master_seed = master_seed
	_streams.clear()
	# Pre-create the saved streams so cursors round-trip even if never drawn.
	for name in SAVED_STREAMS:
		_streams[name] = RngStream.new(_derive_seed(master_seed, name))

func master_seed() -> int:
	return _master_seed

func stream(name: String) -> RngStream:
	if not _streams.has(name):
		_streams[name] = RngStream.new(_derive_seed(_master_seed, name))
	return _streams[name]

## Stable per-stream seed derived from the master seed + stream name (ADR-0009).
func _derive_seed(master: int, name: String) -> int:
	return hash("%d:%s" % [master, name])

func export_state() -> Dictionary:
	var cursors := {}
	for name in SAVED_STREAMS:
		cursors[name] = stream(name).get_cursor()
	return { "master_seed": _master_seed, "cursors": cursors }

func import_state(d: Dictionary) -> void:
	seed_run(int(d.get("master_seed", 0)))
	var cursors: Dictionary = d.get("cursors", {})
	for name in cursors:
		stream(name).set_cursor(int(cursors[name]))
