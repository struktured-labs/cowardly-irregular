extends GutTest

## `spawn()` carried `hold_time / maxf(1.0, Engine.time_scale)` under the comment *"Faster battle
## speed shortens the hold so bubbles never outlive their turn."* That divisor is **1.0 at every
## speed a bubble can spawn at**, because suppression fires first:
##
##   label  engine  spawns?      divisor
##   1x     0.25    yes          1.0
##   2x     0.5     yes          1.0
##   4x+    1.0+    SUPPRESSED   (never reached — spawn() returned null above)
##
## So the only mechanism documented as bounding a bubble against battle speed could not run at any
## reachable speed. CLAUDE.md's family: a clause that cannot fail returns the answer you were
## already holding, and it fails toward what the author expected.
##
## ⛔ THE DELETION IS BEHAVIOUR-PRESERVING BY CONSTRUCTION, SO NO BEHAVIOURAL ARM CAN RED ON IT —
## dividing by 1.0 and not dividing are the same number. What this file pins is the INVARIANT that
## makes the deletion safe, and the mutation is to break the invariant rather than the arithmetic:
## raise SUPPRESS_AT_LABEL so an engine scale above 1.0 becomes spawnable, and the first arm reds
## naming the shortening as newly load-bearing.
##
## It is also the dead-code half of a measured number that is NOT ours to change — a voiceless
## quip's 2.0 hold is 2 BATTLE seconds, which at the default engine 0.25 is 8.0 REAL seconds,
## against ~2.8s for the same line once it is voiced (the voiced path runs on the real clock since
## 2026-09-14). Identical content, 2.9x apart. That is a pacing call for struktured, who has ruled
## on battle pacing before; this file states the figure and changes nothing about it.

const BUBBLE := preload("res://src/battle/BattleSpeechBubble.gd")
const SCENE := preload("res://src/battle/BattleScene.gd")


func _spawnable_engine_scales() -> Array:
	## Derived from the two sources that decide it, never listed: the shipped ladder and the
	## threshold spawn() actually compares against.
	var out: Array = []
	for e in SCENE.BATTLE_SPEEDS:
		if float(e) < BUBBLE.SUPPRESS_TIME_SCALE:
			out.append(float(e))
	return out


func test_no_speed_a_bubble_can_spawn_at_would_have_been_divided() -> void:
	## THE INVARIANT THE DELETION RESTS ON, and the arm the mutation hits.
	var spawnable: Array = _spawnable_engine_scales()
	assert_gt(spawnable.size(), 0,
		"PREMISE: some shipped speed must allow a bubble, or this whole surface is dead")
	for e in spawnable:
		assert_lte(e, 1.0,
			"engine %s can spawn a bubble AND exceeds 1.0, so the removed `/ maxf(1.0, time_scale)` shortening is load-bearing again — restore it or justify the hold at that speed" % [e])


func test_the_suppression_threshold_is_the_only_thing_separating_them() -> void:
	## CONTROL for the arm above: without a suppressed speed above 1.0 in the ladder, "nothing
	## spawnable exceeds 1.0" would be true of a ladder that simply has no fast speeds, and the
	## invariant would be vacuous.
	var suppressed_above_one: int = 0
	for e in SCENE.BATTLE_SPEEDS:
		if float(e) >= BUBBLE.SUPPRESS_TIME_SCALE and float(e) > 1.0:
			suppressed_above_one += 1
	assert_gt(suppressed_above_one, 0,
		"the ladder must still carry speeds above 1.0 that suppression removes, or the invariant above is about an empty set: %s" % [SCENE.BATTLE_SPEEDS])


func test_the_ladder_and_the_threshold_are_read_from_their_owners() -> void:
	## FLOOR: a rename of either source must red here by NAME rather than silently emptying the
	## derived list, which would make every arm above vacuously true.
	assert_true("BATTLE_SPEEDS" in SCENE, "BattleScene.BATTLE_SPEEDS")
	assert_true("SUPPRESS_TIME_SCALE" in BUBBLE, "BattleSpeechBubble.SUPPRESS_TIME_SCALE")
	assert_true("SUPPRESS_AT_LABEL" in BUBBLE, "BattleSpeechBubble.SUPPRESS_AT_LABEL")
	assert_true("LABEL_PER_ENGINE" in BUBBLE, "BattleSpeechBubble.LABEL_PER_ENGINE")
	assert_eq(BUBBLE.SUPPRESS_TIME_SCALE, BUBBLE.SUPPRESS_AT_LABEL / BUBBLE.LABEL_PER_ENGINE,
		"the threshold must stay DERIVED from the label pair, not re-stated")


func test_a_requested_hold_reaches_the_bubble_unscaled() -> void:
	## The behaviour, at both spawnable speeds. This arm passed before the deletion too — stated
	## here so nobody reads it as the proof of anything, only as the pin going forward.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var before: float = Engine.time_scale
	for e in _spawnable_engine_scales():
		Engine.time_scale = e
		var b = BUBBLE.spawn(parent, Vector2(320, 240), "Tester %s" % e, "a line", Color.WHITE, 2.0)
		assert_not_null(b, "PREMISE: engine %s must actually spawn a bubble" % [e])
		if b != null:
			assert_almost_eq(b._hold_time, 2.0, 0.001,
				"the requested hold was altered at engine %s" % [e])
			b.queue_free()
	Engine.time_scale = before
	await get_tree().process_frame


func test_a_suppressed_speed_still_refuses_to_spawn() -> void:
	## CONTROL for the arm above: if spawn() stopped suppressing, the arms here would start
	## measuring speeds the divisor WOULD have divided, and silently change what this file means.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var before: float = Engine.time_scale
	Engine.time_scale = BUBBLE.SUPPRESS_TIME_SCALE
	var b = BUBBLE.spawn(parent, Vector2(320, 240), "Tester", "a line", Color.WHITE, 2.0)
	Engine.time_scale = before
	assert_null(b, "a bubble spawned at the suppression threshold, so suppression no longer fires first")
	await get_tree().process_frame
