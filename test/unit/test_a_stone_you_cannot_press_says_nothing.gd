extends GutTest

## `ReadableProp` was the one interactable class that never learned Mode 7.
##
## Every sibling widens its zone when `InteractGeometry.is_mode7()` — Signpost 48 -> 128 with the
## 1.67 billboard Y-stretch, chests 40 -> 128, NPCs 44 -> 128 — because the overworld scales the
## world and displaces the ground under the player. ReadableProp built an unconditional 28x28 box in
## `_ready`, privately, in its own file, never through the geometry contract. Under the Mode 7 press
## probe (`PROBE_REACH_MODE7` = 80px in the facing direction) that is a 28px window at exactly arm's
## length — see the measurement below for how narrow that turns out to be in practice.
##
## 🔑 IT WAS INVISIBLE BECAUSE OF WHERE IT WAS USED, NOT BECAUSE IT WAS SUBTLE. The class shipped
## with exactly one consumer — Phil's notebook in Harmonia, a FLAT village, where 28x28 is correct
## and deliberate (it sits beside Phil, and a wider box steals his press). A defect that only exists
## in a context nobody had entered yet reads as working code for as long as nobody enters it.
##
## The mutation arm below is the whole point: it puts the shipped 28x28 box back and re-runs the same
## sweep, so this file cannot pass by describing geometry that was never load-bearing.
##
## ⚠️ MEASURED, AND NOT THE NUMBER I EXPECTED TO WRITE: sweeping the standable cells within two of
## the stone x 4 facings, the Mode 7 zone answers 73 presses and the 28x28 box answers 4. So the old
## geometry was not IMPOSSIBLE to press — it was pressable from a razor alignment the player has no
## way to know about, which is worse to describe and identical to play. Say 73-vs-4, not "it could
## never be opened"; the assertion below is `live > before` for that reason and not `before == 0`.

const BODY_RADIUS := 8.0
const W1 := "res://src/exploration/OverworldScene.gd"

var _vp: SubViewport = null
var _w: Node2D = null


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	_w = load(W1).new()
	_vp.add_child(_w)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _stone() -> Node2D:
	for n in _w.get_children():
		if n is Node2D and n.get_script() != null \
				and str(n.get_script().resource_path).get_file().get_basename() == "ReadableProp":
			return n as Node2D
	return null


func _fits(at: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


## OverworldController's press, reproduced: the facing probe, then the standing probe, then
## nearest-by-anchor among whatever has an interact().
func _press_lands_on(feet: Vector2, facing: Vector2) -> Node:
	var space := _vp.world_2d.direct_space_state
	for point in [feet + facing * InteractGeometry.PROBE_REACH_MODE7, feet]:
		var q := PhysicsPointQueryParameters2D.new()
		q.position = point
		q.collide_with_areas = true
		q.collide_with_bodies = false
		q.collision_mask = 4
		var best: Node = null
		var best_d := INF
		for hit in space.intersect_point(q):
			var c = hit.get("collider")
			if c == null or not is_instance_valid(c) or not c.has_method("interact") or not (c is Node2D):
				continue
			var d: float = InteractGeometry.anchor(c).distance_squared_to(feet)
			if d < best_d:
				best_d = d
				best = c
		if best != null:
			return best
	return null


## Every standable cell within two cells, every facing — how many of those presses open the stone.
func _openable_from(stone: Node2D, step: float) -> int:
	var hits := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var feet: Vector2 = stone.global_position + Vector2(dx * step, dy * step)
			if not _fits(feet):
				continue
			for facing in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				if _press_lands_on(feet, facing) == stone:
					hits += 1
	return hits


func test_the_survey_stone_can_actually_be_opened() -> void:
	await _build()
	assert_true(Mode7Overlay.is_active,
		"PRECONDITION: W1 must be running Mode 7, or this file measures the flat branch and proves nothing")
	var stone := _stone()
	assert_not_null(stone, "the W1 overworld must carry a ReadableProp — the Survey Stone")
	if stone == null:
		return
	var step: float = float(int(_w.MAP_SCALE) * int(_w.TILE_SIZE))

	var live := _openable_from(stone, step)

	# THE MUTATION: put the shipped geometry back — an unconditional 28x28 box at the same anchor.
	for c in stone.get_children():
		if c is CollisionShape2D:
			c.queue_free()
	await get_tree().process_frame
	var old := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 28)
	old.shape = rect
	stone.add_child(old)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before := _openable_from(stone, step)

	gut.p("MEASURED  mode7 zone: %d openable (cell,facing) presses   28x28 box: %d" % [live, before])
	assert_gt(live, 0,
		"the Survey Stone cannot be opened from ANY standable cell within two cells, from any facing — " +
		"it draws nothing and answers nothing, which is indistinguishable from not being there")
	assert_gt(live, before,
		"the Mode 7 zone (%d presses) is no better than the 28x28 box it replaced (%d) — " % [live, before] +
		"then this file is describing a change that does not do anything")


