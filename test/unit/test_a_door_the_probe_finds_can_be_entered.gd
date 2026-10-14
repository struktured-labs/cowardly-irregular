extends GutTest

## 🐛 EVERY PRESS-TO-ENTER DOOR ATE THE PLAYER'S PRESS IN A BAND ONE PROBE-REACH DEEP.
##
## `AreaTransition.interact()` required `_player_in_zone`, and the probe is the ONLY caller that
## can reach it — `_input` runs before `_unhandled_input` and calls set_input_as_handled(), so an
## overlapping press is consumed there and never becomes an `interaction_requested`. The probe
## therefore only ever calls `interact()` when the player is OUTSIDE the box, which is exactly the
## state the guard refused. The press printed "Found: <door>" and did nothing.
##
## 🔑 MEASURED IN struktured's 2026-10-13 LOG, which is a natural experiment on both sides of the
## band edge. VillageEntrance is authored at (272, 1616); `OverworldScene` shifts the node up
## `TILE_SIZE * 3` and gives it a 64x192 box, so the box bottom edge sits at y = 1616.
##
##     press (272, 1636.4)  probe point 1556.4  INSIDE the box   -> "Found", no Triggering  🐛
##     press (272, 1697.6)  probe point 1617.6  1.6 px PAST it   -> honest "Nothing found"
##     press (272, 1799.6)  probe point 1719.6  outside          -> honest "Nothing found"
##
## He pressed four times, walked away, came back, and only got in once his BODY was inside the box.
##
## ⛔ WHY THE EXISTING PRESS CENSUS IS GREEN THROUGH THIS. `test_a_landmark_that_answers_nothing_
## teaches_you_to_stop_pressing` builds its corpus as "every node with interact()", so every door
## is in it — but `_press_lands_on` returns the SELECTED node and the file never calls `interact()`.
## Selection is not effect: the probe selects the door in the whole band, and the game drops it.
## A file named for landmarks that answer nothing is blind to the one class that answered nothing.
##
## ⚠️ THE DOOR COUNT IS STORY-FLAG DEPENDENT AND IS REPORTED, NEVER PINNED. Castle Harmonia
## and the W2 portal are built only once their flags are set, so this file measured 12 doors run
## alone and 14 in a batch that had set them -- same tree, same commit. A pinned count would red
## on a correct change and on nothing else; the floor below is an anti-vacuity bound, not a census.
##
## ⚠️ THE ARM BELOW ASSERTS EFFECT, NOT SELECTION — it emits the player's real
## `interaction_requested` and waits for `transition_triggered`. Nothing here reproduces the probe.

const W1 := "res://src/exploration/OverworldScene.gd"
const BODY_RADIUS := 8.0

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


## The reach the CONTROLLER will use, read the way it reads it — not a constant copied in here.
func _reach() -> float:
	return InteractGeometry.PROBE_REACH_MODE7 if Mode7Overlay.is_active else InteractGeometry.PROBE_REACH_FLAT


func _doors() -> Array:
	var out: Array = []
	var stack: Array = [_w]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is AreaTransition and (n as AreaTransition).require_interaction:
			out.append(n)
	return out


## The box's bottom edge in world space, read off the node's own CollisionShape2D.
func _bottom_edge(door: Node2D) -> float:
	for c in door.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			var r: RectangleShape2D = (c as CollisionShape2D).shape
			return door.global_position.y + c.position.y + r.size.y * 0.5
	return NAN


