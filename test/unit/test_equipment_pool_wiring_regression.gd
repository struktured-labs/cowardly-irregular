extends GutTest

## Equipment pool wiring + persistence.
##
## TWO bugs that were masking each other:
##  1. OverworldMenu called EquipmentMenu.setup(target) with NO lists, so the
##     "nothing supplied" backfill offered the ENTIRE catalog — every item in
##     the game equippable without ever being bought (measured: 21/21 weapons,
##     12/12 armors, 12/12 accessories).
##  2. GameLoop.equipment_pool — fed by shop purchases, treasure chests AND
##     battle drops — was never serialized, so every earned drop vanished on
##     reload. Invisible because (1) handed you everything anyway.
##
## Tests drive the REAL paths (the actual call site, a real JSON round-trip)
## rather than shapes chosen here — per the 2026-07-25 lesson that a test
## supplying its own assumed values can be green against a dead feature.

const OVERWORLD_MENU := "res://src/ui/OverworldMenu.gd"
const EQUIP_MENU := "res://src/ui/EquipmentMenu.gd"
const SHOP := "res://src/exploration/ShopScene.gd"

var _saved_pool: Dictionary = {}


func before_each() -> void:
	_saved_pool = GameState.equipment_pool.duplicate(true)


func after_each() -> void:
	GameState.equipment_pool = _saved_pool.duplicate(true)


func _menu() -> Object:
	var m = load(EQUIP_MENU).new()
	add_child_autofree(m)
	return m


# ---------------------------------------------------------------- consumer

## THE regression. An owned-nothing pool must offer nothing — this is the
## exact case the old empty-means-unsupplied backfill turned into "offer
## every item in the game".
func test_empty_pool_offers_nothing_rather_than_the_whole_catalog() -> void:
	var m = _menu()
	m.setup(null, [], [], [])
	assert_eq(m.available_weapons.size(), 0,
		"owning no weapons must offer no weapons — [] is a real answer, not 'no list supplied'")
	assert_eq(m.available_armors.size(), 0, "same for armor")
	assert_eq(m.available_accessories.size(), 0, "same for accessories")
	assert_lt(m.available_weapons.size(), EquipmentSystem.weapons.size(),
		"the catalog must not leak back in through the fallback")


func test_menu_offers_exactly_the_pool_it_is_given() -> void:
	var owned: String = EquipmentSystem.weapons.keys()[0]
	var m = _menu()
	m.setup(null, [owned], [], [])
	assert_eq(m.available_weapons, [owned],
		"the menu offers precisely what the party owns, no more")


## Omitting the lists still yields the catalog, so any caller that genuinely
## wants "everything" (and every pre-existing test) keeps working.
func test_omitted_lists_still_fall_back_to_the_catalog() -> void:
	var m = _menu()
	m.setup(null)
	assert_eq(m.available_weapons.size(), EquipmentSystem.weapons.size(),
		"an OMITTED list still means 'no restriction' — only an empty list means 'you own none'")


## The bug was never in setup(); it was in the caller passing nothing. Assert
## the real call site supplies the pool.
func test_overworld_menu_passes_the_pool_to_setup() -> void:
	var src := FileAccess.get_file_as_string(OVERWORLD_MENU)
	assert_true(src.contains("equip_menu.setup(target, pool[\"weapons\"], pool[\"armors\"], pool[\"accessories\"])"),
		"the equip menu must be given the party's gear — passing only `target` is what offered the whole catalog")
	assert_false(src.contains("equip_menu.setup(target)\n"),
		"the bare setup(target) call must not return")
	assert_true(src.contains("func _shared_equipment_pool"), "pool accessor exists")


func test_shared_pool_accessor_reads_gameloop_and_survives_its_absence() -> void:
	var om = load(OVERWORLD_MENU).new()
	add_child_autofree(om)
	var pool: Dictionary = om._shared_equipment_pool()
	for slot_key in ["weapons", "armors", "accessories"]:
		assert_true(pool.has(slot_key), "pool always reports every slot: %s" % slot_key)
		assert_true(pool[slot_key] is Array, "%s is an Array even with no GameLoop" % slot_key)


