extends GutTest

## struktured 2026-07-17: "I feel like music randomly dropped in volume
## during a battle" + "battle speed should forever be visible."
##
## (1) Night fell mid-battle and the night music hush (LPF+reverb) applied
##     to the battle track — an invisible-cause volume drop. Battle audio is
##     now mood-exempt: band changes skip the hush in BATTLE state, battle
##     start strips hush+crickets, exploration return re-syncs from the clock.
## (2) The speed indicator auto-faded to 0.3 alpha at 1x AND sat top-left
##     under the ENEMIES panel. Now: full opacity forever, bottom-left above
##     the turn-order box.

const GAME_LOOP := "res://src/GameLoop.gd"
const SCENE := "res://src/battle/BattleScene.gd"


func _body_of(path: String, fn: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	var i := src.find("func %s" % fn)
	assert_gt(i, -1, "%s must exist" % fn)
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else 8000)


func test_band_change_skips_hush_during_battle() -> void:
	var body := _body_of(GAME_LOOP, "_on_time_of_day_changed")
	assert_true("current_state != LoopState.BATTLE" in body,
		"night falling mid-fight must NOT hush battle music — the invisible volume drop")


func test_battle_start_strips_night_mood() -> void:
	var body := _body_of(GAME_LOOP, "_start_battle_async")
	assert_true("set_night_music_effects(false)" in body,
		"battle entry strips the hush — a fight started at night must sound full-energy")
	assert_true("set_night_ambience(false)" in body,
		"crickets don't play over battle music")


func test_exploration_return_resyncs_from_clock() -> void:
	var body := _body_of(GAME_LOOP, "_start_exploration")
	# 2026-07-18: re-sync DEFERRED 3.5s past the victory jingle (hushing the fanfare mid-note read as a defeat sting — cowir-music msg 2784 mechanism); conditions re-checked at fire time.
	assert_true("set_night_music_effects(true)" in body and "create_timer(3.5)" in body,
		"night hush re-sync must be deferred past the victory jingle, re-checking state at fire time")
	assert_true("set_night_music_effects(false)" in body,
		"day-side re-sync stays immediate — nothing to hush")
	assert_true("set_night_ambience(night_now and outdoor_scene)" in body,
		"crickets only outdoors at night — interiors/caves stay silent")


func test_speed_indicator_never_fades() -> void:
	var body := _body_of(SCENE, "_animate_speed_change")
	assert_false("0.3, 0.5" in body,
		"the 1x auto-fade to 0.3 alpha is gone — battle speed is forever visible")
	assert_true("panel.modulate.a = 1.0" in body, "full opacity, always")


func test_speed_indicator_bottom_left() -> void:
	var body := _body_of(SCENE, "_create_speed_indicator")
	assert_true("get_viewport_rect().size.y - 222" in body,
		"indicator sits bottom-left above the turn-order box — top-left buried it under the ENEMIES panel")
