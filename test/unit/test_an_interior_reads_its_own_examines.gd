extends GutTest

const Sweep := preload("res://src/maps/interiors/InteriorPlacementSweep.gd")
const BASE := "res://src/maps/interiors/BaseInterior.gd"
const DIR := "res://src/maps/interiors/"
const PACK := "res://data/examine_texts.json"

## `data/examine_texts.json` is read by villages, Castle Harmonia, AssemblyCore and the W6
## overworld. BaseInterior had no loader, so a row keyed to a room could be authored and reach
## nobody — the same silent gap that left the castle's eleven and the villages' thirteen unread for
## six months. This adds the path; @cowir-story authors the rows on top of it.
##
## 🔑 THE ANCHOR IS `spawn_points["entrance"]`, AND THE REASON I FIRST GAVE FOR IT WAS FALSE.
## I argued it was safe because `BaseInterior._init_spawn_points` DERIVES the door as
## `(width / 2, height - 2)`. @cowir-story measured that every one of the 27 rooms overrides that
## with a hardcoded cell, so the derivation is reached by none of them:
##
##     HarmoniaChapel     18x13   derived (9, 11)   authored (8, 11)
##     HarmoniaLibrary    20x14   derived (10, 12)  authored (9, 12)
##     ScripturaBookshop  16x12   derived (8, 10)   authored (7, 10)
##
## Every room differs from the derivation, consistently one cell short in x — these are placed
## doors, not computed ones. The decision stands (an offset from the door is what an author means)
## but the GUARANTEE is weaker than I claimed: the entrance is an authored absolute, so a
## re-authored grid can leave it behind. `test_every_interiors_own_door_is_walkable` below is the
## repair, and it is the arm that makes the anchor worth having.
##
## ⚠️ AND THE OFFSET TABLE IS REACHED THROUGH `_examine_offsets()`, NOT READ AS A CONST. BaseVillage
## gates on `_EXAMINE_OFFSETS.has(id)` while inviting subclasses to override `_examine_offset_for`;
## a const resolves in the base scope, so that override cannot be reached for a row the base table
## lacks. Harmless there today — every shipped village row IS in the base table — but this class is
## built so a room can name its own offset and actually be consulted, which `test_a_room_can_name_
## its_own_offset` pins.


## A minimal real BaseInterior: walls on the border, floor inside, and a door the subclass AUTHORS
## the way all 27 shipped rooms do rather than inheriting.
class Room extends BaseInterior:
	var offsets: Dictionary = {}
	var area_id: String = "harmonia_chapel"

	func _get_area_id() -> String:
		return area_id

	func _get_map_width() -> int:
		return 10

	func _get_map_height() -> int:
		return 8

	func _get_layout() -> Array:
		var rows: Array = []
		for y in range(8):
			var row := ""
			for x in range(10):
				row += "W" if (x == 0 or y == 0 or x == 9 or y == 7) else "."
			rows.append(row)
		return rows

	func _init_spawn_points() -> void:
		spawn_points["entrance"] = Vector2(5, 6)

	func _examine_offsets() -> Dictionary:
		return offsets

	func _get_music_track() -> String:
		return ""

	func _get_ambient_key() -> String:
		return ""


func _room() -> Node2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var r := Room.new()
	vp.add_child(r)
	await get_tree().physics_frame
	return r


func _readables(r: Node2D) -> Array:
	var out: Array = []
	if r.npcs == null:
		return out
	for c in r.npcs.get_children():
		if c is ReadableProp:
			out.append(c)
	return out


