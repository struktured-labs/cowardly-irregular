extends GutTest

## Regression test for the "trapped in the tavern" playtest bug (struktured
## 2026-07-18): the Dancing Tonberry's exit trigger sat on top of the
## entrance spawn point, so AreaTransition self-fired the instant the scene
## loaded — silently swallowed by GameLoop's in-flight transition guard,
## but it permanently spent AreaTransition's one-shot _triggered latch. The
## real exit then did nothing for the rest of the session no matter how the
## player aligned ("had to teleport out using the debugger").
##
## Runtime probes, not source pins: instantiates the real scene, ticks
## physics like GameLoop's fade-in window does, and drives the player
## through an actual approach to the door. Uses its own SubViewport/World2D
## so a leaked OverworldPlayer body from an unrelated earlier test (the
## default 2D physics space is shared tree-wide) can't spuriously overlap
## our exit trigger and poison the one-shot latch this test is asserting on.

const TavernScript = preload("res://src/maps/interiors/TavernInterior.gd")
const TILE := 32

var _viewport: SubViewport


func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	add_child(_viewport)


func after_each() -> void:
	_viewport.queue_free()


func _find_exit(tavern) -> Area2D:
	for t in tavern.transitions.get_children():
		if t.name == "Exit":
			return t
	return null


## Every 'D' (door) tile center in the authored layout — the visual feature
## the exit trigger is supposed to sit on.
func _door_tile_centers(tavern) -> Array:
	var centers: Array = []
	for y in range(tavern.TAVERN_LAYOUT.size()):
		var row: String = tavern.TAVERN_LAYOUT[y]
		for x in range(tavern.MAP_WIDTH):
			if x < row.length() and row[x] == "D":
				centers.append(Vector2((x + 0.5) * TILE, (y + 0.5) * TILE))
	return centers


func test_exit_trigger_covers_a_door_tile_and_does_not_self_fire_at_spawn() -> void:
	var tavern = TavernScript.new()
	_viewport.add_child(tavern)
	await get_tree().process_frame
	await get_tree().process_frame

	var exit := _find_exit(tavern)
	assert_not_null(exit, "tavern must build an Exit AreaTransition")
	var cs: CollisionShape2D = exit.get_child(0)
	assert_true(cs.shape is RectangleShape2D, "exit trigger should be a rectangle")

	var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
	var rect := Rect2(exit.global_position - half, (cs.shape as RectangleShape2D).size)

	# (a) The trigger must actually intersect at least one authored door
	# tile's center — proof the sensor sits on the visual feature, not
	# buried in a wall or shifted off it (the "hard to align" complaint).
	var doors := _door_tile_centers(tavern)
	assert_gt(doors.size(), 0, "layout should declare at least one D door tile")
	var covers_a_door := false
	for c in doors:
		if rect.has_point(c):
			covers_a_door = true
			break
	assert_true(covers_a_door,
		"exit trigger rect %s must contain at least one door tile center (got none of %s)" % [rect, doors])

	# (b) Simulate GameLoop's fade-in window: several physics frames with
	# zero player input right after spawn. The one-shot _triggered latch
	# must NOT already be spent — that's what bricked the real exit.
	exit.body_entered.connect(func(b): print("[DIAG] fired for body=%s is_ours=%s pos=%s player_pos=%s exit_rect=%s" % [b, b == tavern.player, (b as Node2D).global_position if b is Node2D else "?", tavern.player.global_position, rect]))
	for i in range(20):
		await get_tree().physics_frame
	assert_false(exit._triggered,
		"exit's one-shot _triggered latch fired at spawn with no player input — self-trigger bug that permanently bricks the real exit")

	tavern.free()


## End-to-end: walk the player from the entrance spawn toward the door and
## confirm the SAME exit instance still fires exactly once when they get
## there — the actual repro path, not just geometry.
func test_walking_from_spawn_to_door_exits_exactly_once() -> void:
	var tavern = TavernScript.new()
	_viewport.add_child(tavern)
	await get_tree().process_frame
	await get_tree().process_frame

	# Settle through the fade-in-equivalent window before starting the walk,
	# same as a real GameLoop transition would before input unlocks.
	for i in range(10):
		await get_tree().physics_frame

	var fired: Array = []
	tavern.area_transition.connect(func(tm, ts): fired.append([tm, ts]))

	# Walk from spawn straight down through both door rows to the outer
	# threshold, in small steps (no wall collision in this legacy scene —
	# see InteriorPlacementSweep.gd — so a straight walk is a faithful sim).
	var start: Vector2 = tavern.player.position
	var target := Vector2(start.x, 17.9 * TILE)
	var steps := 30
	for i in range(steps + 1):
		tavern.player.position = start.lerp(target, float(i) / steps)
		await get_tree().physics_frame

	assert_eq(fired.size(), 1,
		"walking through the door should trigger exactly one area_transition — got %s" % [fired])
	if fired.size() > 0:
		assert_eq(fired[0][0], "harmonia_village")
		assert_eq(fired[0][1], "bar_exit")

	tavern.free()
