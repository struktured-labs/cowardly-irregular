extends BaseVillage
class_name ScripturaPlaza

## ScripturaPlaza — the capital district stub (cowir-story ruled scope, msg 2159):
## one plaza + Scriptweaver's Guild + Independent bookshop + a Palace-district
## gate (landmark, not enterable). Clean stone, oppressive politeness. Unblocks
## word_from_capital (Rowan → Aldrin in the bookshop → Rowan), thirty_seven
## (guild scholar + the overdue-book pickup by the palace gate), and
## untested_edge's guild-scholar translation path.

# TILE_SIZE + spawn_points inherit from BaseVillage — do not redeclare.
const MAP_WIDTH: int = 30
const MAP_HEIGHT: int = 22


func _get_area_id() -> String:
	return "scriptura_plaza"


func _get_music_area_id() -> String:
	return "village"


func _get_village_display_name() -> String:
	return "Scriptura"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(15 * TILE_SIZE,15 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(15 * TILE_SIZE,17 * TILE_SIZE)


func _generate_map() -> void:
	# G = Guild facade, B = Bookshop facade, P = Palace-gate structure (grand,
	# impassable), F = fountain, p = stone plaza path, d = worn dirt, f = flower,
	# X = exit road (south). Every row is exactly MAP_WIDTH (24) chars.
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"W............................W",
		"W............................W",
		"W...ppppppPPPPPPPPPPpppppp...W",
		"W...ppppppPPPPPPPPPPpppppp...W",
		"W...pppppppPPPPPPPPppppppp...W",
		"W...pppppppppppppppppppppp...W",
		"W...ppGGGGGppppppppBBBBBpp...W",
		"W...ppGGGGGppppppppBBBBBpp...W",
		"W...ppGGGGGppppppppBBBBBpp...W",
		"W...ppGGGGGppppppppBBBBBpp...W",
		"W...pppppppppFFFFppppppppp...W",
		"W...pppppppppFFFFppppppppp...W",
		"W...pppppppppppppppppppppp...W",
		"W...ppffppppppppppppppffpp...W",
		"W...pppppppppppppppppppppp...W",
		"W...pppppppppppppppppppppp...W",
		"W...pppppppppppppppppppppp...W",
		"W...pppppppppXXXXppppppppp...W",
		"W............................W",
		"W............................W",
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	]
	for y in range(MAP_HEIGHT):
		var row: String = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var ch: String = row[x] if x < row.length() else "W"
			var tile_type := _char_to_tile_type(ch)
			var atlas := _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas)
			if ch == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	spawn_points["entrance"] = Vector2(15 * TILE_SIZE,17 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	# Interiors return here (guild_exit / bookshop_exit) just below their doors.
	spawn_points["guild_exit"] = Vector2(7 * TILE_SIZE,11 * TILE_SIZE)
	spawn_points["bookshop_exit"] = Vector2(22 * TILE_SIZE,11 * TILE_SIZE)


func _char_to_tile_type(ch: String) -> int:
	match ch:
		"W": return TileGeneratorScript.TileType.WALL
		"G", "B", "P": return TileGeneratorScript.TileType.WALL  # building / gate walls
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"d": return TileGeneratorScript.TileType.VILLAGE_DIRT
		"f": return TileGeneratorScript.TileType.VILLAGE_FLOWER
		"F": return TileGeneratorScript.TileType.WATER
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.VILLAGE_PATH


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id: int = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	# Exit road south → back to the W1 overworld at the Scriptura landmark.
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "scriptura_return"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(15 * TILE_SIZE,18 * TILE_SIZE))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 4, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# Scriptweaver's Guild (left facade) and Aldrin's Books (right facade).
	_add_interior_door("GuildDoor", "scriptura_guild", "Scriptweaver's Guild",
		Vector2(7 * TILE_SIZE,10 * TILE_SIZE))
	_add_interior_door("BookshopDoor", "scriptura_bookshop", "Aldrin's Books",
		Vector2(22 * TILE_SIZE,10 * TILE_SIZE))
	_build_palace_gate()


