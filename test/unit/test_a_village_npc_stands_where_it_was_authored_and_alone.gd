extends GutTest

## Three NPCs were standing somewhere nobody put them, and one of them was sharing a tile.
##
## `BaseVillage` relocates any body it finds on an impassable cell — half a tile diagonally, with a
## `push_warning` nobody reads. Three villages authored an NPC onto a cell that already held a PROP:
##
##     MapleHeights  Gerald (10,15)            planter    -> (304,464), ONTO Neighborhood Dad's tile
##     Grimhollow    Creepy Child Wednesday    barrel     -> (240,336)
##     Sandrift      Sand Sage Mirage          cart       -> (240,496)
##
## 🔑 GERALD'S IS THE ONE THAT COST SOMETHING. Interaction is nearest-wins, so two NPCs on one cell
## means the far one may never be selected — and Gerald is a quest giver (`gerald_w2`). The other two
## were merely standing a tile from where the author placed them, which nothing would ever report.
##
## Fixed by moving the PROPS, not the NPCs: a planter is decoration, a quest giver's position is
## content. The three guards below are what makes it stay fixed.
##
## ⛔ SINGLE-DIRECTION, STATED RATHER THAN FIXED (@cowir-deploy's framing, 2026-09-11: direction is
## not a fourth axis, it is a property of the SUBJECT — what the premise quantifies over). This
## quantifies over NPCs THAT EXIST and asserts properties of them. It says nothing about NPCs that
## SHOULD exist and do not: a deleted NPC is not sealed in, shares no tile and is on no grid, so
## deletion satisfies every assert here by construction. "Cannot be fooled" and "would detect it" are
## different claims and this file only has the first.
## The corpus SIZE is covered (router equality below) and three named members are pinned; individual
## NPC inventory is not, and a ratchet over ~94 names would cost a line per NPC forever. If you need
## "did someone delete a villager", that is a different guard and it does not exist yet.
##
## ⚠️ SCOPE IS TALKING NPCS — nodes answering `get_npc_id()`. Shops, inns and doors are deliberately
## ON impassable tiles (you interact from beside them) and their Area2D is two tiles wide, so a
## cell-based reachability rule is simply the wrong question for them: measured, 5 of them have no
## walkable neighbour at all and every one is correct. 94 talking NPCs across 13 villages; 0 sealed.

const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")
const VILLAGE_DIR := "res://src/maps/villages"
const TILE := 32

## Off-grid positions are USUALLY the relocation signature. This one is not — and an entry costs a
## reason, so nobody can quiet a real relocation by appending a name.
const MAY_STAND_OFF_GRID := {
	## ⚠️ THE REASON WAS WRONG AND THE ENTRY WAS RIGHT. It said "so the booth sits between two mall
	## units" — inferred, never checked. Measured: MapleStripMall's row 6 is `...YYYYYpOOp...`, so
	## cols 23-24 are her OWN two-tile booth (`"S", "O"` both map to HOUSE_WALL, :95), and the
	## half-tile centres her under it on the row-7 walkway. @cowir-sfx, 2026-09-11: the delete-the-
	## entry test proves an entry is LOAD-BEARING and says nothing about whether its stated reason is
	## TRUE — and a load-bearing entry's explanation is the one thing nothing can ever contradict.
	"Madame Orrery": "half-tile X (23 * TILE_SIZE + TILE_SIZE / 2) centres her under her own two-tile booth at cols 23-24, standing on the row-7 walkway",
}


