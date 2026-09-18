extends RefCounted

## Put the music autoload back to the state a fresh process starts in.
##
## ⛔ EXISTS BECAUSE `stop_music()` READS AS A FULL RESET AND IS NOT ONE. It clears
## `_music_playing`, `_current_music`, the crossfade and the stinger resume — and leaves
## `_current_area` and `_current_world_suffix` exactly where the last area put them, and leaves the
## player's `volume_db` wherever a fade dragged it. Seven music-subject files leaked through a
## teardown that looked complete, and one of the seven restored `_current_area` and missed the
## suffix: a hand-written teardown covers the fields its author happened to think of.
##
## 🔑 THE TWO LIVE CONSEQUENCES, both measured 2026-09-17:
##   a foreign `_current_world_suffix` hands the next file another world's SFX prefix (`w3_`, `w5_`)
##   `_current_area` + `_music_playing` together satisfy play_area_music's early return, so a later
##   call for that same area returns before starting anything and its bed never plays
##
## ⛔ THIS IS A BARRIER, NOT A CONDUIT, AND THE 26 FILES CALLING IT DEPEND ON THAT.
## It restores DECLARED DEFAULTS (`_current_area = ""`, `_current_world_suffix = "medieval"` —
## SoundManager.gd's own initialisers), never a snapshot of what the caller inherited. Two
## consequences a reader needs and neither is visible from the call site:
##
##   ✅ nothing to snapshot means no setup line an abort can skip, so it is safe FIRST in a hook
##      (and every write below is guarded for the same reason — see restore()).
##   ⛔ a file wired to this CLEANS UP AFTER AN UPSTREAM LEAKER, so a probe running DOWNSTREAM of it
##      reports clean about a tree that is not. "This file no longer leaks" and "the suite is clean"
##      are independent claims, and this helper only ever supports the first.
##
## Sibling helpers chose differently and a teardown's semantics are not interchangeable:
## `autobattle_profiles.gd` and `autogrind_state.gd` restore the PRIOR SNAPSHOT (conduits — they
## cannot mask an upstream leaker and do not clean up after one, and they must run LAST because they
## restore rather than clear). `battle_state.dirty_fields()` is an ORACLE: read-only, diffed against
## a fresh instance, for probes. Pick by which claim you need, not by which is nearest.
##
## Preloaded rather than `class_name` on purpose: no `--import` needed for a lane to use it.

## Every field a test can move, in the order the autoload wants them — reset_danger re-applies a
## live corruption envelope, so corruption is cleared after it rather than before.
static func restore() -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var sm: Node = (loop as SceneTree).root.get_node_or_null("SoundManager")
	if sm == null:
		return
	if sm.has_method("stop_music"):
		sm.stop_music()
	if sm.has_method("stop_ambient"):
		sm.stop_ambient()
	if sm.has_method("reset_danger"):
		sm.reset_danger()
	if sm.has_method("reset_corruption"):
		sm.reset_corruption()
	## ⛔ EVERY WRITE GUARDED, BECAUSE THIS CALL IS THE FIRST LINE OF ALL 26 HOOKS THAT USE IT.
	## A GDScript error aborts its enclosing function, so an abort here skips every teardown line
	## BELOW it in each of those files — one rename multiplied 26 times, and each file stays green.
	## @cowir-controller's rule: a teardown line placed first must be one that cannot abort.
	if "_current_area" in sm:
		sm._current_area = ""
	if "_current_world_suffix" in sm:
		sm._current_world_suffix = "medieval"
	## Last, because a completed fade-out leaves the level at -40 and nothing above lifts it.
	if "_music_player" in sm and sm._music_player and "_music_base_db" in sm:
		sm._music_player.volume_db = sm._music_base_db
		sm._music_player.pitch_scale = 1.0
