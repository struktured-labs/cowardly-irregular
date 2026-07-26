extends GutTest

## Found 2026-07-01 while diagnosing "goblin suddenly became small and
## facing wrong way": _handle_monster_summon spawned mid-battle enemies
## with a HARDCODED final scale of 1.0 and no flip_h. Battle-start
## spawns give artist drops (<=128px frames: slime/bat/goblin/cave_rat)
## ENEMY_SCALE_BUMP (2.5x) and flip them to face the party — so any
## summoned artist-sheet monster popped in 2.5x too small AND facing
## away. Also: the summon path never appended _enemy_base_positions,
## so summons were silently excluded from idle sway (index guard).

const SCENE_SRC := "res://src/battle/BattleScene.gd"


func _summon_body() -> String:
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	var idx: int = src.find("func _on_monster_summoned")
	assert_gt(idx, -1, "_on_monster_summoned must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx)


func test_summon_applies_artist_size_bump() -> void:
	var body := _summon_body()
	assert_true(body.contains("ENEMY_SCALE_BUMP"),
		"summon path must apply the artist-drop size bump like battle-start spawns")
	assert_true(body.contains("ENEMY_SMALL_FRAME_THRESHOLD"),
		"bump must key off the same frame-height threshold as battle-start")


func test_summon_flips_artist_sheets_toward_party() -> void:
	# 2026-07-25: this pinned the literal `flip_h = is_artist_monster`, so adding the
	# manifest flip_h override (cave_rat_king renders backwards without it) failed a
	# test whose actual subject — summon/battle-start PARITY — was preserved. Assert
	# the parity instead of one spelling of it.
	# 2026-07-26: helper renamed monster_flip_override -> monster_faces_party when
	# facing was decoupled from the scale bump. Same subject, clearer name.
	var body := _summon_body()
	assert_true(body.contains("monster_faces_party("),
		"summons must resolve facing through the shared helper, not a local rule")
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_eq(scene_src.count("HybridSpriteLoader.monster_faces_party("), 2,
		"exactly two flip sites — battle-start and summon — must agree; a summoned monster "
		+ "facing the wrong way while its battle-start twin faces correctly is the regression")


func test_summon_tween_settles_at_computed_scale() -> void:
	var body := _summon_body()
	assert_true(body.contains("Vector2(final_scale, final_scale)"),
		"pop-in tween must settle at the computed scale")
	assert_false(body.contains("\"scale\", Vector2(1.0, 1.0)"),
		"hardcoded 1.0 final scale is the regression — 2.5x too small for artist drops")


func test_summon_registers_sway_base_position() -> void:
	var body := _summon_body()
	assert_true(body.contains("_enemy_base_positions.append"),
		"summons must register a sway base position or the idle-sway index guard skips them forever")