func _fits(at: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


## Every interact()-bearing area whose box contains `at` -- the probe's CANDIDATE SET at that
## point. This is a filter, not the probe's arbitration: the arm below only ever uses positions
## where this returns exactly ONE candidate, so nearest-wins has nothing to decide and no part of
## the selection logic is reproduced here.
func _candidates_at(at: Vector2) -> Array:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = at
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = 4
	var out: Array = []
	for hit in _vp.world_2d.direct_space_state.intersect_point(q, 32):
		var c = hit.get("collider")
		if c != null and is_instance_valid(c) and c is Node2D and c.has_method("interact"):
			out.append(c)
	return out


## A standable spot under `door` from which the door is the ONLY thing a press can reach: body clear
## of the box, probe point inside it, no second candidate. Vector2.INF when the band is contested
## everywhere, which is a fact about that door's surroundings and is reported, never asserted away.
func _uncontested_band_feet(door: Node2D, reach: float) -> Vector2:
	var bottom := _bottom_edge(door)
	if is_nan(bottom):
		return Vector2.INF
	var depth := BODY_RADIUS + 2.0
	while depth <= reach - 2.0:
		for dx in [0.0, -32.0, 32.0, -64.0, 64.0]:
			var feet := Vector2(door.global_position.x + dx, bottom + depth)
			if not _fits(feet):
				continue
			var cands := _candidates_at(feet + Vector2(0.0, -reach))
			if cands.size() == 1 and cands[0] == door:
				return feet
		depth += 6.0
	return Vector2.INF


func test_the_corpus_is_real() -> void:
	await _build()
	assert_not_null(_w.player, "CONTROL: the W1 scene must build a player for the probe to run from")
	var doors := _doors()
	assert_gt(doors.size(), 8, "CONTROL: W1 must carry its press-to-enter doors, found %d" % doors.size())
	var boxed := 0
	for d in doors:
		if not is_nan(_bottom_edge(d)):
			boxed += 1
	assert_eq(boxed, doors.size(), "CONTROL: every door must expose a rectangle box; %d of %d did" % [boxed, doors.size()])
	assert_gt(_reach(), 0.0, "CONTROL: the probe reach must be positive")
	## Without this a false RED is indistinguishable from the defect: an unwired controller
	## push_warnings and drops every press, so no door would fire for a reason of my own making.
	assert_not_null(_w.controller, "CONTROL: the scene must build the controller that owns the probe")
	assert_eq(_w.controller.player, _w.player, "CONTROL: the controller's player must be the scene's player, else the probe never runs")
	gut.p("  %d press-to-enter doors, reach %.0f px" % [doors.size(), _reach()])


## ⛔ THE ARM THAT MATTERS: stand in the band below each door -- body clear of the box, probe
## point inside it -- face the door, press, and A TRANSITION MUST OPEN.
##
## ⚠ IT IS "A TRANSITION", NOT "THIS DOOR", AND THE DIFFERENCE IS MEASURED RATHER THAN ASSUMED.
## My first version asserted the door under test opens, and it red on Sandrift and Ironhaven --
## correctly, for a reason that is not this defect. Both sit directly north of a dragon cave on the
## same x (Sandrift 656,3536 over Lightning 656,3664; Ironhaven 5232,3792 over Fire 5232,3568), so
## from the band below the village the CAVE is 46 px away and the village 174 px: the cave is
## between the player and the door, and nearest-wins hands it the press. That is the arbitration
## `_a_nearer_transition_has` documents, working. Asserting "this door" would have forced a
## relocation to protect behaviour that is already right -- the coincidental-ratchet trap one layer
## up. What the player is owed is that the press is ANSWERED; which of two stacked destinations
## answers is a separate, pre-existing design question, reported below and not decided here.
func test_every_door_the_probe_finds_can_be_entered() -> void:
	await _build()
	var reach := _reach()
	var player = _w.player
	var doors := _doors()
	doors.sort_custom(func(a, b): return str(a.name) < str(b.name))
	## Every door is watched, so a press answered by a NEARER SIBLING is visible as such rather
	## than counting as silence. Without this the two stacked pairs read as the defect.
	var answered: Array = []
	for d in doors:
		d.transition_triggered.connect(func(_m, _s, who = d): answered.append(str(who.name)))
	var dead: Array = []
	var contested: Array = []
	var covered := 0
	for door in doors:
		var feet := _uncontested_band_feet(door, reach)
		if feet == Vector2.INF:
			contested.append(str(door.name))
			continue
		## `_triggered` latches per instance and the game clears it on body_exited. Each press here
		## is a fresh approach, so clear it on every door or an earlier press starves a later one.
		for d in doors:
			d._triggered = false
		player.global_position = feet
		player.current_direction = OverworldPlayer.Direction.UP
		player.pending_click_target = null
		await get_tree().physics_frame
		## The precondition this whole file is about: the probe path runs only with NO overlap.
		assert_false(door._player_in_zone,
			"CONTROL: %s must not already contain the player at %s; the band was mis-derived" % [door.name, str(feet)])
		answered.clear()
		player.interaction_requested.emit()
		await get_tree().physics_frame
		covered += 1
		if not (str(door.name) in answered):
			dead.append("%s (pressed at %s, %.0f px under its box, sole candidate there)" % [
				door.name, str(feet), feet.y - _bottom_edge(door)])
	assert_gt(covered, 5,
		"CONTROL: only %d of %d doors had an uncontested spot in their band; a green would mean little" % [covered, doors.size()])
	dead.sort()
	for d in dead:
		gut.p("  DEAD: %s" % d)
	assert_eq(dead, [],
		"%d of %d doors found the press and dropped it -- the player faces the door, is the only thing it can reach, presses, and nothing happens: %s" % [
			dead.size(), covered, "; ".join(dead)])
	contested.sort()
	for c in contested:
		gut.p("  no uncontested spot in the band (stacked destination or prop): %s" % c)
	gut.p("  %d of %d doors enterable from their band; %d contested throughout" % [
		covered, doors.size(), contested.size()])


## ⛔ CONTROL ON THE OTHER CLASS: auto-enter transitions must stay auto-enter. Village and interior
## exits set require_interaction = false and fire on touch; a press from outside must not warp them.
func test_an_auto_enter_transition_still_ignores_a_press() -> void:
	var t := AreaTransition.new()
	t.target_map = "harmonia_village"
	t.target_spawn = "entrance"
	t.require_interaction = false
	add_child_autofree(t)
	var fired := [false]
	t.transition_triggered.connect(func(_m, _s): fired[0] = true)
	t.interact(null)
	assert_false(fired[0], "an auto-enter transition must fire on touch only, never on a press from outside it")
