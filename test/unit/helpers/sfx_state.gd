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
## ⛔ THE CONSEQUENCE IS MEASURED, NOT HYPOTHETICAL, AND IT LANDS ON `CONTROL:` ARMS. Stubbing
## `play_attack_hit` to a bare `return` and running [polluter, victim] in one process:
##     without this helper   Failing 1   every victim CONTROL green, subject dead
##     with it               Failing 3   test_the_weapon_hit_no_longer_replaces_the_weakness_stinger
##                                       test_the_element_no_longer_replaces_the_weapon_hit
## Neither victim resets the stream — one clears cooldowns only, the other has no before_each — and
## both read `assert_true(_battle_player.stream != null, "CONTROL: ...")`. A leaked stream satisfies
## that exactly as a real cue does, so it turns every bare-presence control in the process into a
## tautology. The arms a leak disables first are the ones whose job is refusing a vacuum.
##
## Preloaded rather than `class_name` so a lane can use it with no --import.
##
## ⚠️ THIS MAKES ITS CALLERS BARRIERS, AND THAT IS A DELIBERATE TRADE. It releases EVERY sfx player,
## not just the ones its file drove — so a file wired to it also clears an UPSTREAM leaker's stream,
## and a probe running after it sees clean while the real polluter stays invisible. Kept because the
## alternative is a per-file list of players, and a cue routes to players its caller never names
## (play_battle reaches _flourish_player via the combo path). A derived release that over-cleans
## beats a hand-list that misses. Hunting a stream leak: probe BEFORE one of these files, not after.

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
## ⛔ THIS FUNCTION MUST NOT BE ABLE TO ABORT. Its callers place it FIRST in after_each, so every
## restore below it now depends on it returning — a line placed first buys abort-immunity for the
## lines under it only by having none of its own. Every step is total: get_main_loop and
## get_node_or_null do not throw, `sm.get(name)` yields null for an absent property rather than
## erroring, and each player is is_instance_valid-guarded before it is touched.
static func release_streams() -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var sm: Node = (loop as SceneTree).root.get_node_or_null("SoundManager")
	if sm == null:
		return
	## ⛔ THE RAMP, BEFORE THE PLAYERS. `_combo_step` is the SOURCE the per-play pitch bias derives
	## from, and resetting `pitch_scale` below clears only what it RENDERED — a helper that is a
	## barrier for the rendered field and silent about the field feeding it. Reported by cowir-music
	## 2026-09-18: test_group_attack_cue_survives_its_own_hits ends with get_combo_pitch_bias() at
	## 1.0300 against a 1.0000 fresh process, and neither barrier cleared it. No victim today — all
	## three readers reset before their first read — so this closes a latch rather than a defect.
	if sm.has_method("reset_hit_chain"):
		sm.reset_hit_chain()
	for pname in sfx_players(sm):
		var p = sm.get(pname)
		if p == null or not is_instance_valid(p):
			continue
		p.stop()
		p.stream = null
		p.pitch_scale = 1.0
