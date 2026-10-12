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
## ⚠️ The press arm is not "a readable exists". The dispatch is nearest-by-anchor
## (OverworldController._pick_nearest_interactable), and `w2_bus_hipotion` sits two cells under The
## Timetable — so a readable can be placed, labelled, and still lose every press to a chest.

const WORLD := preload("res://src/exploration/SuburbanOverworld.gd")


func _world() -> Node2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var w = WORLD.new()
	vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
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


## Every interactable the SCENE owns — not the "interactables" group, which is global and carries
## other tests' leftovers into this one.
func _scene_interactables(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node2D and c.has_method("interact"):
			out.append(c)
		_scene_interactables(c, out)


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
				want, str(row["cell"]), "nothing" if best == null else str(best.name), best_d])
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
