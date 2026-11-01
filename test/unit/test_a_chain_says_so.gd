extends GutTest

## struktured 2026-11-01 on chains: "too abrupt, it just jumps into the 2nd one, no warning, no preamble, not even obvious
## it's a chain battle". The first link names the chain, every link carries "Chain N/M", and between links a card says who
## is coming and what the breather gave back -- skippable, wall-clock, and the real iris path still runs.

const BATTLE := "res://src/battle/BattleScene.tscn"
## BattleScene declares no class_name; a bare reach to it is a PARSE error that stops this whole file running.
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const BattleState := preload("res://test/unit/helpers/battle_state.gd")

var _saved_scale = null
var _guard: RefCounted = null


func before_each() -> void:
	_saved_scale = GameState.text_size_scale
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _guard != null:
		_guard.restore()
	BattleManager.chain_link = 0
	BattleManager.chain_total = 0
	BattleManager.chain_groups = 1


func test_the_banner_names_the_chain_and_its_length() -> void:
	assert_string_contains(BattleSceneScript.chain_banner_text(1, 2), "CHAIN ×2", "battle one does not say how long the chain is")
	assert_eq(BattleSceneScript.chain_banner_text(2, 2), "CHAIN 2/2", "a later link does not say which one it is")


func _scene() -> Node:
	var s = load(BATTLE).instantiate()
	add_child_autofree(s)
	return s


func test_a_chain_battle_shows_its_tag_and_banner_and_a_lone_battle_does_not() -> void:
	var lone := _scene()
	lone._show_chain_intro(0, 0)
	assert_null(lone.find_child("ChainTag", true, false), "CONTROL: an ordinary battle grew a chain tag")
	var one_link := _scene()
	one_link._show_chain_intro(1, 1)
	assert_null(one_link.find_child("ChainTag", true, false), "a chain that fit one battle claimed to be a chain of battles")
	var s := _scene()
	s._show_chain_intro(1, 2)
	var tag := s.find_child("ChainTag", true, false) as Label
	assert_not_null(tag, "a chain battle has no Chain N/M tag")
	assert_eq(tag.text if tag else "", "Chain 1/2")
	var banner := s.find_child("ChainBanner", true, false) as Label
	assert_not_null(banner, "the first link did not announce the chain")
	assert_string_contains(banner.text if banner else "", "CHAIN ×2")


func test_the_game_loop_tells_each_battle_which_link_it_is() -> void:
	var gl = load("res://src/GameLoop.gd").new()
	autofree(gl)
	gl._chain_total = 2
	gl._chain_index = 1
	gl._chain_engaged = 1
	gl._publish_chain_to_battle()
	assert_eq([BattleManager.chain_link, BattleManager.chain_total], [1, 2], "battle one was not told it is link 1 of 2")
	gl._end_chain()
	gl._publish_chain_to_battle()
	assert_eq([BattleManager.chain_link, BattleManager.chain_total], [0, 0], "an ordinary battle after a chain still thinks it is one")


func test_end_battle_forgets_the_chain_link() -> void:
	BattleManager.chain_link = 2
	BattleManager.chain_total = 2
	var none: Array[Combatant] = []
	BattleManager.player_party = none
	BattleManager.enemy_party = none.duplicate()
	BattleManager.all_combatants = none.duplicate()
	BattleManager.end_battle(false)
	assert_eq([BattleManager.chain_link, BattleManager.chain_total], [0, 0], "the next battle would inherit a chain tag")


func test_the_breather_heals_the_living_by_its_fraction() -> void:
	var up := Combatant.new()
	up.combatant_name = "Up"
	up.max_hp = 100
	up.current_hp = 10
	up.max_mp = 40
	up.current_mp = 0
	up.is_alive = true
	add_child_autofree(up)
	var down := Combatant.new()
	down.combatant_name = "Down"
	down.max_hp = 100
	down.current_hp = 0
	down.is_alive = false
	add_child_autofree(down)
	var got: Dictionary = BattleManager.apply_chain_breather([up, down])
	var hp := int(100 * BattleManager.CHAIN_BREATHER_FRACTION)
	assert_eq(up.current_hp, 10 + hp, "the breather did not restore its fraction of max HP")
	assert_eq(int(got.get("Up", {}).get("hp", -1)), hp, "the card would report a different number than was healed")
	assert_false(got.has("Down"), "the breather raised the dead")
	assert_string_contains(ChainCard.detail_for(got), "+%d HP" % hp, "the card does not show what the breather gave")