## ⛔ FLOOR. Every BaseInterior member this file reaches, derived from this file's own source rather
## than hand-listed, so a rename reds here NAMING THE SYMBOL instead of making an arm go vacuous.
## Reached through the `Room` subclass, so they resolve at runtime and an abort would be silent in
## any arm that has already asserted once.
func test_the_symbols_this_file_drives_all_exist() -> void:
	var r = await _room()
	var src := FileAccess.get_file_as_string("res://test/unit/test_an_interior_reads_its_own_examines.gd")
	assert_ne(src, "", "CONTROL: this file must be readable to derive its own reaches")
	var code: String = str(GdSource.split(src)["code"])
	## \u26d4 EXCLUDE THIS FUNCTION'S OWN BODY. Deriving over the whole file matched `r.has_method`
	## from the loop below, so the floor reported a reach it had invented itself — Object.has_method
	## exists, so the arm passed and the count read as 9 where the file drives 8. A suppression list
	## would hide it; removing the self-reference is the structural cure.
	var own := code.find("func test_the_symbols_this_file_drives_all_exist")
	assert_gt(own, -1, "CONTROL: this function must be findable to exclude itself")
	var own_end := code.find("\nfunc ", own + 10)
	code = code.substr(0, own) + ("" if own_end < 0 else code.substr(own_end))
	assert_false(code.contains("func test_the_symbols_this_file_drives_all_exist"),
		"CONTROL: the self-slice must actually remove this function")
	var rx := RegEx.create_from_string("\\br\\.([a-z_]+)")
	var want: Dictionary = {}
	for m in rx.search_all(code):
		want[m.get_string(1)] = true
	assert_gt(want.size(), 3, "CONTROL: only %d reaches derived; the pattern is not matching" % want.size())
	var missing: Array = []
	for name in want.keys():
		if not (r.has_method(str(name)) or str(name) in r):
			missing.append(str(name))
	missing.sort()
	assert_eq(missing, [], "BaseInterior no longer has: %s" % ", ".join(missing))
	gut.p("  floor pinned %d reaches: %s" % [want.size(), ", ".join(want.keys())])


func test_a_row_with_an_offset_becomes_a_readable_at_that_cell() -> void:
	var r = await _room()
	r.offsets = {"probe_plaque": Vector2i(-2, -3)}
	var placed: int = r._place_examines({
		"probe_plaque": {"world": "medieval", "scene": "harmonia_chapel",
			"prop": "plaque", "name": "A Plaque", "text": "Authored prose."},
	})
	assert_eq(placed, 1, "the row must be placed")
	var props := _readables(r)
	assert_eq(props.size(), 1, "exactly one readable, found %d" % props.size())
	if props.is_empty():
		return
	var prop = props[0]
	assert_eq(str(prop.name), "Examine_probe_plaque", "the node is named for its row")
	## Cell-CENTRED: entrance (5,6) + (-2,-3) = (3,3) -> (3*32+16, 3*32+16). A 28px readable on a
	## cell CORNER sits 24px off every axis-aligned probe, so it draws and cannot be pressed.
	assert_eq(prop.position, Vector2(3 * 32 + 16, 3 * 32 + 16),
		"the readable sits centred on entrance+offset, not on the cell corner")
	assert_eq(str(prop.display_name), "A Plaque", "the row's name reaches the prop")
	var pages = prop._provider.call()
	assert_eq(pages, ["Authored prose."], "the row's TEXT is what the player reads")


func test_a_room_can_name_its_own_offset() -> void:
	var r = await _room()
	r.offsets = {"room_local": Vector2i(1, -1)}
	assert_eq(r._examine_offset_for("room_local"), Vector2i(1, -1),
		"a subclass offset must be CONSULTED — BaseVillage's const gate cannot reach one")
	assert_eq(r._place_examines({"room_local": {"name": "X", "text": "t"}}), 1,
		"and it must gate placement, not just answer a lookup")


## ⛔ THE REFUSALS cowir-main named. Each is a row that would otherwise place a prop with nothing
## behind it — a mute interactable, which is worse than an absent one because it answers a press.
func test_a_row_with_no_offset_and_a_row_with_no_text_are_both_refused() -> void:
	var r = await _room()
	## \u26d4 `no_text` CARRIES AN OFFSET ON PURPOSE. Without one it was refused by the OFFSET gate,
	## so deleting the empty-text gate left this arm green — one mutation, two gates, and the
	## surviving one answered for both. Each row here must be refusable for exactly one reason.
	r.offsets = {"has_offset": Vector2i(0, -2), "no_text": Vector2i(2, -2)}
	var placed: int = r._place_examines({
		"has_offset": {"name": "Good", "text": "real"},
		"no_offset": {"name": "Bad", "text": "orphaned prose"},
		"no_text": {"name": "Mute", "text": ""},
	})
	assert_eq(placed, 1, "only the well-formed row places; got %d" % placed)
	var names: Array = []
	for p in _readables(r):
		names.append(str(p.name))
	names.sort()
	assert_eq(names, ["Examine_has_offset"], "the refused rows left no prop: %s" % ", ".join(names))


