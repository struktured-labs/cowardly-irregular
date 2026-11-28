extends GutTest
## .849 gate: 4450 "Node not found" errors from bare-script BattleScenes; the fixture builds the .tscn instead.

const Fixture := preload("res://test/unit/helpers/battle_scene_fixture.gd")
const SceneScript := preload("res://src/battle/BattleScene.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const PATHS := ["BattleField/PartyArea/Player1Pos", "BattleField/EnemyArea/Enemy1Pos", "UI/PartyStatusPanel", "UI/TurnInfoPanel/TurnInfo"]


class Probe extends "res://src/battle/BattleScene.gd":
	var probed := true


var _bm_guard = BattleStateGuard.new()


func before_each() -> void:
	_bm_guard.snapshot()


func after_each() -> void:
	_bm_guard.restore()


func test_a_bare_script_has_none_of_the_nodes() -> void:
	var bare: Node = autofree(SceneScript.new())
	for p in PATHS:
		assert_false(bare.has_node(p), "CONTROL: a bare BattleScene.gd has no %s, which is what the engine errors were" % p)


func test_the_fixture_has_every_node() -> void:
	var scene: Node = autofree(Fixture.build())
	assert_eq(scene.get_script().get_base_script(), SceneScript, "the fixture runs the real BattleScene script beneath its quiet override")
	for p in PATHS:
		assert_true(scene.has_node(p), "the fixture's scene must carry %s" % p)


func test_a_probe_subclass_keeps_its_script_and_the_nodes() -> void:
	var scene: Node = autofree(Fixture.build(Probe))
	assert_eq(scene.get_script(), Probe, "the probe subclass must be the scene's script")
	assert_true(bool(scene.get("probed")), "the probe's own members must be live")
	for p in PATHS:
		assert_true(scene.has_node(p), "a probe-scripted fixture must still carry %s" % p)


func test_a_built_scene_starts_no_battle_of_its_own() -> void:
	var live: Node = Fixture.build(null, true)
	add_child_autofree(live)
	assert_gt(live.test_enemies.size(), 0, "CONTROL: a live-built scene spawns its own test battle on entering the tree")
	live.queue_free()
	await get_tree().process_frame
	_bm_guard.restore()
	var before: int = BattleManager.current_state
	var scene: Node = Fixture.build()
	add_child_autofree(scene)
	assert_eq(scene.test_enemies.size(), 0, "the fixture's scene must not spawn a test battle")
	assert_eq(scene.enemy_sprite_nodes.size(), 0, "the fixture's scene must not place its own enemy sprites")
	assert_eq(int(BattleManager.current_state), before, "the fixture's scene must not start a battle on the BattleManager autoload")


func test_the_top_offenders_build_through_the_fixture() -> void:
	for f in ["command_menu_shape_regression", "the_boss_last_words_are_a_moment", "a_buff_lands_where_you_can_see_it",
			"a_running_advance_shows_its_steps", "a_swing_plays_to_its_last_frame", "a_boss_line_is_not_a_wedged_menu_regression",
			"a_hit_lands_with_its_weight", "a_sprite_rests_at_its_own_colour", "the_locked_defer_row_says_why_regression",
			"the_group_menu_offers_what_the_engine_accepts", "the_party_shares_one_bag_in_battle", "the_advance_queue_is_shown_as_cards",
			"the_party_panel_compacts_without_a_coroutine_regression", "a_chained_lunge_comes_home_regression",
			"job_change_hides_unknown_quick_slots_regression", "victory_banners_stay_clear_of_the_results", "defer_always_available_regression"]:
		var src := FileAccess.get_file_as_string("res://test/unit/test_%s.gd" % f)
		assert_gt(src.length(), 0, "CONTROL: read test_%s.gd" % f)
		assert_true(src.contains("battle_scene_fixture.gd"), "test_%s.gd must build its BattleScene through the fixture" % f)


func test_the_root_sets_nothing_a_probe_swap_would_drop() -> void:
	## set_script resets script-owned vars, so the probe path is only faithful while the .tscn root sets none.
	var allowed := ["layout_mode", "anchors_preset", "anchor_left", "anchor_top", "anchor_right", "anchor_bottom",
		"offset_left", "offset_top", "offset_right", "offset_bottom", "grow_horizontal", "grow_vertical", "script"]
	var keys: Array = []
	var on := false
	for line in FileAccess.get_file_as_string(Fixture.SCENE_PATH).split("\n"):
		if line.begins_with("[node name=\"BattleScene\""):
			on = true
		elif on and line.begins_with("["):
			break
		elif on and " = " in line:
			keys.append(line.get_slice(" = ", 0))
	assert_true(keys.has("script"), "CONTROL: the root block was found and read")
	for k in keys:
		assert_true(allowed.has(k), "BattleScene.tscn's root sets '%s'; battle_scene_fixture's probe set_script would silently drop a script var" % k)
