extends GutTest

## struktured 2026-11-01: "move the party and monsters slightly towards the edges of the screen (party slightly
## closer to the right and monsters slightly closer to left). see if we got the space for that", then "the rogue/bard
## are sorta stacked on top of each other in battle ... I think its systemic". Measured in real battles: the enemies
## had 71px to the left column at 100% text and 33px at 200%, so they stand 24px nearer it (ENEMY_EDGE_SHIFT). The
## party stood in one diagonal 45px apart with 150-230px bodies (Rogue 68% inside the Mage, 90% in Diamond), under the
## AUTO/speed badges. Now the badges ride in the PARTY header and the party stands in two ranks spaced by its measured
## widths, PARTY_PANEL_GAP from its panel at any Text Size. This holds all of it, on each body's opaque frame.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BS := preload("res://src/battle/BattleScene.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const Body := preload("res://test/unit/helpers/battle_body_rect.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const SettingsMenuScript := preload("res://src/ui/SettingsMenu.gd")
const AdvanceAuraScript := preload("res://src/battle/AdvanceAura.gd")

const LINEUPS := [["goblin", "goblin", "goblin"], ["goblin", "goblin"], ["cave_rat_king"]]
const LEFT_COLUMN := ["EnemyStatusPanel", "BattleLogPanel", "CTBTimeline"]

var _guard
var _saved_scale := 1.0
var _saved_text := 1.0
var _saved_formation := 0


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_text = GameState.text_size_scale
	_saved_formation = BS.current_formation


func after_each() -> void:
	## current_formation is STATIC and the headless resolver applies it: a cycled formation left behind buffed the next file's grind party.
	BS.current_formation = _saved_formation
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


func test_no_party_member_touches_the_party_panel_or_a_badge_at_any_size() -> void:
	var bad: Array = []
	var judged := 0
	for ts in SettingsMenuScript.TEXT_SIZE_PRESETS:
		GameState.set_text_size_scale(ts)
		var scene = await _build(["goblin"])
		for i in 3:
			await get_tree().process_frame
		var w: Dictionary = Body.walls(scene)
		assert_eq(scene.party_sprite_nodes.size(), 5, "CONTROL: the full party stands")
		assert_true(w.has("PartyStatusPanel") and w.has("SpeedPanel") and w.has("AutoToggleButton"),
			"CONTROL: the PARTY panel and both badges stand (%s)" % str(w.keys()))
		for f in BS.FORMATION_NAMES.size():
			if f > 0:
				scene.cycle_formation()
				await get_tree().create_timer(0.4).timeout
			var tag := "text %.2f %s" % [ts, BS.FORMATION_NAMES[scene.current_formation]]
			bad.append_array(_touches(scene, scene.party_sprite_nodes, ["PartyStatusPanel", "SpeedPanel", "AutoToggleButton"], tag))
			bad.append_array(_touches(scene, scene.enemy_sprite_nodes, ["SpeedPanel", "AutoToggleButton"], tag))
			judged += 1
		scene.queue_free()
		await get_tree().process_frame
	assert_eq(judged, SettingsMenuScript.TEXT_SIZE_PRESETS.size() * BS.FORMATION_NAMES.size(), "CONTROL: every size and formation was judged")
	assert_eq(bad, [], "%d touch(es):\n%s" % [bad.size(), "\n".join(bad.slice(0, 6))])


func test_the_badges_ride_in_the_party_header() -> void:
	var scene = await _build(["goblin"])
	for i in 3:
		await get_tree().process_frame
	var panel: Control = scene.get_node("UI/PartyStatusPanel")
	for name in ["SpeedPanel", "AutoToggleButton"]:
		var badge := scene.find_child(name, true, false) as Control
		assert_not_null(badge, "CONTROL: %s is built" % name)
		if badge:
			assert_true(panel.is_ancestor_of(badge), "%s rides inside the PARTY panel, off the column above the party" % name)