## ⛔ `BaseInterior._get_area_id()` returns "interior". A room that forgets to override it must not
## match rows, or it serves another scene's prose — and nothing on screen would say so.
func test_the_default_area_id_claims_nothing() -> void:
	var r = await _room()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	assert_true(parsed is Dictionary, "CONTROL: the pack must parse")
	var rows: Dictionary = (parsed as Dictionary).get("examines", {})
	assert_gt(rows.size(), 10, "CONTROL: the pack holds %d rows, so an empty result means filtering" % rows.size())
	## \u26d4 DRIVEN THROUGH THE SEAM, NOT THE FILE READ. Asserting `_load_examine_pack() == {}` here
	## was GREEN with the refusal DELETED: no shipped row carries `scene: "interior"`, so the empty
	## result came from the ordinary filter and proved nothing. A synthetic row with that scene is
	## the only input that separates the two, and it cannot exist in the pack by design.
	r.area_id = "interior"
	assert_eq(r._rows_for_this_scene({"planted": {"scene": "interior", "name": "N", "text": "t"}}), {},
		"a row keyed to the DEFAULT id must be refused — a room that forgot to override _get_area_id would otherwise serve it")
	assert_eq(r._load_examine_pack(), {}, "and the file path refuses it too")
	r.area_id = "harmonia_chapel"
	assert_eq(r._rows_for_this_scene({"planted": {"scene": "harmonia_chapel", "name": "N", "text": "t"}}).size(), 1,
		"CONTROL: the same seam ACCEPTS a row for a real id, so the refusal above is about the id")
	assert_true(r._load_examine_pack() is Dictionary, "a real id still reads the pack")


## \u2705 THE DISK HALF, END TO END, WITH NO PLACEHOLDER ROW SHIPPED. cowir-main's brief allowed one
## placeholder in `examine_texts.json` to prove the path and then its removal; a synthetic pack plus
## this arm is strictly better, because it proves the real file read and the real filter against
## data that is already there and stays proven once @cowir-story's interior rows land. The probe
## room borrows an EXISTING scene id, so `_load_examine_pack` is exercised on shipped content.
func test_the_pack_is_actually_read_from_disk_and_filtered_by_scene() -> void:
	var r = await _room()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	assert_true(parsed is Dictionary, "CONTROL: the pack must parse")
	var rows: Dictionary = (parsed as Dictionary).get("examines", {})
	var by_scene: Dictionary = {}
	for k in rows.keys():
		var e = rows[k]
		if e is Dictionary:
			var sc: String = str((e as Dictionary).get("scene", ""))
			by_scene[sc] = int(by_scene.get(sc, 0)) + 1
	var busiest := ""
	for sc in by_scene.keys():
		if busiest == "" or int(by_scene[sc]) > int(by_scene[busiest]):
			busiest = str(sc)
	assert_ne(busiest, "", "CONTROL: the pack must name at least one scene")
	assert_gt(int(by_scene.get(busiest, 0)), 1,
		"CONTROL: the busiest scene has %d rows; one row cannot show FILTERING" % int(by_scene.get(busiest, 0)))
	r.area_id = busiest
	var mine: Dictionary = r._load_examine_pack()
	assert_eq(mine.size(), int(by_scene[busiest]),
		"reading '%s' must return its %d rows, got %d" % [busiest, int(by_scene[busiest]), mine.size()])
	for k in mine.keys():
		assert_eq(str((mine[k] as Dictionary).get("scene", "")), busiest,
			"row '%s' belongs to another scene — the filter leaked" % str(k))
	assert_lt(mine.size(), rows.size(),
		"CONTROL: it returned the WHOLE pack (%d of %d), so nothing was filtered" % [mine.size(), rows.size()])
	gut.p("  read %d of %d rows from disk for scene '%s'" % [mine.size(), rows.size(), busiest])


