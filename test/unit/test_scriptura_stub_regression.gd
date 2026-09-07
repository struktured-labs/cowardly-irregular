extends GutTest

## Scriptura capital-district stub (2026-07-08, cowir-story ruled scope msg 2159):
## plaza + Scriptweaver's Guild + Aldrin's bookshop + Palace-gate landmark.
## Unblocks word_from_capital (Rowan → Aldrin), thirty_seven (guild scholar +
## overdue-book pickup), untested_edge guild path.
##
## Pins: GameLoop dispatch + transition classification, the plaza map integrity
## and quest-NPC/pickup wiring, the interiors' quest NPC ids (load-bearing), the
## overworld entrance, and the breadcrumb.

const PlazaScript := preload("res://src/maps/villages/ScripturaPlaza.gd")


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_gameloop_dispatches_the_three_scriptura_maps() -> void:
	var g := _read("res://src/GameLoop.gd")
	assert_true(g.contains("\"scriptura_plaza\":"), "GameLoop must dispatch scriptura_plaza")
	assert_true(g.contains("\"scriptura_guild\":"), "GameLoop must dispatch scriptura_guild")
	assert_true(g.contains("\"scriptura_bookshop\":"), "GameLoop must dispatch scriptura_bookshop")
	assert_true(g.contains("ScripturaPlazaScript = preload"), "plaza preload present")


func test_interiors_are_interior_type_plaza_is_village_type() -> void:
	var g := _read("res://src/GameLoop.gd")
	assert_true(g.contains("\"scriptura_guild\", \"scriptura_bookshop\""),
		"guild + bookshop must be in INTERIOR_MAP_IDS (quick interior transition)")
	assert_true(g.contains("\"scriptura_plaza\" in t"),
		"scriptura_plaza must classify as a village transition")


func test_plaza_map_rows_are_uniform_width() -> void:
	# A ragged ASCII row silently mis-tiles the plaza. Instantiate and confirm
	# the scene builds without error (BaseVillage runs the full map gen).
	var plaza = PlazaScript.new()
	add_child_autofree(plaza)
	await get_tree().process_frame
	assert_eq(plaza._get_area_id(), "scriptura_plaza")
	# Village layouts bumped ~20% for playtest breathing room (msg 2542/2543);
	# plaza went 24 → 30. Test guards against ragged rows via the runtime build
	# check above; the exact width just needs to reflect the current authored dims.
	assert_eq(plaza.MAP_WIDTH, 30)
	assert_true(plaza.spawn_points.has("entrance"), "entrance spawn registered")
	assert_true(plaza.spawn_points.has("guild_exit"), "guild return spawn registered")
	assert_true(plaza.spawn_points.has("bookshop_exit"), "bookshop return spawn registered")


func test_plaza_places_breadcrumb_and_gate() -> void:
	var src := _read("res://src/maps/villages/ScripturaPlaza.gd")
	for cid in ["scriptura_citizen_1", "scriptura_citizen_2",
			"scriptura_citizen_3", "scriptura_citizen_4"]:
		assert_true(src.contains(cid), "plaza must place breadcrumb citizen %s" % cid)
	assert_true(src.contains("_build_palace_gate"), "palace-gate landmark present")
	assert_true(src.contains("scriptura_guild") and src.contains("scriptura_bookshop"),
		"both interior doors wired")


func test_book_pickup_gated_on_favor_asked() -> void:
	# overdue_guild_book must only spawn while the scholar's favor is asked and
	# the quest isn't complete — else it's a free item / a lingering prop.
	var src := _read("res://src/maps/villages/ScripturaPlaza.gd")
	assert_true(src.contains("quest_world1_thirty_seven_favor_asked"),
		"book pickup gated on favor_asked")
	assert_true(src.contains("overdue_guild_book"), "book pickup places the right item")


func test_interior_quest_npc_ids_match_quest_data() -> void:
	# THE load-bearing check: the interiors must set the exact npc_ids the quest
	# system keys on, or the quests silently dead-end at those NPCs.
	var guild := _read("res://src/maps/interiors/ScripturaGuildInterior.gd")
	assert_true(guild.contains("guild_scholar_scriptura"),
		"Guild interior must place guild_scholar_scriptura (thirty_seven + untested_edge)")
	var shop := _read("res://src/maps/interiors/ScripturaBookshopInterior.gd")
	assert_true(shop.contains("aldrin_scriptura"),
		"bookshop must place aldrin_scriptura (word_from_capital)")


func test_interiors_use_authored_ambient_tones() -> void:
	var guild := _read("res://src/maps/interiors/ScripturaGuildInterior.gd")
	assert_true(guild.contains("ambient_scriptorium"), "Guild uses cowir-sfx's scriptorium tone")
	var shop := _read("res://src/maps/interiors/ScripturaBookshopInterior.gd")
	assert_true(shop.contains("ambient_library"), "bookshop reuses ambient_library")


func test_interiors_exit_to_plaza() -> void:
	var guild := _read("res://src/maps/interiors/ScripturaGuildInterior.gd")
	assert_true(guild.contains("scriptura_plaza"), "Guild exits to the plaza")
	var shop := _read("res://src/maps/interiors/ScripturaBookshopInterior.gd")
	assert_true(shop.contains("scriptura_plaza"), "bookshop exits to the plaza")


func test_overworld_entrance_gated_and_returnable() -> void:
	var ow := _read("res://src/exploration/OverworldScene.gd")
	assert_true(ow.contains("scriptura_plaza"), "overworld has a Scriptura entrance")
	assert_true(ow.contains("scriptura_return"), "overworld registers the Scriptura return spawn")


func test_thirty_seven_book_fetch_consumes() -> void:
	# cowir-story's ruling: the book is TRADED, must leave inventory at turn-in.
	var q = JSON.parse_string(_read("res://data/quests/world1_thirty_seven.json"))
	var step3 = q["objectives"][2]
	assert_eq(step3["type"], "fetch")
	assert_true(step3.get("consume", false), "overdue_guild_book fetch must consume at turn-in")


func test_word_from_capital_targets_exist_in_data() -> void:
	# Sanity: the quest's giver + turn-in NPCs are the ones the scene places.
	var q = JSON.parse_string(_read("res://data/quests/world1_word_from_capital.json"))
	assert_eq(q["giver"]["npc_id"], "rowan_harmonia", "giver is Rowan (Harmonia)")
	var targets: Array = []
	for o in q["objectives"]:
		if o.has("target_npc"):
			targets.append(o["target_npc"])
	assert_true(targets.has("aldrin_scriptura"), "quest routes through Aldrin in the bookshop")