func test_the_bodies_measured_are_figures_not_frames() -> void:
	var scene = await _build(["goblin"])
	var vp: Vector2 = scene.get_viewport_rect().size
	for s in scene.enemy_sprite_nodes + scene.party_sprite_nodes:
		var r: Rect2 = Body.of(s)
		assert_gt(r.size.x, 20.0, "CONTROL: %s has a body to measure (%s)" % [s.name, str(r)])
		assert_lt(r.size.x, vp.x * 0.25, "CONTROL: %s is measured by its figure, not a padded frame (%s)" % [s.name, str(r)])


## A member's opaque figure on screen, idle frame: what a player sees as "stacked".
func _figure(sprite: AnimatedSprite2D) -> Rect2:
	var fig: Rect2 = AdvanceAuraScript.figure_rect_in_sprite(sprite, &"idle")
	return Rect2(sprite.global_position + fig.position, fig.size)


func test_no_two_party_members_stack_in_any_formation() -> void:
	var bad: Array = []
	var judged := 0
	for ts in [1.0, 2.0]:
		GameState.set_text_size_scale(ts)
		var scene = await _build(["goblin"])
		for i in 3:
			await get_tree().process_frame
		for f in BS.FORMATION_NAMES.size():
			if f > 0:
				scene.cycle_formation()
				await get_tree().create_timer(0.4).timeout
			var figs: Array = []
			for s in scene.party_sprite_nodes:
				figs.append(_figure(s))
			for i in figs.size():
				for j in range(i + 1, figs.size()):
					var a: Rect2 = figs[i]
					var b: Rect2 = figs[j]
					var cut := a.intersection(b)
					var smaller := minf(a.get_area(), b.get_area())
					judged += 1
					if smaller > 0.0 and cut.get_area() > smaller * 0.15:
						bad.append("text %.2f %s: members %d and %d share %.0f%% of the smaller body" % [
							ts, BS.FORMATION_NAMES[scene.current_formation], i, j, 100.0 * cut.get_area() / smaller])
		scene.queue_free()
		await get_tree().process_frame
	assert_eq(judged, 2 * BS.FORMATION_NAMES.size() * 10, "CONTROL: every pair of five in every formation, at 100% and 200%")
	assert_eq(bad, [], "%d stacked pair(s):\n%s" % [bad.size(), "\n".join(bad.slice(0, 8))])


## struktured on .759: "where the rogue is relative to mage and cleric looks so proportionally off". Each rank is ONE
## column (body centres within 2px) with evenly spaced feet, in every formation whose offsets are uniform per rank.
## Diamond is NOT here, by ruling (cowir-main 2026-11-01): its offsets are authored geometry, a diamond on purpose.
const RANK_UNIFORM_FORMATIONS := ["V-Formation", "Front Line", "Back Row", "Spread"]
## Diamond's own contract instead: these exact offsets, and no stacking (test_no_two_party_members_stack covers it).
const DIAMOND_OFFSETS := [Vector2(-25, 0), Vector2(0, -30), Vector2(0, 30), Vector2(25, -18), Vector2(25, 18)]


func test_diamond_keeps_its_authored_shape() -> void:
	var scene = await _build(["goblin"])
	assert_true("Diamond" in BS.FORMATION_NAMES, "CONTROL: Diamond is still a formation")
	for i in DIAMOND_OFFSETS.size():
		assert_eq(scene._get_formation_offset(i, 5, BS.PartyFormation.DIAMOND), DIAMOND_OFFSETS[i],
			"Diamond's member %d keeps its authored offset" % i)


