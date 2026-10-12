extends GutTest

## W3 drew four pieces of machinery — two gear piles, two steam pipes — and answered with none of
## them. Same anti-feature W1 closed and W2 closed after it: a player who presses the first two and
## gets silence has been taught that overworld scenery is scenery, and walks past every readable
## placed afterwards.
##
## W3Landmarks.table() is the single source for cell, art type and pages, so moving a landmark moves
## the readable standing on it. The arms check the CONSUMER rather than the table: the scene it
## built, the press that reaches it, and the panel that opens.
##
## ⚠️ The press arms are not "a readable exists". Dispatch is nearest-by-anchor, and `w3_park_ether`
## sits two cells above The Standing Gauge — the same collinear-tie shape W2's Timetable has with
## `w2_bus_hipotion`. The census helper reports a press lost to an equidistant neighbour as YIELDED
## with both distances printed, and reds only on a press lost to something FARTHER.
##
## 📌 The four cells are all in `tools/gen_w3_steampunk.py`'s ENTITY_SPOTS, which reserves a 3x3
## clearing per cell and warns that changing the set reshuffles the seeded RNG. So relocating a row
## regenerates the whole W3 map, and the cells are fixed by construction rather than by preference.

const WORLD := preload("res://src/exploration/SteampunkOverworld.gd")
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
	var lore := W3Landmarks.new()
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
	var lore := W3Landmarks.new()
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


## A provider must survive GameState being absent — the null branch is the one no playthrough takes
## and every isolated test does, and W3's collar shipped `return []` on that path for one draft.
func test_no_provider_goes_empty_without_game_state() -> void:
	var lore := W3Landmarks.new()
	var rows: Array = lore.table()
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null:
		gs.name = "GameStateHidden"
	var empty: Array = []
	for row in rows:
		var pages = Callable(lore, str(row["fn"])).call()
		if not (pages is Array) or (pages as Array).is_empty():
			empty.append(str(row["fn"]))
	if gs != null:
		gs.name = "GameState"
	assert_eq(empty, [],
		"with no GameState these providers return nothing, so the prop opens a blank panel: %s" % ", ".join(empty))


func test_the_press_at_a_landmark_reaches_its_own_readable() -> void:
	var w = await _world()
	var lore := W3Landmarks.new()
	var rows: Array = lore.table()
	var others: Array = []
	_census.scene_interactables(w, others)
	assert_gt(others.size(), rows.size(),
		"CONTROL: the Dominion holds only the new readables (%d), so 'nearest' is trivially true" % others.size())

	var stolen: Array = []
	for row in rows:
		var at: Vector2 = w._cell_center(row["cell"])
		var best: Node2D = null
		var best_d: float = INF
		for o in others:
			var d: float = InteractGeometry.anchor(o).distance_to(at)
			if d < best_d:
				best_d = d
				best = o
		var want: String = "Lore_" + str(row["fn"])
		if best == null or str(best.name) != want:
			stolen.append("%s: the press at %s goes to '%s' (%.0f px)" % [
				want, str(row["cell"]), "nothing" if best == null else _census.label(best), best_d])
	assert_eq(stolen, [], "a landmark's press is taken by something else: %s" % ", ".join(stolen))


## A label is a promise. See the helper's header for why `yielded` is reported and not asserted.
func test_every_landmark_readable_can_actually_be_pressed() -> void:
	var w = await _world()
	assert_true(Mode7Overlay.is_active,
		"PRECONDITION: W3 must be running Mode 7, or this measures the flat branch and proves nothing")
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
			unreachable.append("%s (%s) — %s; move that row's cell in W3Landmarks.table()" % [
				str(p.name), str(p.display_name), ", ".join(split["bad"])])
	unreachable.sort()
	assert_eq(unreachable, [],
		"a landmark now carries a label promising a press it cannot answer — worse than leaving it " +
		"mute, because the label IS the promise: %s" % ", ".join(unreachable))


## The load-bearing arm. Baseline is measured in the SAME run with the lore props freed, so W3's
## pre-existing face-failures stay this file's business to report and nobody else's to fix.
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
		var s: Dictionary = _census.face_split(n)
		with_lore[n] = (s["bad"] as Array) + (s["yielded"] as Array)
	for key in lore_names.keys():
		(lore_names[key] as Node).free()
	await get_tree().physics_frame

	var robbed: Array = []
	for n in neighbours:
		if not is_instance_valid(n):
			continue
		var s2: Dictionary = _census.face_split(n)
		var without: Array = (s2["bad"] as Array) + (s2["yielded"] as Array)
		for cell in with_lore[n]:
			if not without.has(cell):
				robbed.append("%s loses the press at %s to a landmark readable" % [_census.label(n), str(cell)])
	robbed.sort()
	assert_eq(robbed, [],
		"a new landmark readable took a press its neighbour already answered — the lore props may " +
		"MOVE presses, but not take a face-it-and-press: %s" % ", ".join(robbed))


func test_a_landmark_readable_actually_opens() -> void:
	var w = await _world()
	var lore := W3Landmarks.new()
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


## Derived floor: every symbol this file reaches on its receivers, read out of this file's own
## source. Without it an arm that aborts on a renamed method scores Passing on the assert above it.
func test_the_symbols_this_file_reaches_exist() -> void:
	var src := FileAccess.get_file_as_string("res://test/unit/test_the_dominion_answers_when_you_press_it.gd")
	assert_ne(src, "", "CONTROL: could not read this file, so the floor is derived from nothing")
	var w = await _world()
	var lore := W3Landmarks.new()
	var prop := ReadableProp.new()
	var subjects: Dictionary = {"w": w, "lore": lore, "prop": prop, "_census": _census}
	var re := RegEx.create_from_string("\\b(w|lore|prop|_census)\\.([a-z_][a-z0-9_]*)\\(")
	var reached: Dictionary = {}
	for m in re.search_all(src):
		reached[m.get_string(1) + "." + m.get_string(2)] = true
	assert_gt(reached.size(), 5, "CONTROL: the derivation found %d symbols — the regex is broken" % reached.size())
	var gone: Array = []
	for k in reached.keys():
		var parts: PackedStringArray = str(k).split(".")
		if not subjects[parts[0]].has_method(parts[1]):
			gone.append(str(k))
	gone.sort()
	prop.free()
	assert_eq(gone, [], "this file calls a symbol that no longer exists: %s" % ", ".join(gone))