func _card(hold: float) -> ChainCard:
	var c := ChainCard.new()
	c.hold_sec = hold
	c.title_text = ChainCard.title_for(2, 2)
	add_child_autofree(c)
	return c


func test_the_card_holds_by_the_wall_clock_and_confirm_skips_it() -> void:
	var fired := [false]
	var c := _card(30.0)
	c.finished.connect(func(): fired[0] = true)
	await get_tree().process_frame
	assert_false(fired[0], "CONTROL: a 30 s card finished on its own")
	c._t0 -= int(ChainCard.SKIP_DEBOUNCE_SEC * 1000.0) + 50
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	c._input(ev)
	assert_true(fired[0], "Confirm did not skip the card")
	var timed := [false]
	var t := _card(0.05)
	t.finished.connect(func(): timed[0] = true)
	var t0 := Time.get_ticks_msec()
	while not timed[0] and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_true(timed[0], "a card did not finish on its own wall clock")


func test_the_card_title_grows_with_the_text_and_still_fits() -> void:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var presets: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(presets.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS did not resolve, so this loop would visit nothing")
	var last := 0
	for scale in presets:
		GameState.text_size_scale = float(scale)
		var c := _card(30.0)
		var title := c.find_child("Title", true, false) as Label
		var px := title.get_theme_font_size("font_size")
		assert_gte(px, last, "the card title did not grow at Text Size %s" % str(scale))
		last = px
		assert_lte(title.get_combined_minimum_size().x, 1280.0, "the card title is wider than the screen at Text Size %s" % str(scale))
	GameState.text_size_scale = 1.0
	var at_one := _card(30.0).find_child("Title", true, false) as Label
	GameState.text_size_scale = float(presets.max())
	var at_max := _card(30.0).find_child("Title", true, false) as Label
	assert_gt(at_max.get_theme_font_size("font_size"), at_one.get_theme_font_size("font_size"), "the card ignores Text Size")


const _LoopStub := """
extends "res://src/GameLoop.gd"
var started: Array = []
var overlay_alpha_at_swap: float = -1.0
var card_titles: Array = []
func _wait_for_confirm_victory() -> void:
	pass
func _start_battle_async(specific_enemies: Array = [], is_encounter: bool = false) -> bool:
	overlay_alpha_at_swap = BattleTransition._overlay.modulate.a
	started.append(specific_enemies.duplicate())
	return true
func _return_to_exploration(force_battle_teardown: bool = false) -> void:
	_end_chain()
func _process(_d: float) -> void:
	var c = get_node_or_null("ChainCard")
	if c and not c.title_text in card_titles:
		card_titles.append(c.title_text)
"""


func test_between_links_the_card_shows_then_the_real_iris_runs() -> void:
	var s := GDScript.new()
	s.source_code = _LoopStub
	assert_eq(s.reload(), OK, "CONTROL: the GameLoop stub compiles")
	var gl: Node = s.new()
	add_child_autofree(gl)
	gl.chain_card_seconds = 0.05
	gl._chain_links = [[["bat", "bat"]]]
	gl._chain_total = 2
	gl._chain_index = 1
	gl._chain_engaged = 1
	await gl._on_battle_ended(true)
	assert_eq(gl.started, [["bat", "bat"]], "the second link did not start")
	assert_eq(gl.card_titles, [ChainCard.title_for(2, 2)], "no card announced link 2 of 2 between the battles")
	assert_almost_eq(gl.overlay_alpha_at_swap, 1.0, 0.05, "the battles were swapped in plain sight: the iris had not closed")
	assert_lt(BattleTransition._overlay.modulate.a, 0.05, "the iris never opened on the second battle")
	assert_null(gl.get_node_or_null("ChainCard"), "the card outlived the beat")