func test_each_rank_is_one_evenly_spaced_column() -> void:
	var bad: Array = []
	var judged := 0
	var scene = await _build(["goblin"])
	for i in 3:
		await get_tree().process_frame
	for f in BS.FORMATION_NAMES.size():
		if f > 0:
			scene.cycle_formation()
			await get_tree().create_timer(0.4).timeout
		var fname: String = BS.FORMATION_NAMES[scene.current_formation]
		if not (fname in RANK_UNIFORM_FORMATIONS):
			continue
		for rank in [0, 1]:
			var xs: Array = []
			for i in range(rank, scene.party_sprite_nodes.size(), 2):
				## Where it RESTS (home): the acting member's 80px step-out is not its place in the rank.
				var sprite: AnimatedSprite2D = scene.party_sprite_nodes[i]
				var fig: Rect2 = AdvanceAuraScript.figure_rect_in_sprite(sprite, &"idle")
				xs.append((sprite.get_meta("home_position", sprite.position) as Vector2).x + fig.get_center().x)
			for k in range(1, xs.size()):
				if absf(xs[k] - xs[0]) > 2.0:
					bad.append("%s rank %d: member %d stands %.1fpx off its rank's column" % [fname, rank, rank + 2 * k, xs[k] - xs[0]])
			var steps: Array = []
			for i in range(rank, scene.party_sprite_nodes.size(), 2):
				steps.append(float(scene._party_base_positions[i].y) - scene.party_feet_correction(scene.party_sprite_nodes[i]))
			for k in range(2, steps.size()):
				var a: float = steps[k] - steps[k - 1]
				var b: float = steps[k - 1] - steps[k - 2]
				if absf(a - b) > 2.0:
					bad.append("%s rank %d: slot steps %.1f vs %.1f" % [fname, rank, b, a])
			judged += 1
	assert_eq(judged, RANK_UNIFORM_FORMATIONS.size() * 2, "CONTROL: both ranks judged in every rank-uniform formation")
	assert_eq(bad, [], "%d uneven:\n%s" % [bad.size(), "\n".join(bad.slice(0, 8))])


func test_the_party_stands_its_gap_from_the_panel_at_every_size() -> void:
	assert_lt(BS.ENEMY_EDGE_SHIFT, 0.0, "the enemies stand nearer the LEFT edge")
	for ts in SettingsMenuScript.TEXT_SIZE_PRESETS:
		GameState.set_text_size_scale(ts)
		var scene = await _build(["goblin"])
		for i in 3:
			await get_tree().process_frame
		var panel_left: float = (scene.get_node("UI/PartyStatusPanel") as Control).get_global_rect().position.x
		var nearest := INF
		for f in BS.FORMATION_NAMES.size():
			if f > 0:
				scene.cycle_formation()
				await get_tree().create_timer(0.4).timeout
			for s in scene.party_sprite_nodes:
				nearest = minf(nearest, panel_left - _figure(s).end.x)
		assert_almost_eq(nearest, BS.PARTY_PANEL_GAP, 1.5,
			"text %.2f: in its rightmost formation the party stands PARTY_PANEL_GAP from its panel (%.1f)" % [ts, nearest])
		scene.queue_free()
		await get_tree().process_frame


func test_the_enemy_column_carries_its_shift() -> void:
	var st := SCENE.get_state()
	var authored := NAN
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == "offset_left" and str(st.get_node_name(i)) == "EnemyArea":
				authored = float(st.get_node_property_value(i, p))
	assert_false(is_nan(authored), "CONTROL: the scene authors the enemy column")
	var scene = await _build(["goblin"])
	assert_almost_eq(scene.get_node("BattleField/EnemyArea").offset_left, authored + BS.ENEMY_EDGE_SHIFT, 0.5,
		"the enemy column stands ENEMY_EDGE_SHIFT from where the scene authors it")


## The column settles at build and re-seats the party once: that seat must SNAP, not slide in over the opening frames.
func test_the_party_is_already_seated_a_few_frames_in() -> void:
	for ts in SettingsMenuScript.TEXT_SIZE_PRESETS:
		GameState.set_text_size_scale(ts)
		var scene = await _build(["goblin"])
		assert_true(scene._party_relaid_once, "CONTROL text %.2f: the column's build-time re-seat ran" % ts)
		for s in scene.party_sprite_nodes:
			var home: Vector2 = s.get_meta("home_position", Vector2.INF)
			assert_almost_eq(s.position.x, home.x, 0.5, "text %.2f: %s still sliding to its seat (%.1f -> %.1f)" % [ts, s.name, s.position.x, home.x])
		scene.queue_free()
		await get_tree().process_frame
