extends GutTest

## Undoing a queued action played on the UI channel (-16 dB) while the press it undoes plays on the battle channel (-6 dB), and the asset is 9 dB quieter again.
## Measured: -38.9 dB against the press's -19.4 — a ~20 dB gap, so the undo was inaudible over battle music while the press was not.

const BASELINE := "res://test/fixtures/sfx_whoop_baseline.json"
const MENU_SRC := "res://src/ui/Win98Menu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const PRESS := "advance_generic_3"
const UNDO := "advance_undo"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _rms(key: String) -> float:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	if not (parsed is Dictionary):
		return -999.0
	var cues: Dictionary = (parsed as Dictionary).get("cues", {})
	return float((cues.get(key, {}) as Dictionary).get("rms_db", -999.0))


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()


func test_the_undo_is_on_the_queue_correction_voice_not_the_ui_channel() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	sm._ui_player.stream = null
	sm.play_advance_state(UNDO)
	assert_null(sm._ui_player.stream, "the undo is back on the UI channel, 10 dB below the press it answers")
	assert_true(sm._refuse_player.stream != null and str(sm._refuse_player.stream.resource_path).contains(UNDO),
		"the undo did not reach the queue-correction voice")


func test_the_undo_does_not_cut_the_press_it_undoes() -> void:
	# You undo while the press cue is still ringing — a job's fifth rung runs up to 3.6s.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_battle("advance_cleric_5")
	var press = sm._battle_player.stream
	assert_true(press != null and str(press.resource_path).contains("advance_cleric_5"),
		"CONTROL: the press cue must be sounding, or 'not cut' is vacuous")
	sm.play_advance_state(UNDO)
	assert_eq(sm._battle_player.stream, press, "the undo cut the press cue it was answering")


func test_the_undo_lands_within_earshot_of_the_press() -> void:
	# Effective level = the recorded rms of the asset + the level the player is actually set to.
	var sm: Node = _sm()
	if sm == null:
		return
	var undo_rms := _rms(UNDO)
	var press_rms := _rms(PRESS)
	assert_gt(undo_rms, -900.0, "CONTROL: %s is not whoop-pinned, so its level is unrecorded" % UNDO)
	assert_gt(press_rms, -900.0, "CONTROL: %s is not whoop-pinned, so the comparison has no reference" % PRESS)
	if undo_rms < -900.0 or press_rms < -900.0:
		return
	sm.play_battle(PRESS)
	var press_level: float = sm._battle_player.volume_db
	sm.play_advance_state(UNDO)
	var undo_level: float = sm._refuse_player.volume_db
	var gap: float = (undo_rms + undo_level) - (press_rms + press_level)
	assert_gt(gap, -6.0,
		"the undo is %.1f dB under the press it undoes — it was -19.5 dB on the UI channel and inaudible over music" % gap)
	assert_lt(gap, 1.0, "the undo is now LOUDER than the press it answers (%.1f dB) — a correction should not dominate" % gap)


func test_the_menu_routes_the_undo_through_the_advance_family() -> void:
	var code := GdSource.code_of(MENU_SRC)
	var at := code.find("func _play_undo_sound(")
	assert_gt(at, -1, "CONTROL: the undo function must survive the comment strip")
	if at == -1:
		return
	var end := code.find("\nfunc ", at + 1)
	var body := code.substr(at, (end - at) if end > at else -1)
	assert_true(body.contains('play_advance_state("advance_undo")'), "the undo no longer routes through the advance family")
	assert_false(body.contains('play_ui("advance_undo")'), "the undo is back on play_ui — 10 dB below the press, on a player menu blips also use")