func _npcs_in(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c.has_method("get_npc_id"):
			acc.append(c)
		_npcs_in(c, acc)


func _name_of(n: Node) -> String:
	var who = n.get("npc_name")
	return str(who) if who != null and str(who) != "" else str(n.name)


func test_no_village_npc_is_sealed_in_shares_a_tile_or_was_quietly_moved() -> void:
	var sealed: Array = []
	var shared: Array = []
	var off_grid: Array = []
	var names: Array = []
	var names_to_node := {}
	var villages := 0
	var built: Array = []
	var npcs_seen := 0
	var oracle_said_no := 0

	for path in MapScripts.maps_in(VILLAGE_DIR):
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var village = load(path).new()
		vp.add_child(village)
		await get_tree().physics_frame
		await get_tree().process_frame
		villages += 1
		built.append(path.get_file())
		if not village.has_method("_is_cell_walkable"):
			continue
		## The oracle must be able to say NO, or "0 sealed" is free. (0,0) is perimeter wall in every
		## village's map_data.
		if not village._is_cell_walkable(Vector2i(0, 0)):
			oracle_said_no += 1

		var found: Array = []
		_npcs_in(village, found)
		var occupied := {}
		for npc in found:
			npcs_seen += 1
			var who := _name_of(npc)
			names.append(who)
			names_to_node[who] = npc
			var pos: Vector2 = npc.position
			var cell := Vector2i(int(pos.x / TILE), int(pos.y / TILE))

			var standable := false
			for dx in [0, -1, 1]:
				for dy in [0, -1, 1]:
					if village._is_cell_walkable(Vector2i(cell.x + dx, cell.y + dy)):
						standable = true
			if not standable:
				sealed.append("%s: %s at %s has no walkable cell to be spoken to from" % [path.get_file(), who, str(cell)])

			var key := str(cell)
			if occupied.has(key):
				shared.append("%s: %s and %s both stand on %s" % [path.get_file(), who, occupied[key], str(cell)])
			occupied[key] = who

			if (int(pos.x) % TILE != 0 or int(pos.y) % TILE != 0) and not MAY_STAND_OFF_GRID.has(who):
				off_grid.append("%s: %s at %s" % [path.get_file(), who, str(pos)])

	## ⛔ A FLOOR IS BLIND TO PARTIAL LOSS (@cowir-adhoc, confirmed by @cowir-controller the same hour:
	## their `examined > 4` caught a two-file drain and MISSED a one-file one, and a rename touches one
	## file, not both). `villages > 11` would stay green with TWO villages silently gone — including
	## Grimhollow or Sandrift, whose prop moves this guard exists to hold. Named membership instead:
	## every village this test made a claim about must have actually been built.
	## ⛔ A DERIVED CORPUS DOES NOT LOSE MEMBERS — IT NEVER HAD THEM (@cowir-sprites, measured on their
	## own branch: 43 of 145 sheets hidden, guard green, because the filter simply stopped nominating
	## them and no quantity inside the guard moved). MapScripts derives villages by extends-chain, so
	## one `extends` line rewritten and a village is not skipped — it is never a candidate, and only
	## the floor below is watching. So the SIZE is pinned against an INDEPENDENT REGISTER that cannot
	## shrink with the corpus it checks: GameLoop's own map-id router, which is how the game reaches
	## these villages at all. Both sides derived, no hand-list to go stale when a village is added.
	assert_gt(villages, 11, "CONTROL: only %d villages built — the sweep is broken" % villages)
	var routed := _router_village_arms()
	assert_gt(routed, 8, "CONTROL: only %d '<name>_village' arms found in GameLoop — the register read is broken" % routed)
	var walked_named := 0
	for f in built:
		if str(f).ends_with("Village.gd"):
			walked_named += 1
	assert_eq(walked_named, routed,
		("the game routes to %d villages and this sweep walked %d of them.\n" +
		"A village whose `extends` line changed is not SKIPPED by MapScripts — it is never nominated,\n" +
		"so nothing here counts it missing. Walked: %s") % [routed, walked_named, str(built)])
	for must in ["MapleHeightsVillage.gd", "GrimhollowVillage.gd", "SandriftVillage.gd"]:
		assert_true(must in built,
			("CONTROL: %s did not build, so its NPCs were never examined and the empty lists below " +
			"are half a result reported as a whole one. Built: %s") % [must, str(built)])
	assert_gt(npcs_seen, 80, "CONTROL: only %d NPCs found, so the empty lists below are free" % npcs_seen)
	## ⚠️ THIS ASSERT HAS TWO CAUSES AND ITS MESSAGE USED TO NAME ONE. It compares villages EXAMINED
	## against villages BUILT, so it fires both when the oracle is broken AND when a village was
	## instantiated and then silently skipped by a narrowing `if` above — @cowir-deploy's shape, where
	## the filter IS the floor and there is no number to grep for. Measured: skipping one village reds
	## here, so the coverage was already right and only the DIAGNOSIS was wrong. A reader sent to
	## debug _is_cell_walkable for a skipped village loses the afternoon.
	assert_eq(oracle_said_no, villages,
		("%d village(s) were BUILT but never EXAMINED. Two causes, check in this order:\n" +
		"  1. a narrowing `if` above skipped them (has_method, a continue) — the corpus shrank silently\n" +
		"  2. _is_cell_walkable called cell (0,0) walkable — it is perimeter wall, so the oracle is broken\n" +
		"Either way every 'sealed' check below is vacuous for those villages.") % (villages - oracle_said_no))
	assert_true("Surplus Ray" in names,
		"CONTROL: the walk never reached Maple Heights' newest NPC, so it is not reaching authored content")
	## He exists to carry one beat out of an uncalled cutscene: the first villager who names the
	## Coordinator. If that line goes, the recovery is undone and only the placement survives.
	assert_true(_lines_of(names_to_node.get("Surplus Ray")).contains("Coordinator"),
		"Surplus Ray no longer names the Coordinator — the W2 setup he was authored to deliver is gone")
	for who in MAY_STAND_OFF_GRID:
		assert_gt(str(MAY_STAND_OFF_GRID[who]).length(), 30,
			"MAY_STAND_OFF_GRID['%s'] needs a reason naming the deliberate offset, not a placeholder" % who)

	assert_eq(sealed, [], "NPCs the player cannot stand next to: %s" % str(sealed))
	assert_eq(shared, [],
		("two NPCs on one tile — interaction is NEAREST-WINS, so one of them may never be selected: %s\n" +
		"Usually a PROP shares the authored cell and the village relocated the NPC onto its neighbour.") % str(shared))
	assert_eq(off_grid, [],
		("NPC not on the tile grid: %s\n" +
		"USUALLY THIS IS A RELOCATION, NOT A CHOICE: BaseVillage shifts any body standing on an\n" +
		"impassable cell half a tile and warns where nobody looks. Check for a prop on the authored\n" +
		"cell and MOVE THE PROP — decoration yields to content (MapleHeights 10,15 · Grimhollow 8,11\n" +
		"· Sandrift 8,16 were all this). If the offset really is deliberate, add the NPC to\n" +
		"MAY_STAND_OFF_GRID with a reason.") % str(off_grid))


## All of an NPC's authored lines as one string, "" when the node is absent.
func _lines_of(npc) -> String:
	if npc == null:
		return ""
	var lines = npc.get("dialogue_lines")
	return "" if lines == null else " | ".join(PackedStringArray(lines))


## How many villages GameLoop can actually route to — an independent register for the corpus size.
## Read from the match arms in _start_exploration, so adding a village updates it for free.
func _router_village_arms() -> int:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var at := src.find("func _start_exploration")
	if at < 0:
		return 0
	var re := RegEx.new()
	re.compile('(?m)^\t\t"([a-z0-9_]+_village)":')
	return re.search_all(src.substr(at, 9000)).size()
