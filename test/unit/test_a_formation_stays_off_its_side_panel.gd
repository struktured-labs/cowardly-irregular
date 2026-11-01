extends GutTest

## struktured 2026-11-01: "move the party and monsters slightly towards the edges of the screen (party slightly
## closer to the right and monsters slightly closer to left). see if we got the space for that". Measured in real
## battles: the enemies had 71px to the left column at 100% text and 33px at 200%, so they moved 24px left
## (BattleScene.ENEMY_EDGE_SHIFT). The party had no room: its top member already stands under the speed/AUTO
## badges, so PARTY_EDGE_SHIFT stays 0. This holds what the move used: no combatant's on-screen body (opaque frame,
## name, HP bar, status icons) touches its side's column panels, in every formation and every Text Size preset.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BS := preload("res://src/battle/BattleScene.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const Body := preload("res://test/unit/helpers/battle_body_rect.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const SettingsMenuScript := preload("res://src/ui/SettingsMenu.gd")

const LINEUPS := [["goblin", "goblin", "goblin"], ["goblin", "goblin"], ["cave_rat_king"]]
const LEFT_COLUMN := ["EnemyStatusPanel", "BattleLogPanel", "CTBTimeline"]

var _guard
var _saved_scale := 1.0
var _saved_text := 1.0


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_text = GameState.text_size_scale


func after_each() -> void:
	GameState.set_text_size_scale(_saved_text)
	Engine.time_scale = _saved_scale
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _build(lineup: Array) -> Node:
	var scene = SCENE.instantiate()
	## The field path, which letters duplicates ("GOBLIN A"): the forced path does not, and its names are narrower.
	scene.encounter_enemies = lineup.duplicate()
	add_child_autofree(scene)
	Engine.time_scale = 1.0
	for i in 3:
		await get_tree().process_frame
	return scene


func _touches(scene: Node, sprites: Array, wall_names: Array, tag: String) -> Array:
	var out: Array = []
	var w: Dictionary = Body.walls(scene)
	for s in sprites:
		if not is_instance_valid(s) or not s.visible:
			continue
		var r: Rect2 = Body.of(s)
		for name in wall_names:
			if w.has(name) and r.intersects(w[name]):
				out.append("%s: %s %s overlaps %s %s" % [tag, s.name, str(r), name, str(w[name])])
	return out


func test_no_enemy_touches_the_left_column_at_any_text_size() -> void:
	var bad: Array = []
	var judged := 0
	for ts in SettingsMenuScript.TEXT_SIZE_PRESETS:
		GameState.set_text_size_scale(ts)
		for lineup in LINEUPS:
			var scene = await _build(lineup)
			var w: Dictionary = Body.walls(scene)
			assert_true(w.has("EnemyStatusPanel") and w.has("BattleLogPanel"), "CONTROL: the left column stands (%s)" % str(w.keys()))
			assert_eq(scene.enemy_sprite_nodes.size(), lineup.size(), "CONTROL: %s spawned as asked" % str(lineup))
			if lineup.size() > 1:
				assert_eq(str(scene.test_enemies[0].combatant_name).right(2), " A", "CONTROL: duplicates carry their letters, as in the field")
			bad.append_array(_touches(scene, scene.enemy_sprite_nodes, LEFT_COLUMN, "text %.2f %s" % [ts, str(lineup)]))
			judged += 1
			scene.queue_free()
			await get_tree().process_frame
	assert_eq(judged, SettingsMenuScript.TEXT_SIZE_PRESETS.size() * LINEUPS.size(), "CONTROL: every size and lineup was judged")
	assert_eq(bad, [], "%d touch(es):\n%s" % [bad.size(), "\n".join(bad.slice(0, 6))])


func test_no_party_member_touches_the_party_panel_in_any_formation() -> void:
	var bad: Array = []
	var scene = await _build(["goblin"])
	assert_eq(scene.party_sprite_nodes.size(), 5, "CONTROL: the full party stands")
	assert_true(Body.walls(scene).has("PartyStatusPanel"), "CONTROL: the PARTY panel stands")
	for f in BS.FORMATION_NAMES.size():
		if f > 0:
			scene.cycle_formation()
			await get_tree().create_timer(0.4).timeout
		bad.append_array(_touches(scene, scene.party_sprite_nodes, ["PartyStatusPanel"], BS.FORMATION_NAMES[scene.current_formation]))
	assert_eq(bad, [], "%d touch(es):\n%s" % [bad.size(), "\n".join(bad.slice(0, 6))])


func test_the_bodies_measured_are_figures_not_frames() -> void:
	var scene = await _build(["goblin"])
	var vp: Vector2 = scene.get_viewport_rect().size
	for s in scene.enemy_sprite_nodes + scene.party_sprite_nodes:
		var r: Rect2 = Body.of(s)
		assert_gt(r.size.x, 20.0, "CONTROL: %s has a body to measure (%s)" % [s.name, str(r)])
		assert_lt(r.size.x, vp.x * 0.25, "CONTROL: %s is measured by its figure, not a padded frame (%s)" % [s.name, str(r)])


func test_each_column_carries_its_shift() -> void:
	assert_lt(BS.ENEMY_EDGE_SHIFT, 0.0, "the enemies stand nearer the LEFT edge")
	assert_gte(BS.PARTY_EDGE_SHIFT, 0.0, "the party never moves away from its edge")
	var st := SCENE.get_state()
	var authored := {}
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == "offset_left":
				authored[str(st.get_node_name(i))] = float(st.get_node_property_value(i, p))
	assert_true(authored.has("EnemyArea") and authored.has("PartyArea"), "CONTROL: the scene authors both columns")
	var scene = await _build(["goblin"])
	assert_almost_eq(scene.get_node("BattleField/EnemyArea").offset_left, authored.get("EnemyArea", 0.0) + BS.ENEMY_EDGE_SHIFT, 0.5,
		"the enemy column stands ENEMY_EDGE_SHIFT from where the scene authors it")
	assert_almost_eq(scene.get_node("BattleField/PartyArea").offset_left, authored.get("PartyArea", 0.0) + BS.PARTY_EDGE_SHIFT, 0.5,
		"the party column stands PARTY_EDGE_SHIFT from where the scene authors it")
