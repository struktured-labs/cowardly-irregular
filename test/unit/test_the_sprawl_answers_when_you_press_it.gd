extends GutTest

## W2 drew four pieces of street furniture — two hydrants, two bus stops — and answered with none of
## them. That is the anti-feature W1 closed: a player who presses the first two and gets silence has
## been TAUGHT that overworld scenery is scenery, and walks past every readable placed afterwards.
##
## The guard is the one W1 earned, in the shape of its own defect. Cell, art type and pages used to
## live in two places (OverworldScene._place_landmarks vs the lore table), so moving a landmark left
## its readable standing on the old cell with the label still promising a press. W2Landmarks.table()
## is the single source, and the arms below check the CONSUMER rather than the table: the scene it
## built, the press that reaches it, and the panel that opens.
##
## ⚠️ The press arms are not "a readable exists". Dispatch is nearest-by-anchor
## (OverworldController._pick_nearest_interactable), and `w2_bus_hipotion` sits two cells under The
## Timetable — so a readable can be placed, labelled, and still lose every press to a chest.
##
## 📌 MEASURED, and the reason _face_split exists rather than W1's flat assertion. The Timetable's
## three SOUTH cells are EXACTLY equidistant from that chest — 96 vs 96 and 136 vs 136 — so the
## chest answers them. That is nearest-by-anchor working, not a defect, and the only honest way to
## say so is to measure both distances rather than allowlist the cells: a press lost to something
## the player stands AT LEAST AS CLOSE TO is yielded and printed, a press lost to something FARTHER
## is stolen and reds. Relocating the row was tried and rejected — (40,29) measures clean, but
## `tools/gen_w2_suburb.py` reserves a 3x3 clearing per authored cell and warns that changing the
## set reshuffles the seeded RNG, so moving one landmark regenerates the whole W2 map.
##
## W1's copy of this instrument asserts the unrefined form and passes: no W1 landmark has an
## equidistant neighbour. The two differ because the maps differ, not because the rule did.

const WORLD := preload("res://src/exploration/SuburbanOverworld.gd")


var _vp: SubViewport = null
var _step: float = 96.0

const BODY_RADIUS := 8.0


## Own World2D: the shared default lets leaked bodies from other tests overlap these probes.
func _world() -> Node2D:
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var w = WORLD.new()
	_vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step = float(int(w.MAP_SCALE) * int(w.TILE_SIZE))
	return w


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


## Broad census: every standable cell within two, every facing. Without it a prop whose whole ring
## is unstandable scores face-failures [] and reads as reachable.
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


## The contract, W1's wording: from each standable cell touching it, facing it must open IT —
## refined by the dispatch rule it is measuring. A press lost to something the player is standing
## AT LEAST AS CLOSE TO is nearest-by-anchor working: The Timetable's three south cells are exactly
## equidistant from `w2_bus_hipotion`, two cells below it, and the chest answering there is right.
## A press lost to something FARTHER away is the defect, and that is what this returns. The yielded
## cells come back separately so they are reported rather than silently forgiven.
func _face_split(prop: Node2D) -> Dictionary:
	var bad: Array = []
	var yielded: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var feet: Vector2 = prop.global_position + Vector2(dx * _step, dy * _step)
			if not _fits(feet):
				continue
			var facing := Vector2(-dx, 0) if absi(dx) >= absi(dy) else Vector2(0, -dy)
			var won: Node = _press_lands_on(feet, facing)
			if won == prop:
				continue
			if won == null:
				bad.append("(%d,%d) -> nothing" % [dx, dy])
				continue
			var mine: float = InteractGeometry.anchor(prop).distance_to(feet)
			var theirs: float = InteractGeometry.anchor(won as Node2D).distance_to(feet)
			if theirs <= mine + 0.5:
				yielded.append("(%d,%d) to %s at %.0fpx vs %.0f" % [dx, dy, _label(won), theirs, mine])
			else:
				bad.append("(%d,%d) -> %s, %.0fpx away against my %.0f" % [dx, dy, _label(won), theirs, mine])
	return {"bad": bad, "yielded": yielded}


func _readables(w: Node) -> Dictionary:
	var out: Dictionary = {}
	for c in w.get_children():
		if c is ReadableProp:
			out[str(c.name)] = c
	return out


func _landmark_positions(w: Node) -> Array:
	var out: Array = []
	for c in w.get_children():
		if c is Landmark:
			out.append((c as Landmark).position)
	return out


