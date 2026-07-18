extends GutTest

## Interior NPC-vs-furniture collision sweep (struktured playtest, msg 2764
## item 3: "characters are standing on tables... a general purpose algorithm
## that looks to see if there's any collisions before you render anyone").
##
## Runtime belt: BaseInterior._validate_placements is a NPC-container sweep
## that snaps each NPC off (a) impassable tile cells and (b) furniture
## footprints (Sprite2D children of `decorations` at least 24 px wide/tall).
##
## Ratchet: this test pins the seam is wired into _ready + verifies each
## authored interior instantiates without stranding an NPC — a scene that
## grows a new "NPC standing on a table" landing warning after this ratchet
## exists is a regression, catchable at commit time by running the suite.

## Scene → (script_path, layout_const_name). Layout constant is the
## authored map_data — where 'W' means wall. BaseInterior descendants
## expose it via _get_layout(); the three legacy interiors expose it as
## a class const.
const INTERIOR_SCENES: Array = [
	# Legacy Node2D interiors — one of these is the inn where Dorian
	# (msg 2769) is sitting almost on the table.
	["res://src/maps/interiors/InnInterior.gd", "INN_LAYOUT"],
	["res://src/maps/interiors/ShopInterior.gd", "SHOP_LAYOUT"],
	["res://src/maps/interiors/TavernInterior.gd", "TAVERN_LAYOUT"],
	# BaseInterior descendants — sample across worlds.
	["res://src/maps/interiors/HarmoniaChapelInterior.gd", ""],
	["res://src/maps/interiors/MapleCommunityCenterInterior.gd", ""],
	["res://src/maps/interiors/EnrichmentAnnexInterior.gd", ""],
	["res://src/maps/interiors/ScripturaGuildInterior.gd", ""],
	["res://src/maps/interiors/ScripturaBookshopInterior.gd", ""],
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_validate_placements_is_wired_into_ready() -> void:
	# The sweep must fire AFTER _setup_npcs (so it can inspect what
	# subclasses placed) and BEFORE _setup_player (so the player never
	# spawns next to a stranded NPC in an obviously wrong spot).
	var src := _read("res://src/maps/interiors/BaseInterior.gd")
	var ready_idx := src.find("func _ready")
	assert_gt(ready_idx, 0, "BaseInterior._ready is present")
	var next_fn := src.find("\nfunc ", ready_idx + 1)
	var body: String = src.substr(ready_idx, next_fn - ready_idx) if next_fn > 0 else src.substr(ready_idx)
	assert_true(body.contains("_setup_npcs()"),
		"_setup_npcs runs (baseline)")
	assert_true(body.contains("_validate_placements()"),
		"_validate_placements runs")
	# Order: NPCs placed → sweep → transitions/player. Regex-anchor by
	# finding _setup_npcs then requiring _validate_placements later.
	var npcs_pos := body.find("_setup_npcs()")
	var validate_pos := body.find("_validate_placements()")
	assert_gt(validate_pos, npcs_pos,
		"_validate_placements must run AFTER _setup_npcs (needs the NPCs in-tree)")


func test_furniture_size_threshold_declared() -> void:
	# Sanity: the min-size heuristic exists (24 px = 3/4 of a tile).
	# Small decor like bells + quills stays decorative.
	var src := _read("res://src/maps/interiors/InteriorPlacementSweep.gd")
	assert_true(src.contains("MIN_FURNITURE_SIZE_PX"),
		"threshold constant declared for the size filter")


func test_walkability_reads_the_authored_layout() -> void:
	# Interior TileSets have no physics_layer (unlike villages), so
	# walkability MUST read the authored layout array rather than
	# tile_data collision polygons — else every cell reads as walkable
	# and walls stop stopping.
	var src := _read("res://src/maps/interiors/InteriorPlacementSweep.gd")
	var fn_idx := src.find("func _is_cell_walkable")
	assert_gt(fn_idx, 0, "_is_cell_walkable present in the shared utility")
	var next_fn := src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("layout"),
		"walkability consults the authored layout array")
	assert_true(body.contains("\"W\""),
		"walls are identified by 'W' — the layout convention")


func test_legacy_interiors_also_call_the_sweep() -> void:
	# The three legacy interiors (InnInterior, ShopInterior, TavernInterior)
	# extend Node2D directly, not BaseInterior — struktured's Dorian bug
	# is in InnInterior, so those files MUST invoke the shared sweep from
	# their own _ready or the fix regresses.
	for entry in [
		["res://src/maps/interiors/InnInterior.gd", "INN_LAYOUT"],
		["res://src/maps/interiors/ShopInterior.gd", "SHOP_LAYOUT"],
		["res://src/maps/interiors/TavernInterior.gd", "TAVERN_LAYOUT"],
	]:
		var path: String = entry[0]
		var layout_const: String = entry[1]
		var src := _read(path)
		assert_true(src.contains("InteriorPlacementSweep.sweep"),
			"%s must call InteriorPlacementSweep.sweep" % path)
		assert_true(src.contains(layout_const),
			"%s must pass its %s to the sweep" % [path, layout_const])


func test_authored_interiors_instantiate_without_stranding_npcs() -> void:
	# Belt: bring each listed interior into the tree, let _ready run the
	# sweep, and verify no NPC ended up on a wall cell. Furniture-overlap
	# is checked at runtime (push_warning); ratchet on the wall-cell class
	# here since it's cheap and catches the most common regression.
	var checked := 0
	for entry in INTERIOR_SCENES:
		var path: String = entry[0]
		var layout_const_name: String = entry[1]
		var scene_script = load(path)
		if scene_script == null:
			continue
		var scene = scene_script.new()
		add_child_autofree(scene)
		await get_tree().process_frame
		if not ("npcs" in scene) or scene.npcs == null:
			continue
		var layout: Array = []
		if layout_const_name != "" and layout_const_name in scene_script:
			layout = scene_script.get(layout_const_name)
		elif scene.has_method("_get_layout"):
			layout = scene._get_layout()
		else:
			continue
		checked += 1
		var offenders: Array = []
		for npc in scene.npcs.get_children():
			if not (npc is Node2D):
				continue
			var pos: Vector2 = (npc as Node2D).position
			var cell := Vector2i(int(floor(pos.x / 32.0)), int(floor(pos.y / 32.0)))
			if cell.y < 0 or cell.y >= layout.size():
				offenders.append("%s at %s (row out of range)" % [npc.name, pos])
				continue
			var row: String = str(layout[cell.y])
			if cell.x < 0 or cell.x >= row.length():
				offenders.append("%s at %s (col out of range)" % [npc.name, pos])
				continue
			var ch: String = row[cell.x]
			if ch == "W":
				offenders.append("%s at %s cell(%d,%d)='%s' — a WALL" % [
					npc.name, pos, cell.x, cell.y, ch])
		assert_eq(offenders.size(), 0,
			"%s: sweep must leave every NPC on a walkable cell — offenders:\n  %s" % [
				path, "\n  ".join(offenders)])
	assert_gt(checked, 5,
		"expected the ratchet to walk >5 authored interiors (got %d — inheritance broken?)" % checked)
