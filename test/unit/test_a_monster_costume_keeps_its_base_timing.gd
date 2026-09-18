extends GutTest

## A world costume with fewer frames than its base must take the SAME wall-clock time.
##
## `dressed_fps` was written for exactly this and had ONE call site — `_load_external_sheet`, the
## JOB builder. `load_monster_sprite_frames` read `sheet_data.get("fps", 8)` raw, and the monster
## path IS a costume path: BattleScene:1305 builds "%s_%s" % [monster_id, world_suffix] and loads
## the variant through that builder.
##
## The two costume mechanisms are structurally different, which is why this was not a one-line
## mirror. A job costume is ONE manifest entry with two files (idle.png / idle_suburban.png), so
## the loader sees both. A monster costume is TWO SEPARATE ENTRIES (slime / slime_suburban)
## resolved by the caller, so the loader cannot derive the base and must be told it.
##
## Zero instances today, measured both ways: all five true costumes (slime_{suburban,steampunk,
## industrial,digital,abstract}) are 11 frames at 8 fps, exactly like `slime`. The trigger is the
## ratio the JOB costumes already ship at — cleric idle 7 frames -> costume 2, mage 6 -> 2,
## bard 4 -> 2. Authored at 2 against an 11-frame base, a slime costume plays 5.5x fast.
##
## Found by cowir-adhoc diffing the two builders; verified here independently.

const LOADER := "res://src/battle/sprites/HybridSpriteLoader.gd"
const SCENE := "res://src/battle/BattleScene.gd"

const BASE := "slime"
const COSTUMES := ["slime_suburban", "slime_steampunk", "slime_industrial", "slime_digital", "slime_abstract"]


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_the_retiming_math_is_one_owner_not_two_copies() -> void:
	var src := _src(LOADER)
	assert_true(src.contains("static func retimed_fps("),
		"OWNER: retimed_fps is gone — the two builders derive frames differently but must share the arithmetic")
	assert_true(src.contains("return retimed_fps(base_fps, frames, base_tex.get_width() / frame_width)"),
		"OWNER: dressed_fps no longer delegates to retimed_fps. Two copies of `fps * frames / base_frames` drift, and only one of them is ever tested")


func test_a_shorter_costume_is_slowed_to_its_base_duration() -> void:
	## The defect as arithmetic, not as source text: 2 frames against an 11-frame base at 8 fps
	## must play at 8*2/11, so both take 1.375s. Raw fps would finish in 0.25s — 5.5x fast.
	var got: float = HybridSpriteLoader.retimed_fps(8.0, 2, 11)
	assert_almost_eq(got, 8.0 * 2.0 / 11.0, 0.0001,
		"a 2-frame costume of an 11-frame base must be re-timed, got %f" % got)
	assert_almost_eq(2.0 / got, 11.0 / 8.0, 0.0001,
		"DURATION is the invariant the re-timing defends: the costume must occupy the same wall-clock time as the base")


func test_the_retiming_is_inert_where_it_should_be() -> void:
	assert_eq(HybridSpriteLoader.retimed_fps(8.0, 11, 11), 8.0, "an equal frame count must not be re-timed")
	assert_eq(HybridSpriteLoader.retimed_fps(8.0, 0, 11), 8.0, "a zero frame count must fall back, not divide")
	assert_eq(HybridSpriteLoader.retimed_fps(8.0, 4, 0), 8.0, "a zero BASE must fall back, not divide by zero")


func test_the_costume_builder_is_told_which_base_it_dresses() -> void:
	var src := _src(LOADER)
	assert_true(src.contains("func load_monster_sprite_frames(monster_id: String, base_id: String = \"\")"),
		"WIRING: the monster builder no longer accepts a base id, so it cannot re-time anything")
	var scene := _src(SCENE)
	assert_true(scene.contains("load_monster_sprite_frames(variant_id, monster_id)"),
		"WIRING: BattleScene resolves the costume and then does not say what it dresses — the parameter alone re-times nothing")
	## The arm that discriminates. Accepting the base id proves nothing about USING it, and the
	## behavioural arm below cannot tell: today every costume matches its base, so dropping this
	## call leaves it green. Source-level because there is no authored mismatch to drive.
	assert_true(src.contains("anim_fps = retimed_fps(fps, end_frame - start_frame + 1, b_end - b_start + 1)"),
		"WIRING: the per-animation loop no longer consults retimed_fps. The base_id is accepted and ignored, which is the original defect wearing a wider signature")


func test_todays_costumes_are_unchanged_because_they_already_match() -> void:
	## Anti-coincidence: this arm must pass because the data MATCHES, not because nothing is wired.
	## If a costume is ever authored at a different frame count, this reds and names it — which is
	## the moment to confirm the re-timing is what you want rather than a surprise.
	var base := HybridSpriteLoader.load_monster_sprite_frames(BASE)
	assert_not_null(base, "SCOPE: %s did not load — every arm below is vacuous" % BASE)
	var base_fps: float = base.get_animation_speed("idle")
	assert_gt(base_fps, 0.0, "SCOPE: base idle speed is not positive")

	var checked := 0
	var drifted: Array[String] = []
	for id in COSTUMES:
		var frames := HybridSpriteLoader.load_monster_sprite_frames(id, BASE)
		if frames == null:
			continue
		checked += 1
		var got: float = frames.get_animation_speed("idle")
		if abs(got - base_fps) > 0.0001:
			drifted.append("%s idle %f vs base %f" % [id, got, base_fps])
	assert_gt(checked, 3, "SCOPE: only %d of %d costumes loaded — a floor that enumerates nothing passes for free" % [checked, COSTUMES.size()])
	assert_eq(drifted.size(), 0,
		"a costume's frame count now differs from its base, so the re-timing changed its speed: %s. That is the fix working; confirm it is the timing you want" % str(drifted))
