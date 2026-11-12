extends GutTest

## struktured 2026-11-12, playing .792: "the exp cards still overlap with the enemy cards in that last run".
## The victory cards hang left of the party and were stopped by a constant (LOG_CLEAR_X = 190) while the enemy
## panel's right edge is 205 px at 100% and wider with a long name or a larger Text Size, so the column's first
## pixels sat on the panel. The cards now start right of the real right edge of whichever left-column panel is
## showing (enemy panel, log, turn order). Measured on a REAL BattleScene's built nodes, with the overlay settled.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const OverlayScript := preload("res://src/battle/VictoryOverlay.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const ROSTERS := [["goblin"], ["goblin", "goblin", "goblin"], ["goblin", "goblin", "goblin", "goblin", "goblin"]]

var _guard
var _orig_scale := 1.0


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_orig_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _orig_scale
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 2, "CONTROL: the Text Size presets were read")
	return p


func _battle(scale: float, roster: Array) -> Node:
	GameState.text_size_scale = scale
	var scene = SCENE.instantiate()
	scene.encounter_enemies = roster.duplicate()
	add_child_autofree(scene)
	await wait_frames(6)
	return scene


func _results(members: int) -> Dictionary:
	var cr: Array = []
	for i in members:
		cr.append({"name": "Scriptweaver", "job_name": "fighter", "is_alive": true, "exp_gained": 99999,
			"job_exp_before": 40, "exp_to_next": 200, "leveled_up": true, "job_level": 11, "job_exp": 30, "stat_gains": {"HP": 46}})
	return {"char_results": cr, "total_gold": 40, "item_drops": [], "bonuses": [], "injuries": []}


func _settled_overlay(scene: Node, members: int) -> Control:
	var o: Control = OverlayScript.new()
	scene.add_child(o)
	o.build(_results(members), scene)
	o.complete_now()
	await wait_frames(4)
	return o


## A card is the Control that owns a "TopLine" (the finder test_a_victory_card_grows_with_the_text uses).
func _cards(o: Node, out: Array) -> void:
	for c in o.get_children():
		if c is Control and (c as Control).find_child("TopLine", true, false) != null:
			out.append(c)
		else:
			_cards(c, out)


func _column(scene: Node) -> Array:
	var out: Array = []
	for pname in OverlayScript.LEFT_COLUMN:
		var p := scene.find_child(pname, true, false) as Control
		if p != null and p.is_visible_in_tree() and p.get_global_rect().has_area():
			out.append(p)
	return out


func test_no_card_touches_a_left_column_panel_at_any_text_size() -> void:
	var judged := 0
	var walled := 0
	for scale in _presets():
		for roster in ROSTERS:
			var scene: Node = await _battle(float(scale), roster)
			var panels: Array = _column(scene)
			assert_true(panels.any(func(p): return p.name == "EnemyStatusPanel"),
				"CONTROL: the enemy panel is showing at %s with %d foes" % [scale, roster.size()])
			for members in [1, 5]:
				var o: Control = await _settled_overlay(scene, members)
				var cards: Array = []
				_cards(o, cards)
				assert_eq(cards.size(), members, "CONTROL: one card per member (%s, %d foes)" % [scale, roster.size()])
				var vp: Vector2 = o.get_viewport_rect().size
				if o._left_wall(vp.x) > OverlayScript.LOG_CLEAR_X:
					walled += 1
				for card in cards:
					var cr: Rect2 = (card as Control).get_global_rect()
					for p in panels:
						judged += 1
						var pr: Rect2 = (p as Control).get_global_rect()
						assert_false(cr.intersects(pr), "Text Size %s, %d foes, %d cards: a card %s is on %s %s" % [
							scale, roster.size(), members, cr, p.name, pr])
					assert_lte(cr.end.x, vp.x, "and it stays on the screen (%s, right edge %.0f)" % [scale, cr.end.x])
				o.free()
	assert_gt(judged, 0, "card and panel pairs were judged")
	assert_gt(walled, 0, "CONTROL: in some case a panel, not the old constant, is what stops the column")


func test_the_wall_is_the_showing_panels_edge() -> void:
	var scene: Node = await _battle(1.0, ROSTERS[1])
	var o: Control = await _settled_overlay(scene, 5)
	var vp_x: float = o.get_viewport_rect().size.x
	var widest := 0.0
	for p in _column(scene):
		widest = maxf(widest, (p as Control).get_global_rect().end.x)
	assert_gt(widest, 0.0, "CONTROL: a left-column panel is showing")
	assert_almost_eq(o._left_wall(vp_x), maxf(OverlayScript.LOG_CLEAR_X, widest + OverlayScript.LEFT_COLUMN_GAP), 0.01,
		"the cards start a gap right of the widest showing panel")
	for pname in OverlayScript.LEFT_COLUMN:
		var p := scene.find_child(pname, true, false) as Control
		if p != null:
			p.visible = false
	assert_almost_eq(o._left_wall(vp_x), OverlayScript.LOG_CLEAR_X, 0.01, "a hidden panel is no wall: the old floor is all that is left")


func test_a_panel_across_the_screen_is_not_a_column() -> void:
	var scene: Node = await _battle(1.0, ROSTERS[0])
	var o: Control = await _settled_overlay(scene, 5)
	var vp_x: float = o.get_viewport_rect().size.x
	var before: float = o._left_wall(vp_x)
	var panel := scene.find_child("EnemyStatusPanel", true, false) as Control
	assert_not_null(panel, "CONTROL: the enemy panel exists")
	if panel == null:
		return
	panel.custom_minimum_size.x = vp_x * 0.7
	panel.size.x = vp_x * 0.7
	await wait_frames(2)
	assert_gt(panel.get_global_rect().end.x, vp_x * 0.5, "CONTROL: the panel now reaches past mid-screen")
	assert_lte(o._left_wall(vp_x), before, "so it stops being a wall, or the cards would be pushed off the party's side")
