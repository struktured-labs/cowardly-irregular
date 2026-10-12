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
const Census := preload("res://test/unit/helpers/press_census.gd")


var _census: RefCounted = null


## Own World2D: the shared default lets leaked bodies from other tests overlap these probes.
func _world() -> Node2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var w = WORLD.new()
	vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_census = Census.new()
	_census.setup(vp, float(int(w.MAP_SCALE) * int(w.TILE_SIZE)))
	return w


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
	_census.scene_interactables(w, others)
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
				want, str(row["cell"]), "nothing" if best == null else _census.label(best), best_d])
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
	var prop := ReadableProp.new()
	var subjects: Dictionary = {"w": w, "lore": lore, "prop": prop, "_census": _census}
	var re := RegEx.create_from_string("\\b(w|lore|prop|_census)\\.([a-z_][a-z0-9_]*)\\(")
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
	prop.free()
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
		var n: int = _census.presses_for(p)
		var split: Dictionary = _census.face_split(p)
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
	_census.scene_interactables(w, others)
	var neighbours: Array = []
	for n in others:
		if not lore_names.has(str(n.name)):
			neighbours.append(n)
	assert_gt(neighbours.size(), 4,
		"CONTROL: only %d non-lore interactables collected — with nothing to rob, [] is free" % neighbours.size())

	var with_lore: Dictionary = {}
	for n in neighbours:
		var sp: Dictionary = _census.face_split(n)
		with_lore[n] = (sp["bad"] as Array) + (sp["yielded"] as Array)
	for key in lore_names.keys():
		(lore_names[key] as Node).free()
	await get_tree().physics_frame

	var robbed: Array = []
	for n in neighbours:
		if not is_instance_valid(n):
			continue
		var sp2: Dictionary = _census.face_split(n)
		var without: Array = (sp2["bad"] as Array) + (sp2["yielded"] as Array)
		for cell in with_lore[n]:
			if not without.has(cell):
				robbed.append("%s loses the press at %s to a landmark readable" % [_census.label(n), str(cell)])
	robbed.sort()
	assert_eq(robbed, [],
		"a new landmark readable took a press its neighbour already answered — the lore props may " +
		"MOVE presses, but not take a face-it-and-press: %s" % ", ".join(robbed))