## The Palace-district gate — grand, guarded, NOT enterable. The joke: the
## capital's most exclusive district keeps its overdue library returns in a
## bin by the gate (a mailroom). Purely a landmark + the book-pickup anchor.
func _build_palace_gate() -> void:
	var gate := Sprite2D.new()
	gate.name = "PalaceGate"
	var img := Image.create(TILE_SIZE * 8, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var stone := Color(0.72, 0.70, 0.66)
	var stone_dk := Color(0.55, 0.53, 0.50)
	var gold := Color(0.82, 0.70, 0.32)
	var dark := Color(0.10, 0.10, 0.13)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			# two grand columns + a lintel, dark archway between
			var col_l := x >= w * 0.18 and x < w * 0.34
			var col_r := x >= w * 0.66 and x < w * 0.82
			var lintel := y < h * 0.28
			if col_l or col_r or lintel:
				var c := stone if (x + y) % 6 != 0 else stone_dk
				if lintel and y < 5:
					c = gold  # gilded top edge
				img.set_pixel(x, y, c)
			elif x >= w * 0.34 and x < w * 0.66 and y >= h * 0.28:
				img.set_pixel(x, y, dark)  # the archway (into the district, closed)
	gate.texture = ImageTexture.create_from_image(img)
	gate.centered = true
	gate.position = Vector2(15 * TILE_SIZE,4 * TILE_SIZE)
	buildings.add_child(gate)


func _setup_npcs() -> void:
	# ── Quest-critical: the overdue-book pickup (thirty_seven step 3) ──
	# Only present while the scholar's favor has been asked; consumed at turn-in.
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.has_method("is_story_flag_set") \
			and gs.is_story_flag_set("quest_world1_thirty_seven_favor_asked") \
			and not gs.is_story_flag_set("quest_world1_thirty_seven_complete"):
		_place_book_pickup()

	# ── The 4-citizen breadcrumb (word_from_capital: find Aldrin's shop) ──
	# Capital locals point obliquely — helpful in form, evasive in substance;
	# they geometrically converge on the (east-side) bookshop. Authored lines
	# by cowir-story (msg 2278), placed against the fountain/east geometry.
	# Positions shifted +3,+2 alongside the 2026-07-14 plaza grow (msg 2542/2543)
	# to keep the citizens aligned with the fountain + shop geometry they were
	# authored against. citizen_4 at old (16,11) landed in the shifted fountain
	# without this shift — the walkability sweep caught it, this is the fix.
	var breadcrumb := [
		{"id": "scriptura_citizen_1", "pos": Vector2(9, 14),
			"line": "Books? There's a shop, east side, past the notary. I'd point you exactly, only — one doesn't like to be too *specific*. Someone might write it down."},
		{"id": "scriptura_citizen_2", "pos": Vector2(18, 15),
			"line": "The bookseller? Kept to himself. Came up from the provinces a few years back, quiet as a closed drawer. His door's the little one nobody's repainted — the only thing on the row that isn't trying."},
		{"id": "scriptura_citizen_3", "pos": Vector2(12, 16),
			"line": "Go toward the fountain, then don't stop at the fountain. Everyone stops at the fountain. The row behind it — those shops keep regulation hours. That one keeps *his*. I didn't say it."},
		{"id": "scriptura_citizen_4", "pos": Vector2(19, 13),
			"line": "Aldrin's? — I mean, the bookshop, yes. It's right there, honestly. Past the good bench. Little sign you have to already know how to read."},
	]
	for c in breadcrumb:
		var npc = _create_npc("Capital Citizen", "villager",
			Vector2(c["pos"].x * TILE_SIZE, c["pos"].y * TILE_SIZE), [c["line"]])
		npc.npc_id = c["id"]
		npcs.add_child(npc)

	# Rogue lead spots the shop directly — cowir-story's authored line (msg 2278).
	# Doubles as the player's first read on Scriptura's wrongness (the collective
	# not-mentioning is the tell — the Rogue's "sees the second thing" essence).
	if _lead_is_rogue():
		var spotter = _create_npc("(the door the plaza walks around)", "villager",
			Vector2(22 * TILE_SIZE,13 * TILE_SIZE), [
				"There. The small door the whole plaza's walking around. Four people gave me directions to it and not one of them looked at it. That's not a shop nobody knows — that's a shop everybody's decided not to mention.",
			])
		npcs.add_child(spotter)

	# ── Ambient texture (2, lean; cowir-story may enrich later) ──
	# Originals sat inside the guild (7,6) and bookshop (16,6) building
	# blocks (pre-existing bug; the runtime walkability sweep was silently
	# relocating them). Moved onto the mid-plaza walkway so the placement
	# matches intent — clerk south of the guild, warden south of the
	# bookshop — and stays walkable across the 2026-07-14 village grow.
	var clerk = _create_npc("Records Clerk", "scholar",
		Vector2(5, 12) * TILE_SIZE, [
			"Everything is recorded. Everything is fine. Please move along politely.",
		])
	npcs.add_child(clerk)
	var sweeper = _create_npc("Plaza Warden", "guard",
		Vector2(18, 12) * TILE_SIZE, [
			"The plaza is swept twice daily. The district beyond the gate is not for visitors.",
		])
	npcs.add_child(sweeper)


func _place_book_pickup() -> void:
	# overdue_guild_book on a returns-bin bench by the palace gate.
	var TreasureChestScript = load("res://src/exploration/TreasureChest.gd")
	if TreasureChestScript == null:
		return
	var bin = TreasureChestScript.new()
	bin.chest_id = "scriptura_overdue_book_bin"
	bin.contents_type = "item"
	bin.contents_id = "overdue_guild_book"
	bin.contents_amount = 1
	bin.position = Vector2(12 * TILE_SIZE,6 * TILE_SIZE)
	treasures.add_child(bin)


func _lead_is_rogue() -> bool:
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not ("party" in game_loop) or game_loop.party.is_empty():
		return false
	var gs = get_node_or_null("/root/GameState")
	var idx: int = 0
	if gs and "party_leader_index" in gs:
		idx = clampi(gs.party_leader_index, 0, game_loop.party.size() - 1)
	var leader = game_loop.party[idx]
	if leader.job is Dictionary:
		return leader.job.get("id", "") == "rogue"
	elif leader.job is String:
		return leader.job == "rogue"
	return false
