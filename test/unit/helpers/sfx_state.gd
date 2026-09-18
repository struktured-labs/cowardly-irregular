extends RefCounted

## Release every SFX player's STREAM between files.
##
## ⛔ EXISTS BECAUSE `sound_state.gd` IS THE MUSIC SURFACE AND THIS IS A DIFFERENT ONE. That helper
## restores _music_player, _current_area and _current_world_suffix and is correct; it says nothing
## about the thirteen SFX players, whose `stream` PERSISTS after a cue finishes. Measured 2026-09-18:
## six of eight guard files in this lane left a stream on a shared player, with volume_db and
## pitch_scale already clean — so a hand-written teardown covered the two fields its authors were
## reasoning about and not the third. One file already nulled a stream by hand, which is why the
## others' omission was invisible: the defence lived in the victim.
##
## The live consequence is an arm that proves a manifest hit by `stream != null` passing off the
## PREVIOUS file's stream — the same shape as play_voice timing a stale clip, which this lane fixed
## in the product and then reproduced in its own tests.
##
## Preloaded rather than `class_name` so a lane can use it with no --import.

## _music_player and _ambient_player belong to sound_state.gd. Pinned by
## test_a_new_audio_player_is_wired_like_its_siblings so a new music-side player cannot drift in here.
const MUSIC_OWNED := ["_music_player", "_ambient_player"]


## Derived from get_property_list(), not a hand-list — a player added tomorrow is covered on the day
## it is declared.
static func sfx_players(sm: Node) -> Array:
	var out: Array = []
	if sm == null:
		return out
	for prop in sm.get_property_list():
		var pname: String = str(prop.get("name", ""))
		if pname == "" or MUSIC_OWNED.has(pname):
			continue
		var v = sm.get(pname)
		if v is AudioStreamPlayer:
			out.append(pname)
	return out


## pitch_scale IS reset: the +/-5% jitter persists too, and 1.0 is universal. Measured with a planted
## `play_ui("menu_move")` — it left pitch=0.990 behind, so this is the same class as the stream and
## not thoroughness. volume_db is deliberately NOT touched: each channel has its own base, every
## file restores its own, and the probe measured all six already clean. Resetting them here would
## need a per-player base map that could go wrong in a direction nothing would notice.
static func release_streams() -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var sm: Node = (loop as SceneTree).root.get_node_or_null("SoundManager")
	if sm == null:
		return
	for pname in sfx_players(sm):
		var p = sm.get(pname)
		if p == null or not is_instance_valid(p):
			continue
		p.stop()
		p.stream = null
		p.pitch_scale = 1.0
