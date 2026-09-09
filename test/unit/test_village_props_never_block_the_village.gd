extends GutTest

## A prop joins the walkability grid, so decorating a village can WALL IT OFF.
##
## VillageProp._add_prop writes every footprint cell into `_prop_blocked`, which `_is_cell_walkable`
## reads. A barrel is therefore not decoration -- it is level geometry. Drop one in a doorway or a
## one-tile corridor and the shop, the quest NPC or the exit becomes unreachable, with no error and
## nothing in the suite to notice: the scene builds, the sprite draws, and the player simply cannot
## get there. Written 2026-09-09 alongside the prop pass that took six villages from zero props,
## because hand-placed decoration is exactly where this lands.
##
## WHAT IS ASSERTED, and why it is the outcome rather than a property: not "props avoid doors"
## (a prop can miss every door and still seal a corridor) but "from the entry spawn, every door,
## shop, NPC and save point is still reachable". Reachability is the thing the player experiences.

const VILLAGES := {
	"harmonia": "res://src/maps/villages/HarmoniaVillage.gd",
	"eldertree": "res://src/maps/villages/EldertreeVillage.gd",
	"frosthold": "res://src/maps/villages/FrostholdVillage.gd",
	"grimhollow": "res://src/maps/villages/GrimhollowVillage.gd",
	"ironhaven": "res://src/maps/villages/IronhavenVillage.gd",
	"mapleheights": "res://src/maps/villages/MapleHeightsVillage.gd",
	"sandrift": "res://src/maps/villages/SandriftVillage.gd",
	"brasston": "res://src/maps/villages/BrasstonVillage.gd",
	"nodeprime": "res://src/maps/villages/NodePrimeVillage.gd",
	"rivetrow": "res://src/maps/villages/RivetRowVillage.gd",
	"vertex": "res://src/maps/villages/VertexVillage.gd",
}
const SPAN := 44


func _build(path: String):
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var v = load(path).new()
	vp.add_child(v)
	await get_tree().physics_frame
	return v


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x) / 32, int(p.y) / 32)


## Flood the walkable grid from the village's own entry spawn, props already in place.
func _reachable_from_spawn(v) -> Dictionary:
	var start := _cell(v.spawn_points.get("default", Vector2(64, 64)))
	if not v._is_cell_walkable(start):
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if v._is_cell_walkable(start + Vector2i(dx, dy)):
					start = start + Vector2i(dx, dy)
					break
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var c = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x > SPAN or n.y > SPAN or seen.has(n):
				continue
			if v._is_cell_walkable(n) and v._can_step(c, n):
				seen[n] = true
				stack.append(n)
	return seen


## Everything the player must be able to walk up to, measured by its INTERACTION EXTENT rather
## than its origin. A VillageShop's Area2D sits at the BUILDING'S CENTRE, inside its own walls --
## legitimately unwalkable. The first version of this test called five such buildings "sealed off"
## across three villages, which is a probe reporting its own model back at itself.
func _destinations(v) -> Array:
	var out: Array = []
	for holder in ["buildings", "npcs", "transitions"]:
		var h = v.get(holder)
		if h == null:
			continue
		for n in h.get_children():
			if n is Node2D:
				out.append({"name": str(n.name), "box": _cell_box(n)})
	if v.get("save_point") != null and v.save_point is Node2D:
		out.append({"name": "SavePoint", "box": _cell_box(v.save_point)})
	return out


## Cell-space box covering a node's own collision shapes, grown one cell so a player standing
## BESIDE the thing counts as having reached it. Shapeless nodes fall back to their origin cell.
func _cell_box(n: Node2D) -> Rect2i:
	var box := Rect2i(_cell(n.position), Vector2i.ZERO)
	var found := false
	for c in n.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var half: Vector2 = (c.shape as RectangleShape2D).size / 2.0
			var centre: Vector2 = n.position + c.position
			var lo := _cell(centre - half)
			var hi := _cell(centre + half)
			var r := Rect2i(lo, hi - lo)
			box = r if not found else box.merge(r)
			found = true
	return box.grow(1)


func test_no_prop_makes_anything_unreachable() -> void:
	var stranded: Array = []
	var villages_built := 0
	var props_seen := 0
	var destinations_seen := 0

	for label in VILLAGES:
		var v = await _build(VILLAGES[label])
		villages_built += 1
		props_seen += (v.props.get_child_count() if v.get("props") != null else 0)
		var reach := _reachable_from_spawn(v)
		for d in _destinations(v):
			destinations_seen += 1
			var box: Rect2i = d["box"]
			var ok := false
			for y in range(box.position.y, box.end.y + 1):
				for x in range(box.position.x, box.end.x + 1):
					if reach.has(Vector2i(x, y)):
						ok = true
						break
				if ok:
					break
			if not ok:
				stranded.append("%s/%s around %s" % [label, d["name"], str(box)])

	assert_eq(villages_built, VILLAGES.size(), "built %d of %d villages" % [villages_built, VILLAGES.size()])
	assert_gt(props_seen, 15, "CONTROL: only %d props across every village -- with no props placed this test cannot fail and certifies nothing" % props_seen)
	assert_gt(destinations_seen, 60, "CONTROL: only %d destinations collected -- the probe is not seeing them and the zero below is free" % destinations_seen)
	assert_eq(stranded, [],
		"a prop has sealed something off -- the scene builds and the sprite draws, the player just cannot get there: %s" % str(stranded))


## CONTROL: the flood must be capable of reporting a destination as unreachable. A village walled
## off at the spawn strands everything; if this comes back empty the sweep above is decoration.
func test_the_flood_can_report_something_unreachable() -> void:
	var v = await _build(VILLAGES["eldertree"])
	var reach := _reachable_from_spawn(v)
	assert_gt(reach.size(), 50, "CONTROL: the flood reached only %d cells in a village of hundreds" % reach.size())
	var far := Vector2i(999, 999)
	assert_false(reach.has(far), "CONTROL: a cell outside the map must read as unreachable")


## A prop's base cell is NOT position/TILE. VillageProp.create sets
## position = ((x + 0.5) * TILE, (y + 1) * TILE) so the art can grow upward from the base row, and
## dividing straight back reports y+1 -- which is how a first pass at this "found" two props buried
## in walls that are standing on open ground.
func _prop_base(p: Node2D) -> Vector2i:
	return Vector2i(int(floor(p.position.x / 32.0)), int(p.position.y / 32.0) - 1)


## A prop inside a building is drawn behind it and blocks a cell nobody could stand on anyway --
## harmless to walk, but it means the coordinate was a typo and the decoration is not where it reads.
func test_no_prop_stands_inside_a_wall() -> void:
	var embedded: Array = []
	var checked := 0
	for label in VILLAGES:
		var v = await _build(VILLAGES[label])
		if v.get("props") == null:
			continue
		for p in v.props.get_children():
			checked += 1
			for c in p.footprint_cells(_prop_base(p)):
				if not v._tile_is_open(c):
					embedded.append("%s: %s at %s is inside solid ground" % [label, str(p.name), str(c)])
	assert_gt(checked, 60, "CONTROL: only %d props inspected across every village" % checked)
	assert_eq(embedded, [], "props standing in walls -- drawn behind the building, so the coordinate is a typo: %s" % str(embedded))
