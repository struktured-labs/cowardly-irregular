extends GutTest

## W1 draws nine overworld landmarks and, until the Survey Stone, pressed back with exactly none.
##
## That is not a missing feature, it is an anti-feature: the first three inert landmarks TEACH the
## player that overworld scenery is scenery, and the lesson is retroactive — every readable placed
## afterwards inherits it. The Survey Stone's own header records the problem ("W1 already has three
## other STATUE/RUINS/STONE_CIRCLE landmarks that answer nothing"). This file closes it.
##
## ⚠️ THE PROPERTY IS "FACE IT AND PRESS", NOT "NO PRESS MOVES" — and the difference is the whole
## reason this file exists rather than a coverage list. Eight new 128px zones on a map authored
## around thirteen chests do move presses: measured, three chests each lose 1-2 of their broad
## 5x5 press census to a lore prop. Every one of those is the player standing BESIDE the chest and
## facing AWAY from it, toward the new landmark — the facing-biased probe doing exactly its job.
## Asserting zero movement would have forced three landmarks to relocate to protect behaviour that
## is correct. What a player is owed is narrower and checkable: walk up to a thing, face it, press,
## and get it. The arm below measures that set with the lore props present and again with them
## freed, and fails only on a MEMBER THE LORE PROPS INTRODUCED.
##
## 🔑 Signposts are not in any of this. They have no interact() — they are proximity-read on
## body_entered — so they can neither rob a press nor be robbed of one, and the bridge sign two
## cells from The Second Ring is a non-event. Measured before assuming: all 16 W1 signposts score
## zero presses, which reads as a catastrophe and is just the wrong corpus.

const BODY_RADIUS := 8.0
const W1 := "res://src/exploration/OverworldScene.gd"