# ------------------------------------------------------------ persistence

## Drives a REAL JSON round-trip, because JSON.parse is what returns generic
## Arrays — the documented silent-failure class. A dict handed straight back
## would never exercise it.
func test_pool_survives_a_real_json_save_round_trip() -> void:
	var w: String = EquipmentSystem.weapons.keys()[0]
	var a: String = EquipmentSystem.armors.keys()[0]
	var x: String = EquipmentSystem.accessories.keys()[0]
	GameState.equipment_pool = {"weapons": [w, w], "armors": [a], "accessories": [x]}

	var round_tripped: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	assert_true(round_tripped is Dictionary, "save data survives JSON")

	GameState.equipment_pool = {"weapons": [], "armors": [], "accessories": []}
	GameState.from_dict(round_tripped)

	assert_eq(GameState.equipment_pool["weapons"], [w, w],
		"weapons survive save->load, duplicates included — a silent [] here is the player losing every drop")
	assert_eq(GameState.equipment_pool["armors"], [a], "armor survives")
	assert_eq(GameState.equipment_pool["accessories"], [x], "accessories survive")


func test_pool_entries_come_back_as_strings_not_variants() -> void:
	GameState.equipment_pool = {"weapons": ["iron_sword"], "armors": [], "accessories": []}
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.from_dict(round_tripped)
	assert_true(GameState.equipment_pool["weapons"][0] is String,
		"entries coerce to String on load, per the typed-array roundtrip class")


func test_malformed_pool_does_not_wipe_the_slot_silently() -> void:
	GameState.equipment_pool = {"weapons": ["iron_sword"], "armors": [], "accessories": []}
	GameState.from_dict({"equipment_pool": "not a dictionary"})
	assert_eq(GameState.equipment_pool["weapons"], ["iron_sword"],
		"a malformed pool keeps what the player had rather than blanking it")


func test_new_game_clears_the_pool() -> void:
	GameState.equipment_pool = {"weapons": ["iron_sword"], "armors": [], "accessories": []}
	GameState.reset_game_state()
	assert_eq(GameState.equipment_pool["weapons"].size(), 0,
		"a New Game must not inherit last run's gear — same leak class as quests/crystals")


# --------------------------------------------------------------- producers

## All three acquisition paths must land in the SAME store the menu reads.
## Any producer writing elsewhere is gear the player can never equip.
func test_all_three_producers_target_the_shared_pool() -> void:
	var shop := FileAccess.get_file_as_string(SHOP)
	var chest := FileAccess.get_file_as_string("res://src/exploration/TreasureChest.gd")
	var battle := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(shop.contains("equipment_pool"), "shop purchases land in the shared pool")
	assert_true(chest.contains("equipment_pool"), "chest drops land in the shared pool")
	assert_true(battle.contains("equipment_pool"), "battle drops land in the shared pool")


## The orphan: 2 writes, 0 reads. Gear written there was unreachable.
## Targets the WRITE, not the word — a comment naming what was removed is
## worth keeping, and a check that forbids mentioning it would be noise.
func test_orphaned_equipment_inventory_write_is_gone() -> void:
	var shop := FileAccess.get_file_as_string(SHOP)
	assert_false(shop.contains("party_leader[\"equipment_inventory\"] = []"),
		"the second store had no readers — two stores for one concept is how they drift apart")
	assert_false(shop.contains("party_leader[\"equipment_inventory\"].append"),
		"and nothing appends to it")


## GameLoop must push the live pool into the save bucket and read it back.
func test_gameloop_syncs_the_pool_both_directions() -> void:
	var gl := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(gl.contains("GameState.equipment_pool = equipment_pool.duplicate(true)"),
		"live pool pushes into the save bucket on sync — without this nothing is ever written")
	assert_true(gl.contains("func _restore_equipment_pool_from_game_state"),
		"and is rehydrated on load — a write-only bucket loses the gear just as thoroughly")
	assert_true(gl.contains("_restore_equipment_pool_from_game_state()"),
		"the restore is actually CALLED, not merely defined")
