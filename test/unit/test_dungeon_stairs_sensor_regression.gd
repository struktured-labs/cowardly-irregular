extends GutTest

## struktured 2026-07-18 (lightning cave): "it says there is a floor 2 and I
## can't seem to hit the right button." Root: stairs were AreaTransition-based
## walk-on sensors — AreaTransition's OWN body_entered handler fired on first
## graze, spent its one-shot _triggered latch (emitting to nobody), and the
## stairs went dead for the session (same latch-spend class as the tavern
## exit trap). Also audit defect #9: UP was a tight 32x32 vs DOWN's 64x64.
## Fix: inter-floor stairs are PLAIN Area2D sensors (no latch to spend) at
## the unified 48x48; only the floor-1 exit keeps a real AreaTransition.

const CAVES := ["res://src/maps/dungeons/DragonCave.gd", "res://src/maps/dungeons/WhisperingCave.gd"]


func _stair_region(path: String) -> String:
	var src: String = FileAccess.get_file_as_string(path)
	var i: int = src.find("# Stairs up")
	assert_gt(i, -1, "%s must have the stairs block" % path)
	var end: int = src.find("Boss trigger", i)
	return src.substr(i, (end - i) if end > -1 else 3000)


func test_interfloor_stairs_are_plain_sensors() -> void:
	for cave in CAVES:
		var region := _stair_region(cave)
		assert_true("var up_trans = Area2D.new()" in region,
			"%s: stairs-up must be a plain Area2D — an AreaTransition self-spends its one-shot latch on first graze and the stairs die" % cave)
		assert_true("var down_trans = Area2D.new()" in region,
			"%s: inter-floor stairs-down must be a plain Area2D for the same reason" % cave)


func test_stairs_use_unified_box() -> void:
	for cave in CAVES:
		var region := _stair_region(cave)
		assert_eq(region.count("InteractGeometry.STAIRS_BOX"), 3,
			"%s: up + inter-floor down + floor-1 exit all use the unified 48x48 (was 32x32 up / 64x64 down)" % cave)


func test_floor1_exit_keeps_real_transition() -> void:
	for cave in CAVES:
		var region := _stair_region(cave)
		assert_true("AreaTransitionScript.new()" in region,
			"%s: the floor-1 overworld exit still needs a real AreaTransition (it warps maps)" % cave)
		assert_true("transition_triggered.connect(_on_transition_triggered)" in region,
			"%s: floor-1 exit wiring preserved" % cave)


func test_sensor_fires_repeatedly_no_latch() -> void:
	# Behavioral: a plain Area2D sensor has no one-shot latch — enter/exit/enter
	# must fire body_entered twice (the dead-stairs class can't recur).
	var sensor := Area2D.new()
	add_child_autofree(sensor)
	InteractGeometry.setup_trigger_collision(sensor, InteractGeometry.STAIRS_BOX)
	var fires: Array = []
	sensor.body_entered.connect(func(b): fires.append(b))
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	var cs := CollisionShape2D.new()
	cs.shape = CircleShape2D.new()
	body.add_child(cs)
	add_child_autofree(body)
	body.global_position = Vector2(500, 500)
	sensor.global_position = Vector2.ZERO
	await get_tree().physics_frame
	body.global_position = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.global_position = Vector2(500, 500)
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.global_position = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(fires.size(), 2, "sensor must fire on EVERY entry — no spendable latch")
