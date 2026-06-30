## ids.gd — shared ID constants & enums (ADR-0003 / ARCHITECTURE §4 types/).
##
## Pure, engine-only. No scene-tree or autoload dependency. Holds the enum-valued
## story state (FinalChoice, EndingId) plus their stable string <-> enum mappings
## used by the save (ADR-0005 §d stores `story.choices` as enum STRINGS, never ints).
class_name Ids
extends RefCounted

## The A4-06 final choice. NONE = not yet chosen.
enum FinalChoice { NONE, SHARE, SLEEP, TAKE, WAKE }

## The resolved ending (A4-07). NONE = not yet reached.
enum EndingId { NONE, A, B, C, D }

const _FINAL_CHOICE_TO_STR := {
	FinalChoice.NONE: "NONE",
	FinalChoice.SHARE: "SHARE",
	FinalChoice.SLEEP: "SLEEP",
	FinalChoice.TAKE: "TAKE",
	FinalChoice.WAKE: "WAKE",
}

const _ENDING_TO_STR := {
	EndingId.NONE: "NONE",
	EndingId.A: "A",
	EndingId.B: "B",
	EndingId.C: "C",
	EndingId.D: "D",
}

static func final_choice_to_str(c: int) -> String:
	return _FINAL_CHOICE_TO_STR.get(c, "NONE")

static func final_choice_from_str(s: String) -> int:
	for k in _FINAL_CHOICE_TO_STR:
		if _FINAL_CHOICE_TO_STR[k] == s:
			return k
	return FinalChoice.NONE

static func ending_to_str(e: int) -> String:
	return _ENDING_TO_STR.get(e, "NONE")

static func ending_from_str(s: String) -> int:
	for k in _ENDING_TO_STR:
		if _ENDING_TO_STR[k] == s:
			return k
	return EndingId.NONE
