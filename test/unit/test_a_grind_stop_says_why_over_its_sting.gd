extends GutTest

## An automatic autogrind stop plays TWO cues in one frame: _play_grind_stop_sfx's reason cue (hp / death / corruption)
## and _show_grind_stop_notification's attention sting. Both went to _ui_player, so the sting replaced the reason before a
## sample of it was heard and every automatic stop sounded identical. The sting now rides its own voice (play_alert).

const GL_SRC := "res://src/GameLoop.gd"
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const STING := "autogrind_stop_sting"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	var sm: Node = _sm()
	if sm != null:
		sm._sfx_cooldowns.clear()


func after_each() -> void:
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm != null:
		sm._sfx_cooldowns.clear()


## Reason cue first, then the banner, in GameLoop's own order (both stop paths call them back to back).
func _stop(reason: String) -> Dictionary:
	var sm: Node = _sm()
	var gl: Node = load(GL_SRC).new()
	gl._play_grind_stop_sfx(reason)
	var reason_stream = sm._ui_player.stream
	gl._show_grind_stop_notification(reason)
	var out := {"reason": reason_stream, "ui_after": sm._ui_player.stream, "alert": sm._alert_player.stream}
	gl.free()
	return out


func test_the_reason_cue_survives_the_sting() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	for reason in ["HP threshold reached", "Party member died", "Corruption limit reached", "Max battles reached"]:
		var r := _stop(reason)
		assert_not_null(r["reason"], "CONTROL: '%s' put a reason cue on the UI voice" % reason)
		assert_true(r["ui_after"] == r["reason"],
			"'%s': the stop sting replaced the reason cue on _ui_player, so the player never hears why the grind stopped" % reason)
		sm._sfx_cooldowns.clear()


func test_the_sting_still_sounds_on_its_own_voice() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(STING), "CONTROL: %s must be a registered cue" % STING)
	var r := _stop("HP threshold reached")
	assert_not_null(r["alert"], "the attention sting must still play on an automatic stop")
	assert_true(str((r["alert"] as Resource).resource_path).ends_with(STING + ".ogg"),
		"the alert voice must be carrying the sting, got %s" % str(r["alert"]))


func test_a_manual_stop_has_no_sting_and_that_is_the_control() -> void:
	## The player pressed stop and already knows; the banner and sting stay off, only the reason cue plays.
	var sm: Node = _sm()
	if sm == null:
		return
	var r := _stop("Manual stop")
	assert_not_null(r["reason"], "CONTROL: a manual stop still plays grind_stop_manual")
	assert_null(r["alert"], "a manual stop must not sound the attention sting")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm.has_method("play_alert"), "SoundManager has no play_alert — the sting's own voice is gone")
	for member_name in ["_ui_player", "_alert_player", "_sfx_cooldowns", "_sfx_manifest"]:
		assert_true(sm.get(member_name) != null, "SoundManager has no %s — this file reaches for it directly" % member_name)
	var gl: Node = load(GL_SRC).new()
	for m in ["_play_grind_stop_sfx", "_show_grind_stop_notification"]:
		assert_true(gl.has_method(m), "GameLoop has no %s — this file drives it" % m)
	gl.free()
