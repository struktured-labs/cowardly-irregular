extends GutTest

## A chest holding a sword must SAY it holds equipment.
##
## TreasureChest routes on an AUTHORED discriminator, not on what the item is:
##   "item"      -> party[0].add_item()          the consumable inventory
##   "equipment" -> GameLoop.equipment_pool      what EquipmentMenu reads
## The two never meet. A chest authored `contents_type = "item"` whose
## contents_id is a sword hands the player a weapon they can never equip — it
## sits in the item menu forever as a dead entry.
##
## This is not hypothetical and not my discovery. The same class has now been
## found and fixed on four separate grant paths: battle drops
## (BattleManager._route_drop_to_equipment_pool, whose own comment says pre-fix
## "EVERY drop went into add_item, leaving equipment as unusable lore items"),
## treasure chests, shops, and — 2026-08-06, cowir-story — quest rewards, where
## a +140-attack sword was granted with add_item alone. Each was fixed
## individually; nothing pinned the invariant, so the fifth author reintroduces
## it.
##
## Swept at the time of writing: 20 chest-placing scripts, 0 mis-routed in
## either direction. The deliverable is therefore the guard, not a fix.
##
## DRIVEN, not source-parsed. An earlier pass of this scan matched only the
## dict-literal authoring style and reported a clean 0 while never looking at
## the 7 sites that use direct assignment — a wrong-shape zero that read exactly
## like a clean sweep. Building the scene and reading the nodes has no shape
## assumption in it at all.

const EQUIPMENT_JSON := "res://data/equipment.json"


func _equipment_ids() -> Dictionary:
	var out := {}
	var txt := FileAccess.get_file_as_string(EQUIPMENT_JSON)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for section in parsed:
		if typeof(parsed[section]) == TYPE_DICTIONARY:
			for id in parsed[section]:
				out[str(id)] = str(section)
	return out


## Derived: every script that places a chest, found by what it CONTAINS rather
## than a maintained list, so a new chest-bearing map is covered on arrival.
func _chest_placing_scripts() -> Array:
	var out: Array = []
	var stack: Array = ["res://src/exploration", "res://src/maps"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for sub in dir.get_directories():
			stack.append(d + "/" + sub)
		for f in dir.get_files():
			if not f.ends_with(".gd") or f == "TreasureChest.gd":
				continue
			var path := d + "/" + f
			if FileAccess.get_file_as_string(path).contains("contents_type ="):
				out.append(path)
	out.sort()
	return out


func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


func _collect_chests(root: Node, into: Array) -> void:
	for child in root.get_children():
		if child is TreasureChest:
			into.append(child)
		_collect_chests(child, into)


## The control the sweep cannot supply for itself: prove the corpus is real and
## that membership can come back false, so "nothing mis-routed" means the check
## ran rather than that it matched nothing.
func test_the_equipment_corpus_is_real_and_can_report_absence() -> void:
	var eq := _equipment_ids()
	assert_gt(eq.size(), 0, "parsed equipment ids from equipment.json — zero makes every check below vacuous")
	var a_known: String = ""
	for id in eq:
		a_known = str(id)
		break
	assert_true(eq.has(a_known), "a known member (%s) is present — the positive half" % a_known)
	assert_false(eq.has("zzz_definitely_not_a_real_weapon"),
		"a fabricated id is absent — without this, membership could be true of everything and the sweep would pass blind")


func test_every_placed_chest_routes_by_what_it_actually_holds() -> void:
	var eq := _equipment_ids()
	assert_gt(eq.size(), 0, "equipment corpus loaded")
	var files := _chest_placing_scripts()
	assert_gt(files.size(), 0, "found chest-placing scripts — zero would pass this file for free")

	var chests_seen := 0
	var by_type := {}
	var files_yielding := 0
	var build_failures: Array = []
	var offenders: Array = []

	for path in files:
		var script = load(path)
		if script == null:
			build_failures.append("%s: failed to load" % path)
			continue
		var node = script.new()
		if node == null or not (node is Node):
			if node is Node:
				node.free()
			continue
		_isolated_viewport().add_child(node)
		await get_tree().process_frame

		var found: Array = []
		_collect_chests(node, found)
		if not found.is_empty():
			files_yielding += 1
		for chest in found:
			chests_seen += 1
			var ctype: String = str(chest.contents_type)
			var cid: String = str(chest.contents_id)
			by_type[ctype] = int(by_type.get(ctype, 0)) + 1
			if ctype == "equipment" and not eq.has(cid):
				offenders.append("%s: chest declares 'equipment' but '%s' is not in equipment.json — it lands in a pool EquipmentMenu can show but nothing can resolve" % [path.get_file(), cid])
			elif ctype == "item" and eq.has(cid):
				offenders.append("%s: chest declares 'item' but '%s' IS equipment (%s) — add_item puts it in the consumable inventory and it can never be equipped" % [path.get_file(), cid, str(eq[cid])])

	assert_true(build_failures.is_empty(),
		"%d chest-placing script(s) could not be loaded, so their chests were never inspected:\n  %s" % [
			build_failures.size(), "\n  ".join(build_failures)])
	assert_gt(chests_seen, 0,
		"inspected %d scripts and found ZERO chest nodes — the placement pattern changed and this sweep is now blind" % files.size())
	assert_gt(files_yielding, 1,
		"only %d script actually yielded chests — too few for this to be a sweep" % files_yielding)
	assert_true(by_type.has("item") and by_type.has("equipment"),
		"both routes are represented among placed chests (saw %s) — if one is absent, half the invariant is untested" % str(by_type))
	assert_true(offenders.is_empty(),
		"%d of %d placed chest(s) route by the wrong path:\n  %s" % [
			offenders.size(), chests_seen, "\n  ".join(offenders)])
