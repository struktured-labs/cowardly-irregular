extends GutTest

## A Masterite the player cannot reach is a boss that does not exist, and nothing in the engine says so.
##
## `BaseVillage` RELOCATES any body it finds on an impassable cell — half a tile diagonally, behind a
## `push_warning` nobody reads — so a boss authored onto a wall still appears, a tile off, and a boss
## authored into a prop footprint or onto another encounter's cell can be eclipsed by nearest-wins
## interaction. Both read as "placed" in the village source.
##
## W1's four could coast on an auto-set when a player missed them. W2-W6's cannot: these fights are
## the ONLY writers of the flags their worlds' fragment reveals wait on, so an unreachable one is a
## reveal that never fires. The repair is to judge the CELL against the village's own walkability
## authority (`_is_cell_walkable`), on the built scene, rather than to re-read the coordinates.
##
## Derived end to end: the corpus is every map script MapScripts nominates, and the expected count
## comes from the village SOURCES, so a boss added to a village and a boss dropped from the walk are
## both visible. Nothing here is a hand-kept list of villages or of bosses.

## 📋 ARMS PROVEN — which asserts here have a DEMONSTRATED red, and which do not.
##   moved == []         ✅ Warden onto the inn's wall block (6,3) -> "authored at (192,96), stands at
##                          (176,80)"; and onto the perimeter echo wall (0,8) -> "(0,256) -> (48,240)"
##   shared == []        ✅ Arbiter stacked onto the Tempo's cell  -> names both and "(11, 10)"
##   set equality        ✅ one `npcs.add_child` dropped while the source still declares it
##   blocked == []       ⛔ NEVER FIRED, AND ALMOST UNREACHABLE — say so rather than imply it is a
##                          proven arm. `_validate_placements` runs on every Node2D under `npcs`, so a
##                          boss on an impassable cell is RELOCATED before this test can read it: both
##                          wall mutations above left the built cell walkable and `moved` is what spoke.
##                          It can only fire in the case BaseVillage merely warns about — no walkable
##                          cell within 5 tiles — which these villages' open bands make hard to build.
##                          Kept because that case leaves the boss standing in a wall and nothing else
##                          here would notice.
##
const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")
const VILLAGE_DIR := "res://src/maps/villages"
const TILE := 32


## Every Masterite a village constructs and the position it was AUTHORED at, straight from the
## source. The authored coordinate is the only thing that can contradict a relocation, which repairs
## the symptom the walkability arm reads: a boss shunted onto a walkable cell passes that arm.
func _declared() -> Dictionary:
	var out := {}
	var d := DirAccess.open(VILLAGE_DIR)
	assert_not_null(d, "FLOOR: %s must be listable — the expected set is derived from it" % VILLAGE_DIR)
	if d == null:
		return out
	var id_rx := RegEx.create_from_string('\\.monster_id\\s*=\\s*"(masterite_[a-z_]+)"')
	var pos_rx := RegEx.create_from_string('\\.position\\s*=\\s*Vector2\\(\\s*([0-9.]+)\\s*\\*\\s*TILE_SIZE\\s*,\\s*([0-9.]+)\\s*\\*\\s*TILE_SIZE\\s*\\)')
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f)
		for m in id_rx.search_all(src):
			var pm := pos_rx.search(src, m.get_end())
			assert_not_null(pm, "%s: %s declares no `position = Vector2(x * TILE_SIZE, y * TILE_SIZE)` after it" % [f, m.get_string(1)])
			if pm == null:
				continue
			out[m.get_string(1)] = {
				"file": f,
				"pos": Vector2(float(pm.get_string(1)) * TILE, float(pm.get_string(2)) * TILE),
			}
	return out


func _encounters_in(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c.has_method("defeat_flag") and c.has_method("_prereq_met"):
			acc.append(c)
		_encounters_in(c, acc)


func _npc_cells(n: Node, acc: Dictionary) -> void:
	for c in n.get_children():
		if c.has_method("get_npc_id") and c is Node2D:
			var p: Vector2 = (c as Node2D).position
			acc[str(Vector2i(int(p.x / TILE), int(p.y / TILE)))] = str(c.name)
		_npc_cells(c, acc)


func test_every_placed_masterite_stands_on_a_walkable_cell_of_its_own() -> void:
	var blocked: Array = []
	var shared: Array = []
	var moved: Array = []
	var seen_ids: Array = []
	var declared := _declared()
	var oracle_said_no := 0
	var villages_walked := 0

	for path in MapScripts.maps_in(VILLAGE_DIR):
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var village = load(path).new()
		vp.add_child(village)
		await get_tree().physics_frame
		await get_tree().process_frame
		villages_walked += 1
		if not village.has_method("_is_cell_walkable"):
			continue
		## The oracle must be able to say NO, or "0 blocked" is free. (0,0) is perimeter wall everywhere.
		if not village._is_cell_walkable(Vector2i(0, 0)):
			oracle_said_no += 1

		var found: Array = []
		_encounters_in(village, found)
		if found.is_empty():
			continue
		var occupied := {}
		_npc_cells(village, occupied)
		for enc in found:
			var mid: String = str(enc.get("monster_id"))
			seen_ids.append(mid)
			var pos: Vector2 = (enc as Node2D).position
			var cell := Vector2i(int(pos.x / TILE), int(pos.y / TILE))
			if not village._is_cell_walkable(cell):
				blocked.append("%s: %s at %s is on an impassable cell — BaseVillage will shunt it half a tile and warn" % [path.get_file(), mid, str(cell)])
			var key := str(cell)
			if occupied.has(key):
				shared.append("%s: %s shares %s with %s — interaction is nearest-wins, so one of them may never be selected" % [path.get_file(), mid, str(cell), occupied[key]])
			occupied[key] = mid
			## RELOCATION, read against the authored coordinate rather than a grid convention —
			## Grimhollow's Arbiter is authored on a half-tile deliberately, so "off-grid" is not the
			## signature here. BaseVillage._validate_placements shunts any Node2D under `npcs` off an
			## impassable cell, warns, and moves on; after that the cell IS walkable and the arm above
			## is satisfied. Only the source can say the boss is not where its author put it.
			if declared.has(mid) and pos != Vector2(declared[mid]["pos"]):
				moved.append("%s: %s was authored at %s and stands at %s — BaseVillage relocated it off an impassable cell" % [path.get_file(), mid, str(declared[mid]["pos"]), str(pos)])

	## CONTROLS FIRST — each of the three claims below is empty for free if the sweep did not run.
	assert_gt(villages_walked, 11, "CONTROL: only %d villages built — the sweep is broken" % villages_walked)
	assert_gt(oracle_said_no, 11, "CONTROL: only %d villages could call a wall impassable — the oracle is not answering" % oracle_said_no)
	assert_gt(declared.size(), 0, "CONTROL: no monster_id parsed out of the village sources — the expected set is empty")
	var declared_ids: Array = declared.keys()
	declared_ids.sort()
	seen_ids.sort()
	assert_eq(seen_ids, declared_ids,
		("the built scenes hold a different set of Masterites than the sources declare.\n" +
		"A placement behind an `if` that is false at _ready, or a renamed local var, lands here —\n" +
		"and every arm below would have been silently empty about it.\nbuilt: %s\nsource: %s") % [str(seen_ids), str(declared_ids)])

	assert_eq(blocked, [], "a Masterite on an impassable cell:\n  %s" % "\n  ".join(blocked))
	assert_eq(shared, [], "a Masterite sharing a cell:\n  %s" % "\n  ".join(shared))
	assert_eq(moved, [], "a Masterite is not where it was authored:\n  %s" % "\n  ".join(moved))
