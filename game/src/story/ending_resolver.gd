## ending_resolver.gd — resolveEnding (ADR-0003, mirrors 04 §5 EXACTLY).
##
## Pure & static. `v` is a FlagView (typed facade) so access is honest while the LOGIC is
## line-for-line with story doc 04 §5. Pinned by the golden test (ADR-0009). Reads ONLY
## gating flags via the facade; non-gating flags (Piggy/emotional/BRAMBLE_SACRIFICE) never
## appear here.
##
## Offered options: Sleep/Take ALWAYS; Share iff FACTIONS_UNITED; Wake iff
## WARDEN_TRUTH_WHOLE and ROOKWISE_RECRUITED and MARROW_REDEEMED.
class_name EndingResolver
extends RefCounted

const SHARE := Ids.FinalChoice.SHARE
const SLEEP := Ids.FinalChoice.SLEEP
const TAKE := Ids.FinalChoice.TAKE
const WAKE := Ids.FinalChoice.WAKE

static func factions_united(v: FlagView) -> bool:
	return v.factions_united()

static func can_wake(v: FlagView) -> bool:
	return v.warden_truth_whole() and v.ROOKWISE_RECRUITED and v.MARROW_REDEEMED

static func offered_options(v: FlagView) -> Array:
	var opts := [SLEEP, TAKE]            # always available
	if factions_united(v):
		opts.append(SHARE)
	if can_wake(v):
		opts.append(WAKE)
	return opts

static func resolve(v: FlagView, final_choice: int) -> int:
	if final_choice == SHARE and factions_united(v):
		return Ids.EndingId.A
	if final_choice == SLEEP:
		return Ids.EndingId.B
	if final_choice == TAKE:
		return Ids.EndingId.C
	if final_choice == WAKE and can_wake(v):
		return Ids.EndingId.D
	# SHARE/WAKE are never presented unless their gate is true, so this is unreachable.
	assert(false, "resolveEnding reached an unoffered choice")
	return Ids.EndingId.B