func test_the_stone_reads_the_players_own_file() -> void:
	## The provider is re-invoked on every open, so the pages are a live read, not a fixed array.
	await _build()
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState required")
		return
	var prior: Dictionary = gs.story_flags.duplicate(true)

	gs.story_flags.erase("secret_w1_sunken_ring")
	gs.story_flags.erase("chest_w1_secret_sunken_ring")
	var shut: Array = _w._survey_stone_entries()

	gs.set_story_flag("secret_w1_sunken_ring", true)
	var opened: Array = _w._survey_stone_entries()

	gs.set_story_flag("chest_w1_secret_sunken_ring", true)
	var emptied: Array = _w._survey_stone_entries()
	gs.story_flags = prior

	assert_gt(shut.size(), 3, "the stone must have pages before anything is discovered (%d)" % shut.size())
	assert_eq(opened.size(), shut.size(),
		"finding the ring REPLACES the final entry rather than adding one — same page count")
	assert_eq(emptied.size(), opened.size() + 1, "emptying the ring appends the amended inventory")
	assert_true(str(shut[shut.size() - 1]).contains("does not open"),
		"undiscovered, the last page must still be the surveyor's dead end")
	assert_true(str(opened[opened.size() - 1]).contains("It opens"),
		"discovered, the last page must be the annotation — the stone noticing what the player did")


## A press you CAN land is still a press nobody makes if nothing says the statue is a thing.
##
## Phil's notebook survives being an invisible hotspot because Harmonia is dense and players press
## everything in a village. W1 already has three other STATUE/RUINS/STONE_CIRCLE landmarks that
## answer nothing, so by the time a player reaches this one the overworld has taught them that
## scenery is scenery. The label is the affordance, and it is ROW_ACTION because this is a press.
func test_the_stone_announces_itself_when_you_stand_at_it() -> void:
	await _build()
	var stone := _stone()
	assert_not_null(stone, "PRECONDITION: the Survey Stone must exist")
	if stone == null:
		return
	var label: Label = stone._label
	assert_not_null(label, "a ReadableProp must carry a proximity label — it draws nothing else")
	if label == null:
		return
	assert_eq(label.text, "The Survey Stone", "the label names the prop, as every sibling's does")
	assert_false(label.visible, "and stays hidden until the player is at it")

	stone._player_nearby = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(label.visible, "standing at the stone must surface its name")

	stone._player_nearby = false
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(label.visible, "and walking off must take it away again")


func test_the_flat_branch_is_untouched() -> void:
	## Phil's notebook is the class's only other consumer and it is FLAT; the fix must be additive.
	assert_eq(InteractGeometry.READABLE_BOX_FLAT, Vector2(28.0, 28.0),
		"the flat box is the shipped, playtested value — widening it steals Phil's press")
	## FORCED, not assumed: is_active is a static that an earlier arm in this file leaves true, so a
	## `if not is_active` guard here would skip itself silently and read as a passing arm.
	var prior_mode7: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false
	var prop = load("res://src/exploration/ReadableProp.gd").new()
	add_child_autofree(prop)
	await get_tree().process_frame
	Mode7Overlay.is_active = prior_mode7
	var shape: CollisionShape2D = null
	for c in prop.get_children():
		if c is CollisionShape2D:
			shape = c
	assert_not_null(shape, "a ReadableProp must build its own zone when none is authored")
	if shape == null:
		return
	assert_true(shape.shape is RectangleShape2D, "flat props keep the rectangle")
	assert_eq((shape.shape as RectangleShape2D).size, InteractGeometry.READABLE_BOX_FLAT,
		"and keep the exact size they shipped with")
