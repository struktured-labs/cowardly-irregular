extends GutTest

## Room-to-breathe HUD pass (struktured 2026-10-03): "you can make turn order card cooler too
## with extra space (add icons or something, idk)". Each CTB timeline entry is now a forecast
## card — portrait/icon, AP pips, a thin HP bar, and a highlighted current actor — instead of
## a bare indicator+name+speed-number row.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _bm: RefCounted = null
var _scene: Node = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _spawn_battle_and_build_timeline() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame  # let any auto-triggered turn_info update's queue_free()'d rows flush first
	_scene._update_turn_info()
	await get_tree().process_frame
	await get_tree().process_frame  # flush THIS call's own queue_free()'d rows before the test reads node names


func _timeline_cards() -> Array:
	var ctb := _scene.get_node_or_null("UI/CTBTimeline")
	if not ctb:
		return []
	var timeline := ctb.find_child("Timeline", true, false)
	if not timeline:
		return []
	return timeline.get_children()


func test_ctb_panel_widened_for_richer_cards() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_string_contains(src, "_ctb_panel.offset_right = LEFT_COLUMN_RIGHT",
		"CTB panel must be widened past the old 110px name+number strip")
	assert_string_contains(src, "_ctb_panel.offset_top = -230",
		"CTB panel must be tall enough for portrait + pips + HP bar rows")


func test_timeline_builds_at_least_one_entry_card() -> void:
	await _spawn_battle_and_build_timeline()
	var cards := _timeline_cards()
	assert_gt(cards.size(), 0, "a live battle must produce at least one CTB entry")
	for c in cards:
		assert_true(str(c.name).begins_with("CTBEntryCard"),
			"each entry must be the new PanelContainer card, not a bare row")


func test_each_card_carries_a_portrait_and_an_hp_bar() -> void:
	await _spawn_battle_and_build_timeline()
	var cards := _timeline_cards()
	assert_gt(cards.size(), 0, "CONTROL: need at least one card to inspect")
	for c in cards:
		var card: Node = c
		var portrait: Node = card.find_child("Portrait", true, false)
		assert_not_null(portrait, "%s must carry a Portrait node" % card.name)
		assert_true(portrait is TextureRect, "Portrait must be a TextureRect")

		var hp_bg: Node = card.find_child("HPBarBg", true, false)
		assert_not_null(hp_bg, "%s must carry an HPBarBg node" % card.name)
		var hp_fill: Node = hp_bg.find_child("HPBarFill", true, false)
		assert_not_null(hp_fill, "HPBarBg must carry an HPBarFill child")

		var pips: Node = card.find_child("APPips", true, false)
		assert_not_null(pips, "%s must carry an APPips row" % card.name)
		assert_gt(pips.get_child_count(), 0, "APPips must contain pip nodes")


func test_current_actor_card_is_visually_highlighted() -> void:
	await _spawn_battle_and_build_timeline()
	var cards := _timeline_cards()
	assert_gt(cards.size(), 0, "CONTROL: need at least one card")
	var head: PanelContainer = cards[0]
	var style: StyleBoxFlat = head.get_theme_stylebox("panel")
	assert_not_null(style, "head card must carry an explicit panel style")
	assert_eq(style.border_width_left, 2, "the current/head actor's card must have the thicker highlighted border")
	if cards.size() > 1:
		var other: PanelContainer = cards[1]
		var other_style: StyleBoxFlat = other.get_theme_stylebox("panel")
		assert_ne(other_style.border_color, style.border_color,
			"a non-head card must be styled differently from the highlighted head card")


func test_enemy_hp_bar_respects_fog_of_war_until_revealed() -> void:
	# Direct unit check on the HP-bar builder itself — the fog-of-war rule
	# (BattleUIManager._enemy_hp_revealed) must gate what the bar SHOWS,
	# not just what a Label prints.
	var ui_mgr_script: GDScript = load("res://src/battle/BattleUIManager.gd")
	var fake_scene := RefCounted.new()
	var ui_mgr = ui_mgr_script.new(fake_scene)
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var enemy: Combatant = combatant_script.new()
	enemy.combatant_name = "Shrouded Foe"
	enemy.max_hp = 100
	enemy.current_hp = 10  # would read as near-death if shown
	var bar: Control = ui_mgr._ctb_hp_bar(enemy, false)
	var fill: Node = bar.find_child("HPBarFill", true, false)
	assert_almost_eq(fill.anchor_right, 1.0, 0.001,
		"an un-scanned enemy's HP bar must show the UNKNOWN fraction (full-width neutral), not the true 10%")

	# Direct state write, not reveal_enemy_stats() — that also rebuilds the live enemy status
	# boxes via _scene.test_enemies, which this bare RefCounted fake_scene doesn't carry.
	ui_mgr._revealed_enemies[enemy] = true
	var bar2: Control = ui_mgr._ctb_hp_bar(enemy, false)
	var fill2: Node = bar2.find_child("HPBarFill", true, false)
	assert_almost_eq(fill2.anchor_right, 0.1, 0.01,
		"once revealed, the HP bar must show the real fraction")