## Every interactable the SCENE owns — not the "interactables" group, which is global and carries
## other tests' leftovers into this one.
func _scene_interactables(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node2D and c.has_method("interact"):
			out.append(c)
		_scene_interactables(c, out)


## An OverworldNPC never sets its node name, so a thief reads as '@Area2D@276' unless we ask it who
## it is — and an unreadable red is a red nobody acts on.
func _label(n: Node) -> String:
	for key in ["npc_name", "display_name", "chest_id", "sign_text"]:
		if n.get(key) != null and str(n.get(key)) != "":
			return "%s (%s)" % [str(n.get(key)), n.name]
	return str(n.name)


func test_every_landmark_has_a_readable_on_its_own_cell() -> void:
	var w = await _world()
	var lore := W2Landmarks.new()
	var rows: Array = lore.table()
	assert_gt(rows.size(), 0, "CONTROL: the table is empty, so every [] below is free")

	var props := _readables(w)
	var marks := _landmark_positions(w)
	assert_eq(props.size(), rows.size(), "one readable per table row")
	assert_eq(marks.size(), rows.size(), "one drawn landmark per table row")

	var missing: Array = []
	var adrift: Array = []
	for row in rows:
		var key: String = "Lore_" + str(row["fn"])
		if not props.has(key):
			missing.append(key)
			continue
		var want: Vector2 = w._cell_center(row["cell"])
		if props[key].position.distance_to(want) > 1.0:
			adrift.append("%s at %s, table says %s" % [key, str(props[key].position), str(want)])
		if not marks.any(func(p): return p.distance_to(want) <= 1.0):
			adrift.append("%s has no landmark drawn on its cell %s" % [key, str(row["cell"])])
	assert_eq(missing, [], "a table row built no readable: %s" % ", ".join(missing))
	assert_eq(adrift, [], "a readable does not stand on its own landmark: %s" % ", ".join(adrift))


func test_every_provider_returns_pages() -> void:
	var lore := W2Landmarks.new()
	var rows: Array = lore.table()
	assert_gt(rows.size(), 0, "CONTROL: no rows to call")
	var broken: Array = []
	for row in rows:
		var fn: String = str(row["fn"])
		if not lore.has_method(fn):
			broken.append("%s names no method" % fn)
			continue
		var pages = Callable(lore, fn).call()
		if not (pages is Array) or (pages as Array).is_empty():
			broken.append("%s returned no pages" % fn)
			continue
		for e in pages as Array:
			if e is Dictionary:
				if str(e.get("body", "")) == "":
					broken.append("%s has a headed page with no body" % fn)
			elif not (e is String) or str(e) == "":
				broken.append("%s has a page that is neither text nor a {heading,body}" % fn)
	assert_eq(broken, [], "a landmark would open an empty panel: %s" % ", ".join(broken))


func test_the_press_at_a_landmark_reaches_its_own_readable() -> void:
	var w = await _world()
	var lore := W2Landmarks.new()
	var rows: Array = lore.table()
	var others: Array = []
	_scene_interactables(w, others)
	assert_gt(others.size(), rows.size(),
		"CONTROL: the sprawl holds only the new readables (%d), so 'nearest' is trivially true" % others.size())

	var stolen: Array = []
	for row in rows:
		var at: Vector2 = w._cell_center(row["cell"])
		var best: Node2D = null
		var best_d: float = INF
		for o in others:
			## Matches the dispatch: nearest anchor wins, ties to the earlier sibling.
			var d: float = InteractGeometry.anchor(o).distance_to(at)
			if d < best_d:
				best_d = d
				best = o
		var want: String = "Lore_" + str(row["fn"])
		if best == null or str(best.name) != want:
			stolen.append("%s: the press at %s goes to '%s' (%.0f px)" % [
				want, str(row["cell"]), "nothing" if best == null else _label(best), best_d])
	assert_eq(stolen, [], "a landmark's press is taken by something else: %s" % ", ".join(stolen))


func test_a_landmark_readable_actually_opens() -> void:
	var w = await _world()
	var lore := W2Landmarks.new()
	var rows: Array = lore.table()
	assert_gt(rows.size(), 0, "CONTROL: nothing to open")
	var props := _readables(w)
	var key: String = "Lore_" + str(rows[0]["fn"])
	assert_true(props.has(key), "SCOPE: %s must exist to be pressed" % key)
	if not props.has(key):
		return
	var prop = props[key]
	assert_false(prop.is_open(), "CONTROL: closed before the press")
	prop.interact(null)
	assert_true(prop.is_open(), "pressing %s opened nothing — the provider returned no pages" % key)
	prop._close_panel()
	assert_false(prop.is_open(), "the panel must close, and release the input lock with it")


## Derived floor: every symbol this file reaches on its two receivers, read out of this file's own
## source. Without it an arm that aborts on a renamed method scores Passing on the assert above it.
func test_the_symbols_this_file_reaches_exist() -> void:
	var src := FileAccess.get_file_as_string("res://test/unit/test_the_sprawl_answers_when_you_press_it.gd")
	assert_ne(src, "", "CONTROL: could not read this file, so the floor is derived from nothing")
	var w = await _world()
	var lore := W2Landmarks.new()
	var subjects: Dictionary = {"w": w, "lore": lore, "prop": ReadableProp.new()}
	var re := RegEx.create_from_string("\\b(w|lore|prop)\\.([a-z_][a-z0-9_]*)\\(")
	var reached: Dictionary = {}
	for m in re.search_all(src):
		reached[m.get_string(1) + "." + m.get_string(2)] = true
	assert_gt(reached.size(), 4, "CONTROL: the derivation found %d symbols — the regex is broken" % reached.size())
	var gone: Array = []
	for k in reached.keys():
		var parts: PackedStringArray = str(k).split(".")
		if not subjects[parts[0]].has_method(parts[1]):
			gone.append(str(k))
	gone.sort()
	(subjects["prop"] as Node).free()
	assert_eq(gone, [], "this file calls a symbol that no longer exists: %s" % ", ".join(gone))


## A label is a promise. W1's measured property is "face it and press", NOT "no press moves" —
## four new 128px zones (Y-stretched to 213) on a map authored around seven chests DO move presses,
## and asserting zero movement would force correct placements to relocate.
func test_every_landmark_readable_can_actually_be_pressed() -> void:
	var w = await _world()
	assert_true(Mode7Overlay.is_active,
		"PRECONDITION: W2 must be running Mode 7, or this measures the flat branch and proves nothing")
	var props: Array = _readables(w).values()
	assert_gt(props.size(), 0, "CONTROL: no lore props found, so [] below is free")
	var unreachable: Array = []
	for p in props:
		var n := _presses_for(p)
		var split := _face_split(p)
		gut.p("  %-24s %3d presses   stolen %s   yielded %s" % [
			str(p.name), n, str(split["bad"]), str(split["yielded"])])
		if n <= 0:
			unreachable.append("%s (%s) — no standable cell within two opens it from any facing" % [str(p.name), str(p.display_name)])
		elif not (split["bad"] as Array).is_empty():
			unreachable.append("%s (%s) — %s; move that row's cell in W2Landmarks.table()" % [
				str(p.name), str(p.display_name), ", ".join(split["bad"])])
	unreachable.sort()
	assert_eq(unreachable, [],
		"a landmark now carries a label promising a press it cannot answer — worse than leaving it " +
		"mute, because the label IS the promise: %s" % ", ".join(unreachable))


## The load-bearing arm. `w2_bus_hipotion` sits two cells under The Timetable and the new zone
## reaches 213 px vertically, so the chest is inside it. Baseline is measured in the SAME run with
## the lore props freed, so W2's pre-existing face-failures stay this file's business to report and
## nobody else's to fix.
func test_no_landmark_readable_takes_a_neighbours_press() -> void:
	var w = await _world()
	var lore_names: Dictionary = _readables(w)
	var others: Array = []
	_scene_interactables(w, others)
	var neighbours: Array = []
	for n in others:
		if not lore_names.has(str(n.name)):
			neighbours.append(n)
	assert_gt(neighbours.size(), 4,
		"CONTROL: only %d non-lore interactables collected — with nothing to rob, [] is free" % neighbours.size())

	var with_lore: Dictionary = {}
	for n in neighbours:
		with_lore[n] = (_face_split(n)["bad"] as Array) + (_face_split(n)["yielded"] as Array)
	for key in lore_names.keys():
		(lore_names[key] as Node).free()
	await get_tree().physics_frame

	var robbed: Array = []
	for n in neighbours:
		if not is_instance_valid(n):
			continue
		var without: Array = (_face_split(n)["bad"] as Array) + (_face_split(n)["yielded"] as Array)
		for cell in with_lore[n]:
			if not without.has(cell):
				robbed.append("%s loses the press at %s to a landmark readable" % [_label(n), str(cell)])
	robbed.sort()
	assert_eq(robbed, [],
		"a new landmark readable took a press its neighbour already answered — the lore props may " +
		"MOVE presses, but not take a face-it-and-press: %s" % ", ".join(robbed))