var _vp: SubViewport = null
var _w: Node2D = null
var _step: float = 64.0


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	_w = load(W1).new()
	_vp.add_child(_w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step = float(int(_w.MAP_SCALE) * int(_w.TILE_SIZE))


func _base(n: Node) -> String:
	if n.get_script() == null:
		return "?"
	return str(n.get_script().resource_path).get_file().get_basename()


## The corpus is "has interact()", not a class list — a class list is a to-do, not a corpus.
func _interactables() -> Array:
	var out: Array = []
	var stack: Array = [_w]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node2D and n.has_method("interact"):
			out.append(n)
	return out


func _nodes_named(base: String) -> Array:
	var out: Array = []
	var stack: Array = [_w]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node2D and _base(n) == base:
			out.append(n)
	return out


func _lore_props() -> Array:
	var out: Array = []
	for p in _nodes_named("ReadableProp"):
		if str(p.name).begins_with("Lore_"):
			out.append(p)
	return out


func _fits(at: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


## OverworldController's press, reproduced: facing probe, then standing probe, nearest by anchor.
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


## Broad census: every standable cell within two, every facing. Informational, printed not asserted.
func _presses_for(prop: Node2D) -> int:
	var hits := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var feet: Vector2 = prop.global_position + Vector2(dx * _step, dy * _step)
			if not _fits(feet):
				continue
			for facing in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				if _press_lands_on(feet, facing) == prop:
					hits += 1
	return hits


## The contract: from each standable cell touching the prop, facing it must open IT. Returns the
## cells where it does not, as "(dx,dy)" — the offender list, not a count.
func _face_failures(prop: Node2D) -> Array:
	var bad: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var feet: Vector2 = prop.global_position + Vector2(dx * _step, dy * _step)
			if not _fits(feet):
				continue
			var facing := Vector2(-dx, 0) if absi(dx) >= absi(dy) else Vector2(0, -dy)
			if _press_lands_on(feet, facing) != prop:
				bad.append("(%d,%d)" % [dx, dy])
	return bad


func test_every_landmark_answers_something() -> void:
	await _build()
	var marks: Array = _nodes_named("Landmark")
	assert_gt(marks.size(), 5, "CONTROL: %d landmarks collected — the scan is broken" % marks.size())
	var readables: Array = _nodes_named("ReadableProp")
	assert_gt(readables.size(), 5, "CONTROL: %d readables collected" % readables.size())

	var mute: Array = []
	for lm in marks:
		var answered := false
		for r in readables:
			if lm.global_position.distance_to(r.global_position) < _step:
				answered = true
		if not answered:
			var cx := int(round((lm.position.x - _w.TILE_SIZE / 2.0) / _step))
			var cy := int(round((lm.position.y - _w.TILE_SIZE / 2.0) / _step))
			mute.append("landmark at cell (%d,%d) draws and answers nothing — give it a row in W1Landmarks.table(), or delete the landmark" % [cx, cy])
	mute.sort()
	assert_eq(mute, [],
		"a W1 landmark is scenery that cannot be pressed — three of those in a row teach the " +
		"player to stop pressing, and every readable placed afterwards inherits it: %s" % ", ".join(mute))


func test_every_landmark_readable_can_actually_be_pressed() -> void:
	await _build()
	assert_true(Mode7Overlay.is_active,
		"PRECONDITION: W1 must be running Mode 7, or this measures the flat branch and proves nothing")
	var props: Array = _lore_props()
	assert_eq(props.size(), 8, "CONTROL: expected 8 lore props, found %d" % props.size())

	var unreachable: Array = []
	for p in props:
		var n := _presses_for(p)
		var face := _face_failures(p)
		gut.p("  %-28s %3d presses   face-fails %s" % [str(p.name), n, str(face)])
		if n <= 0:
			unreachable.append("%s (%s) — no standable cell within two opens it from any facing" % [str(p.name), str(p.display_name)])
		elif not face.is_empty():
			unreachable.append("%s (%s) — standing at %s and facing it does NOT open it; move that row's cell in W1Landmarks.table()" % [str(p.name), str(p.display_name), ", ".join(face)])
	unreachable.sort()
	assert_eq(unreachable, [],
		"a landmark now carries a label promising a press it cannot answer — worse than leaving " +
		"it mute, because the label is the promise: %s" % ", ".join(unreachable))


## The load-bearing arm. Eight new zones may MOVE presses (they do, measurably) but may not take
## a neighbour's own face-it-and-press. Baseline is measured in the same run, with the lore props
## freed, so W1's three pre-existing AreaTransition face-failures stay this file's business to
## report and nobody else's to fix.
func test_no_landmark_readable_takes_a_neighbours_press() -> void:
	await _build()
	var props: Array = _lore_props()
	assert_eq(props.size(), 8, "CONTROL: expected 8 lore props, found %d" % props.size())

	var others: Array = []
	for n in _interactables():
		if not str(n.name).begins_with("Lore_"):
			others.append(n)
	assert_gt(others.size(), 10,
		"CONTROL: only %d non-lore interactables collected — with nothing to rob, [] is free" % others.size())

	var with_lore: Dictionary = {}
	for n in others:
		with_lore[n] = _face_failures(n)

	for p in props:
		p.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var introduced: Array = []
	for n in others:
		if not is_instance_valid(n):
			continue
		var baseline: Array = _face_failures(n)
		for cell in with_lore[n]:
			if not baseline.has(cell):
				introduced.append("%s %s at cell (%.0f,%.0f): standing %s and facing it opens a landmark instead — move that row's cell in W1Landmarks.table()" % [
					_base(n), str(n.name), n.global_position.x / _step, n.global_position.y / _step, cell])
	introduced.sort()
	assert_eq(introduced, [],
		"a landmark readable took a press a neighbour used to answer: both props work, the " +
		"player just walked up to the wrong one: %s" % ", ".join(introduced))


## CONTROL: the arm above must be able to SEE a theft, or its [] is decoration. Measured on a real
## neighbour rather than a fixture — a planted thief on a chest is the shape the arm defends against.
func test_the_arm_can_see_a_stolen_press() -> void:
	await _build()
	var chests: Array = _nodes_named("TreasureChest")
	assert_gt(chests.size(), 0, "CONTROL: chests collected")
	var victim: Node2D = chests[0]
	var before: Array = _face_failures(victim)
	assert_true(before.is_empty(),
		"CONTROL: the victim answers a faced press from every adjacent cell before the thief arrives, got %s" % str(before))

	var thief = load("res://src/exploration/ReadableProp.gd").new()
	thief.position = victim.position + Vector2(4, 4)
	thief.setup("thief", func(): return ["x"])
	_w.add_child(thief)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after: Array = _face_failures(victim)
	thief.queue_free()
	await get_tree().physics_frame
	assert_gt(after.size(), 0,
		"a prop planted 4px inside a chest must take faced presses from it — if it does not, " +
		"_face_failures cannot detect theft and the real arm passes for free")


func test_every_page_is_authored_and_formatted() -> void:
	var lore = W1Landmarks.new()
	var rows: Array = lore.table()
	assert_eq(rows.size(), 8, "CONTROL: the table ships eight rows, found %d" % rows.size())

	var bad: Array = []
	for row in rows:
		var fn: String = str(row["fn"])
		if not lore.has_method(fn):
			bad.append("%s — table() names a provider W1Landmarks does not define" % fn)
			continue
		var pages = lore.call(fn)
		if not (pages is Array) or pages.size() < 2:
			bad.append("%s — a landmark worth a label is worth more than one page" % fn)
			continue
		for e in pages:
			var body: String = str(e.get("body", "")) if e is Dictionary else str(e)
			if body.strip_edges().length() < 40:
				bad.append("%s — a page body of %d chars is a stub" % [fn, body.strip_edges().length()])
			# An unsubstituted token means a `%` arm lost its operand and the player reads the format string.
			if body.contains("%d") or body.contains("%s"):
				bad.append("%s — an unformatted token reached the page: %s" % [fn, body.substr(0, 60)])
	bad.sort()
	assert_eq(bad, [], "a landmark page is unauthored or unformatted: %s" % ", ".join(bad))


## The whole reason these are providers and not constants: the pages re-read the player's own file.
func test_the_pages_answer_the_players_own_state() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState required")
		return
	var lore = W1Landmarks.new()
	var prior_flags: Dictionary = gs.story_flags.duplicate(true)
	var prior_corruption: float = gs.corruption_level
	var prior_gold: int = gs.party_gold

	gs.corruption_level = 0.0
	var calm: String = str(lore.counting_stones())
	gs.corruption_level = 0.5
	var crawling: String = str(lore.counting_stones())

	gs.party_gold = 10
	var poor: String = str(lore.well_register())
	gs.party_gold = 5000
	var rich: String = str(lore.well_register())

	gs.set_story_flag("fire_dragon_defeated", false)
	var unburned: String = str(lore.last_camp())
	gs.set_story_flag("fire_dragon_defeated", true)
	var burned: String = str(lore.last_camp())

	gs.corruption_level = prior_corruption
	gs.party_gold = prior_gold
	gs.story_flags = prior_flags

	assert_ne(calm, crawling, "the warden's count must change as corruption rises — that is the page")
	assert_ne(poor, rich, "the well register reads the purse it is talking to")
	assert_ne(unburned, burned, "the last camp gains the fifth party's line once the grotto is cleared")
	assert_true(crawling.contains("Nine"), "at 0.5 corruption the warden counts nine")
	assert_true(calm.contains("Eight, still"), "at 0.0 corruption the vigil is boring, which is the joke")


## ⛔ THE PROVIDER ARMS ABOVE CALL A FRESH W1Landmarks AND PROVE NOTHING ABOUT THE PLACED PROP.
## A ReadableProp holds its provider as a Callable, and a Callable does not keep a RefCounted
## alive — it stores an ObjectID. The table object lives on the scene (`var _lore`) for exactly
## that reason, and if that reference is ever dropped every prop still labels itself, still
## answers the press probe, still passes every other arm in this file, and opens NOTHING:
## _fetch_entries() returns [] and interact() returns early, silently. So press the real ones.
func test_pressing_a_placed_landmark_actually_opens_it() -> void:
	await _build()
	var props: Array = _lore_props()
	assert_eq(props.size(), 8, "CONTROL: expected 8 lore props, found %d" % props.size())

	var dead: Array = []
	for p in props:
		p.interact(null)
		await get_tree().process_frame
		if not p.is_open():
			dead.append("%s (%s) — pressed and nothing opened; its provider Callable is dead, which means nothing holds W1Landmarks alive" % [str(p.name), str(p.display_name)])
		else:
			if p._entries.size() < 2:
				dead.append("%s — opened with %d pages" % [str(p.name), p._entries.size()])
			p._close_panel()
			await get_tree().process_frame
	dead.sort()
	assert_eq(dead, [],
		"a landmark labels itself, answers the probe, and opens nothing when pressed — the " +
		"loudest possible promise attached to the quietest possible failure: %s" % ", ".join(dead))
