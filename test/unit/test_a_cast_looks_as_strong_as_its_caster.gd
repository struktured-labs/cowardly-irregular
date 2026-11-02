extends GutTest

## struktured 2026-11-01: "all effects are a function of ur char stats / lvl / whatever too. some intensity changes as the
## stat goes up, kind of like Secret of Mana magic". BattleScene.cast_intensity derives one value per cast from the
## caster's level and its stat (magic, or attack for a physical move): a continuous size/shake multiplier, and one of three
## tiers from INTENSITY_TIERS that can add beats (`min_tier`) and recolour (`palette_t3`). Presentation only.
## Also from the same preview: "maybe it was fire magic and you changed it". Fractal Fire's bolt left WHITE, so it read
## as something else, and its target's death dissolve began before the held hit landed, so the bolt flew at an empty spot.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BS := preload("res://src/battle/BattleScene.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()


func after_each() -> void:
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func test_intensity_rises_with_the_stat_and_with_the_level() -> void:
	var last := -1.0
	for stat in [5.0, 20.0, 80.0, 300.0, 900.0]:
		var k: float = BS.intensity_for(10.0, stat)["k"]
		assert_gt(k, last, "a higher stat never looks weaker (stat %.0f)" % stat)
		last = k
	last = -1.0
	for level in [1.0, 10.0, 25.0, 40.0, 58.0]:
		var k: float = BS.intensity_for(level, 50.0)["k"]
		assert_gt(k, last, "a higher level never looks weaker (level %.0f)" % level)
		last = k


func test_a_novice_and_a_master_look_obviously_different() -> void:
	var novice: Dictionary = BS.intensity_for(5.0, 20.0)
	var master: Dictionary = BS.intensity_for(40.0, 400.0)
	assert_eq(int(novice["tier"]), 1, "a level-5 Mage's spell is tier 1")
	assert_eq(int(master["tier"]), 3, "a level-40 Mage's spell is tier 3")
	assert_gt(float(master["k"]) - float(novice["k"]), 0.3, "and visibly bigger, not a rounding difference")


func test_tiers_begin_where_the_one_table_says() -> void:
	assert_eq(BS.INTENSITY_TIERS.size(), 3, "three visible tiers")
	for i in BS.INTENSITY_TIERS.size():
		var at: float = float(BS.INTENSITY_TIERS[i])
		## A score exactly on a boundary: solve 0.6*lv + 0.4*st = at with st = 0 (stat 0), lv from level.
		var level := 1.0 + at / 0.6 * (BS.INTENSITY_LEVEL_CAP - 1.0)
		if at / 0.6 > 1.0:
			continue
		assert_eq(int(BS.intensity_for(level + 0.01, 0.0)["tier"]), i + 1, "tier %d begins at score %.2f" % [i + 1, at])


func test_fire_reads_as_flame_until_its_caster_is_a_master() -> void:
	var seq: Dictionary = FractalFX.load_sequence("fire_battle")
	for p in seq.get("phases", []):
		if str(p.get("kind", "")) in ["bolt", "ring", "emit", "spin_fling"] and int(p.get("min_tier", 1)) <= 1:
			assert_eq(str(p.get("palette", "fire")), "flame", "Fire's %s is orange flame at tier 1, not white-hot" % p["kind"])
			assert_eq(str(p.get("palette_t3", "")), "fire", "and goes white-hot at tier 3")
	## The tier filter itself, on a one-beat sequence so nothing random can hide it: a min_tier 3 ring plays only at 3.
	var host := Node2D.new()
	add_child_autofree(host)
	var only_t3 := {"phases": [{"at": 0.0, "kind": "ring", "dur": 0.3, "scale": 2.0, "palette": "fire", "min_tier": 3}]}
	for t in [1, 3]:
		var fx := FractalFX.new(host, 11)
		fx.tier = t
		var before := host.get_child_count()
		fx.play(only_t3, Vector2(900, 300), Vector2(300, 300))
		assert_eq(host.get_child_count() - before, 1 if t >= 3 else 0, "a tier-3 beat %s at tier %d" % ["plays" if t >= 3 else "is skipped", t])


func test_a_held_hit_keeps_its_target_standing_until_it_lands() -> void:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin", "goblin"]
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	scene._full_render_dmg_buffer = []
	scene._on_enemy_died(0)
	assert_true(0 in scene._deaths_after_impact, "a foe killed by a held hit waits for the hit to land before it dissolves")
	scene._flush_full_render_damage()
	assert_eq(scene._deaths_after_impact, [], "and dissolves as soon as it lands")