## 🔑 THE ORDER IS THE CONTRACT. Placing before the sweep is what gives an examine the same
## wall-and-furniture protection an NPC gets, instead of a second resolver that would drift from it.
func test_examines_are_placed_before_the_placement_sweep() -> void:
	var code: String = str(GdSource.split(FileAccess.get_file_as_string(BASE))["code"])
	var at := code.find("func _ready")
	assert_gt(at, -1, "CONTROL: BaseInterior._ready must exist")
	var nxt := code.find("\nfunc ", at + 10)
	var body: String = code.substr(at, (nxt if nxt > at else code.length()) - at)
	var place := body.find("_place_authored_examines()")
	var sweep := body.find("_validate_placements()")
	assert_gt(place, -1, "_ready must call _place_authored_examines — without it the pack is unread")
	assert_gt(sweep, -1, "CONTROL: _ready must still call _validate_placements")
	assert_true(place < sweep,
		"examines must be placed BEFORE the sweep, or a readable authored onto a table stays on it")


## And the consequence, measured rather than inferred from the order above: a readable whose offset
## lands on a wall is moved onto floor by the shared sweep.
func test_a_readable_on_a_wall_is_relocated_by_the_shared_sweep() -> void:
	var r = await _room()
	## entrance (5,6) + (-5,-6) = (0,0), the top-left corner, which this room's layout walls.
	r.offsets = {"on_a_wall": Vector2i(-5, -6)}
	assert_eq(r._place_examines({"on_a_wall": {"name": "W", "text": "t"}}), 1, "CONTROL: it was placed")
	var props := _readables(r)
	assert_eq(props.size(), 1, "CONTROL: one readable to follow")
	if props.is_empty():
		return
	var before: Vector2 = props[0].position
	assert_false(Sweep._is_cell_walkable(Vector2i(0, 0), r._get_layout()),
		"CONTROL: the chosen cell really is a wall, or this arm proves nothing")
	r._validate_placements()
	var after: Vector2 = props[0].position
	assert_ne(after, before, "the sweep must move a readable off a wall cell")
	assert_true(Sweep._is_cell_walkable(Vector2i(after / 32.0), r._get_layout()),
		"and it must land on floor, not merely somewhere else: %s" % str(after))


## ⛔ THE INVARIANT THAT MAKES AN OFFSET ANCHOR WORTH HAVING, and it was unguarded. Every room
## AUTHORS its own entrance as an absolute cell (@cowir-story's measurement above), so a re-authored
## grid can leave the door inside a wall — and then every offset in that room is measured from a
## cell the player can never stand on. The village-side doorstep is already pinned by
## test_interior_return_doorstep_regression; the room-side door was not pinned by anything.
func test_every_interiors_own_door_is_walkable() -> void:
	var d := DirAccess.open(DIR)
	assert_not_null(d, "CONTROL: the interiors directory must be readable")
	if d == null:
		return
	var checked := 0
	var bad: Array = []
	for f in d.get_files():
		if not f.ends_with(".gd") or f in ["BaseInterior.gd", "InteriorPlacementSweep.gd"]:
			continue
		var scr = load(DIR + f)
		if scr == null or not (scr is GDScript) or not scr.can_instantiate():
			continue
		var room = scr.new()
		if room == null or not room.has_method("_init_spawn_points") or not room.has_method("_get_layout"):
			if room != null:
				room.free()
			continue
		room._init_spawn_points()
		var layout: Array = room._get_layout()
		var entrance: Vector2 = room.spawn_points.get("entrance", Vector2.INF)
		if layout.is_empty() or entrance == Vector2.INF:
			room.free()
			continue
		checked += 1
		var cell := Vector2i(entrance)
		if not Sweep._is_cell_walkable(cell, layout):
			bad.append("%s: its authored entrance %s is not walkable in its own layout" % [f, str(cell)])
		room.free()
	assert_gt(checked, 20,
		"CONTROL: only %d rooms answered both hooks; a short corpus would clear nothing" % checked)
	bad.sort()
	assert_eq(bad, [], "a room's door is inside its own geometry: %s" % ", ".join(bad))
	gut.p("  %d interior doors walkable in their own layouts" % checked)
