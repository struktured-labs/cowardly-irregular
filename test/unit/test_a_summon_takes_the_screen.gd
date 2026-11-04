extends GutTest

## struktured 2026-11-01 "ridiculous summons", batch 3: a party summon is a glory moment like Firaga (card, tinted
## stage, first cast at 1x, tiers) AND its summon_art (sprite_manifest.json) takes the stage: the shared circle opens
## centre stage and the summon's figure rises out of it during the wind-up, stands through the attack, and leaves
## with the beat. The art was on disk with no runtime reader until this. Presentation only.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleSceneClassRef := preload("res://src/battle/BattleScene.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BS_SPEEDS_1X := 0.25

var _guard
var _saved_speed: float = 0.0


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_speed = float(GameState.default_battle_speed)


func after_each() -> void:
	GameState.default_battle_speed = _saved_speed
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _summons() -> Array:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var out: Array = []
	for id in (raw.get("summon_art", {}) if raw is Dictionary else {}):
		if id != "circle":
			out.append(str(id))
	return out


func _scene_with_party() -> Node:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	return scene


func test_every_summon_with_art_is_a_glory_moment_with_its_figure() -> void:
	var ids := _summons()
	assert_gte(ids.size(), 5, "CONTROL: the manifest's summon_art was read (%s)" % str(ids))
	for id in ids:
		var ability: Dictionary = JobSystem.get_ability(id)
		assert_false(ability.is_empty(), "%s is a real ability" % id)
		var vfx = ability.get("vfx", {})
		var seq := str(vfx.get("glory", "")) if vfx is Dictionary else ""
		assert_ne(seq, "", "%s names a glory sequence" % id)
		assert_false(FractalFX.load_sequence(seq).is_empty(), "%s's %s resolves" % [id, seq])
		var art: Dictionary = BattleSceneClassRef.summon_art_for(id)
		assert_true(load(str(art.get("figure", ""))) is Texture2D, "%s's figure loads" % id)
		assert_true(load(str(art.get("circle", ""))) is Texture2D, "and so does the shared circle")
	assert_true(BattleSceneClassRef.summon_art_for("firaga").is_empty(), "CONTROL: a spell without art has none")
	assert_true(BattleSceneClassRef.summon_art_for("circle").is_empty(), "the circle is not a summon")


## The DISPATCH: a party summon raises the splash; its figure is that summon's own art and it rises over the wind-up.
func test_a_party_summon_rises_out_of_its_circle() -> void:
	var scene = await _scene_with_party()
	var saved := Engine.time_scale
	if BattleManager.player_party.is_empty() or BattleManager.enemy_party.is_empty():
		assert_true(false, "CONTROL: a party and a foe")
		return
	scene._on_action_executing(BattleManager.player_party[0], {"type": "ability", "ability_id": "summon_ifrit", "targets": BattleManager.enemy_party.duplicate()})
	await get_tree().process_frame
	var fig := scene.get_node_or_null("SummonSplash/Figure") as Sprite2D
	assert_not_null(fig, "Overclock stands on the stage")
	assert_not_null(scene.get_node_or_null("SummonSplash/Circle"), "in its circle")
	if fig == null:
		Engine.time_scale = saved
		return
	assert_eq(fig.texture.resource_path, str(BattleSceneClassRef.summon_art_for("summon_ifrit")["figure"]), "it is Overclock's own art")
	var start_y := fig.position.y
	await get_tree().create_timer((scene.SUMMON_RISE + 0.1) / Engine.time_scale, true, false, true).timeout
	if is_instance_valid(fig):
		assert_lt(fig.position.y, start_y - 20.0, "it rose out of the circle (%.0f → %.0f)" % [start_y, fig.position.y])
		assert_gt(fig.modulate.a, 0.5, "and it is showing")
	Engine.time_scale = saved


## The figure leaves with the beat rather than standing over the next turn.
func test_the_summon_leaves_when_its_beat_ends() -> void:
	var scene = await _scene_with_party()
	var saved := Engine.time_scale
	if BattleManager.player_party.is_empty() or BattleManager.enemy_party.is_empty():
		assert_true(false, "CONTROL: a party and a foe")
		return
	scene._set_battle_time_scale(1.0)
	scene._play_signature(BattleManager.player_party[0], null, null, JobSystem.get_ability("summon_shiva"), BattleManager.enemy_party.duplicate(), "summon_cold_storage")
	await get_tree().process_frame
	assert_not_null(scene.get_node_or_null("SummonSplash"), "CONTROL: Cold Storage took the stage")
	var beat: float = (scene.SUMMON_RISE + scene.sequence_total("summon_cold_storage") + 1.5) / BS_SPEEDS_1X
	var deadline := Time.get_ticks_msec() + int(beat * 1200.0)
	while Time.get_ticks_msec() < deadline and (scene.get_node_or_null("SummonSplash") != null or scene.get_node_or_null("SummonSplashLeaving") != null):
		await get_tree().process_frame
	assert_null(scene.get_node_or_null("SummonSplash"), "the summon left with its beat")
	assert_null(scene.get_node_or_null("SummonSplashLeaving"), "and is gone, not lingering")
	scene._apply_battle_speed_index(1)
	Engine.time_scale = saved


## A foe's summon (the enemy side has no glory) and a party Firaga (no art) never raise a summon.
func test_no_art_no_summon_and_foes_stay_plain() -> void:
	var scene = await _scene_with_party()
	var saved := Engine.time_scale
	if BattleManager.player_party.is_empty() or BattleManager.enemy_party.is_empty():
		assert_true(false, "CONTROL: a party and a foe")
		return
	assert_eq(scene.glory_sequence(BattleManager.enemy_party[0], JobSystem.get_ability("summon_ifrit")), "", "a foe's Overclock is plain")
	scene._on_action_executing(BattleManager.player_party[0], {"type": "ability", "ability_id": "firaga", "targets": BattleManager.enemy_party.duplicate()})
	await get_tree().process_frame
	assert_not_null(scene.get_node_or_null("SignatureTint"), "CONTROL: Firaga still took the stage")
	assert_null(scene.get_node_or_null("SummonSplash"), "but nothing rose: Firaga has no summon art")
	Engine.time_scale = saved
