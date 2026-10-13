extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const DIR := "res://src/maps/interiors/"
const NOT_A_ROOM := ["BaseInterior.gd", "InteriorPlacementSweep.gd"]

## Villages have had this guard since 2026-10-12 — `test_a_village_npc_stands_where_it_was_authored
## _and_alone` asserts `shared == []` over 94 talking NPCs in 13 villages. INTERIORS HAD NO
## COUNTERPART, and interiors are where the inn, the tavern, the shop and the chapel are.
##
## ⛔ WHY THE PLACEMENT SWEEP IS NOT THIS GUARD. `InteriorPlacementSweep` moves a node off walls and
## furniture, and refuses to RELOCATE one onto an occupied cell. It does not look at a node that was
## already standing on an occupied cell: `_is_position_clear` answers about walls and furniture and
## never about who is there, so two nodes on one ALREADY-CLEAR cell both pass the reservation test
## and neither becomes a mover. The sweep running clean is not evidence of no collision.
##
## 🔑 AND TEACHING IT TO DODGE WOULD BE THE WRONG FIX — cowir-main REJECTED exactly that for villages
## (2026-10-12): moving an NPC trades a loud authoring error for a silent content change. So the
## remedy for anything this arm catches is to move the PROP or re-author the cell, and the arm's job
## is to be loud. `BaseInterior`'s examine loader resolves its own derived cells against occupancy
## for the same reason, which is a different case: a readable's cell is computed, an NPC's is written.
##
## ⚠️ A SOURCE SCAN GETS THIS WRONG IN BOTH DIRECTIONS, which is why this is a runtime arm. Scanning
## for two `_create_npc` calls on one coordinate reports `ShopInterior`'s Gethena and Aldric — who
## are in `ShopType.ITEM` and `ShopType.BLACK_MAGIC`, mutually exclusive match arms that never
## coexist. That was my own first measurement and it was a false positive. The other direction is
## worse: positions computed from a spawn, a const or a `.repeat()` expression are invisible to any
## regex, and the authored pair one cell apart that the RELOCATOR stacks has no source form at all.

const TILE: int = 32

var _vp: SubViewport = null


func _rooms() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	assert_not_null(d, "CONTROL: the interiors directory must be readable")
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") and not (f in NOT_A_ROOM):
			out.append(f)
	out.sort()
	return out


func _label(n: Node) -> String:
	var nm = n.get("npc_name")
	if nm != null and str(nm) != "":
		return str(nm)
	return str(n.name)


func test_no_room_puts_two_interactables_on_one_cell() -> void:
	var scripts := _rooms()
	assert_gt(scripts.size(), 25,
		"CONTROL: found %d interior scripts; a short list would clear nothing" % scripts.size())
	var built := 0
	var examined := 0
	var shared: Array = []
	for f in scripts:
		var scr = load(DIR + f)
		if scr == null or not (scr is GDScript) or not scr.can_instantiate():
			continue
		_vp = SubViewport.new()
		_vp.size = Vector2i(64, 64)
		_vp.world_2d = World2D.new()
		add_child_autofree(_vp)
		var room = scr.new()
		if room == null:
			continue
		_vp.add_child(room)
		await get_tree().physics_frame
		await get_tree().physics_frame
		built += 1
		## Everything a press can land on, wherever the room parked it.
		var byc: Dictionary = {}
		var stack: Array = [room]
		while not stack.is_empty():
			var n = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if not (n is Node2D):
				continue
			if not (n.has_method("interact") or n.is_in_group("interactables")):
				continue
			examined += 1
			var cell := Vector2i(int(floor((n as Node2D).global_position.x / TILE)),
				int(floor((n as Node2D).global_position.y / TILE)))
			if not byc.has(cell):
				byc[cell] = []
			(byc[cell] as Array).append(_label(n))
		for cell in byc.keys():
			var who: Array = byc[cell]
			if who.size() > 1:
				who.sort()
				shared.append("%s cell %s holds %d: %s — interaction is nearest-wins and identical anchors never tie in the loser's favour, so all but one are unreachable; move the PROP or re-author the cell" % [
					f, str(cell), who.size(), ", ".join(who)])
		room.queue_free()
		await get_tree().process_frame
		_vp.queue_free()
		await get_tree().process_frame
	assert_gt(built, 25, "CONTROL: %d rooms built" % built)
	assert_gt(examined, 25,
		"CONTROL: only %d interactables found across %d rooms — the collector is not collecting" % [examined, built])
	shared.sort()
	assert_eq(shared, [], "an interior stacks interactables: %s" % "; ".join(shared))
	## ⚠️ A COUNT, NOT A CLAIM. This line read "no two on one cell" and GUT does not abort on a
	## failed assert, so it printed that sentence in a run that had just NAMED a stacked pair.
	gut.p("  %d rooms, %d interactables, %d shared cell(s)" % [built, examined, shared.size()])


## Every room's _ready calls play_area_music, so building thirty writes SoundManager's area/world
## state without naming any of it.
func after_all() -> void:
	SoundState.restore()
