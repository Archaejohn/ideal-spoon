## flag_view.gd — typed read facade over FlagStore (ARCHITECTURE §7.3a, ADR-0003).
##
## Exposes the gating flags the EndingResolver reads as REAL typed bool properties (so the
## resolver compiles honestly against this facade) and computes the two DERIVED flags
## (WARDEN_TRUTH_WHOLE, FACTIONS_UNITED) on read from the underlying flags + the frozen
## UNITY. Derived values are NEVER stored — there is exactly one source of truth (ADR-0003
## §3.3). Build from a FlagStore (`from_store`) or a plain dict (`from_dict`, used by
## ReplayPlanner's synthesized states).
class_name FlagView
extends RefCounted

## The underlying boolean flags that feed the resolver / derived methods. Changing any of
## these alters the computed ending, so FlagStore must FREEZE exactly these after
## lock_endings() (A3-13). Non-gating flavor flags (e.g. PIGGY_RECRUITED, set at A3-13b
## AFTER the lock) are intentionally NOT here and remain writable post-lock (ADR-0003).
const GATING_FLAGS := [
	"KESTREL_RECRUITED",
	"ORDER_ALLIED",
	"TRUTH_SHARED",
	"ROOKWISE_RECRUITED",
	"MARROW_REDEEMED",
	"BRAMBLE_SHARD_DEPARTURE",
	"BRAMBLE_SHARD_PROMISE",
]

# --- gating underlying flags (read by the resolver / derived methods) ---
var KESTREL_RECRUITED: bool = false
var ORDER_ALLIED: bool = false
var TRUTH_SHARED: bool = false
var ROOKWISE_RECRUITED: bool = false
var MARROW_REDEEMED: bool = false
var BRAMBLE_SHARD_DEPARTURE: bool = false
var BRAMBLE_SHARD_PROMISE: bool = false
var unity: int = 0

## WARDEN_TRUTH_WHOLE — computed-on-read (04 §3.3, verbatim):
##   (both shards) OR (Rookwise AND at least one shard).
func warden_truth_whole() -> bool:
	return (BRAMBLE_SHARD_DEPARTURE and BRAMBLE_SHARD_PROMISE) \
		or (ROOKWISE_RECRUITED and (BRAMBLE_SHARD_DEPARTURE or BRAMBLE_SHARD_PROMISE))

## FACTIONS_UNITED — computed-on-read (04 §3.3, verbatim):
##   unity>=5 AND Kestrel AND (Order allied OR truth shared).
func factions_united() -> bool:
	return unity >= 5 and KESTREL_RECRUITED and (ORDER_ALLIED or TRUTH_SHARED)

static func from_store(store) -> FlagView:
	var v := FlagView.new()
	v.KESTREL_RECRUITED = store.get_flag("KESTREL_RECRUITED")
	v.ORDER_ALLIED = store.get_flag("ORDER_ALLIED")
	v.TRUTH_SHARED = store.get_flag("TRUTH_SHARED")
	v.ROOKWISE_RECRUITED = store.get_flag("ROOKWISE_RECRUITED")
	v.MARROW_REDEEMED = store.get_flag("MARROW_REDEEMED")
	v.BRAMBLE_SHARD_DEPARTURE = store.get_flag("BRAMBLE_SHARD_DEPARTURE")
	v.BRAMBLE_SHARD_PROMISE = store.get_flag("BRAMBLE_SHARD_PROMISE")
	v.unity = store.unity()
	return v

## Build from a plain boolean dict + a unity int (ReplayPlanner synthesized states).
static func from_dict(flags: Dictionary, unity_value: int) -> FlagView:
	var v := FlagView.new()
	v.KESTREL_RECRUITED = bool(flags.get("KESTREL_RECRUITED", false))
	v.ORDER_ALLIED = bool(flags.get("ORDER_ALLIED", false))
	v.TRUTH_SHARED = bool(flags.get("TRUTH_SHARED", false))
	v.ROOKWISE_RECRUITED = bool(flags.get("ROOKWISE_RECRUITED", false))
	v.MARROW_REDEEMED = bool(flags.get("MARROW_REDEEMED", false))
	v.BRAMBLE_SHARD_DEPARTURE = bool(flags.get("BRAMBLE_SHARD_DEPARTURE", false))
	v.BRAMBLE_SHARD_PROMISE = bool(flags.get("BRAMBLE_SHARD_PROMISE", false))
	v.unity = unity_value
	return v
