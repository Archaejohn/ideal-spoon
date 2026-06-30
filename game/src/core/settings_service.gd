## settings_service.gd — volume / text speed / accessibility (ARCHITECTURE §2 autoload #5).
##
## Persisted SEPARATELY from the save (settings.cfg) so a save problem never loses prefs
## and vice-versa (ADR-0005 §b). Phase-3 stub: holds defaults in memory; disk persistence
## lands with SaveManager's file layer. No network.
extends Node

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var text_speed: int = 2                 # 0 slow .. 4 instant
var reduce_motion: bool = false
var high_contrast: bool = false

func to_dict() -> Dictionary:
	return {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"text_speed": text_speed,
		"reduce_motion": reduce_motion,
		"high_contrast": high_contrast,
	}

func from_dict(d: Dictionary) -> void:
	master_volume = float(d.get("master_volume", master_volume))
	music_volume = float(d.get("music_volume", music_volume))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	text_speed = int(d.get("text_speed", text_speed))
	reduce_motion = bool(d.get("reduce_motion", reduce_motion))
	high_contrast = bool(d.get("high_contrast", high_contrast))
