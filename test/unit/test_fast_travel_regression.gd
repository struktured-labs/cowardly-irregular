extends GutTest

## Fast travel (2026-07-01, old queue item 4): crystal attunement +
## gold-scaled warp between attuned crystals.
##
## Pins: attunement registry round-trips through save data, tier lookup
## covers every TeleportMenu destination, cost scales with tier distance,
## and the menu lists only attuned crystals (excluding the current map).

const FastTravelMenuScript := preload("res://src/ui/FastTravelMenu.gd")


func after_each() -> void:
	GameState.activated_crystals.clear()


func test_activation_registry_round_trips_through_save() -> void:
	GameState.activate_crystal("harmonia_village")
	GameState.activate_crystal("brasston_village")
	var data: Dictionary = GameState._create_save_data()
	assert_true(data.has("activated_crystals"))
	GameState.activated_crystals.clear()
	GameState._apply_save_data(data)
	assert_true(GameState.is_crystal_activated("harmonia_village"))
	assert_true(GameState.is_crystal_activated("brasston_village"))
	assert_false(GameState.is_crystal_activated("vertex_village"))


func test_activate_ignores_empty_id() -> void:
	GameState.activate_crystal("")
	assert_eq(GameState.activated_crystals.size(), 0,
		"empty map_id (GameLoop unavailable) must not pollute the registry")


func test_every_teleport_destination_has_a_world_tier() -> void:
	# Cost scaling depends on prefix-matching the map_id — an unmatched id
	# silently falls to tier 1 and undercharges cross-world warps. Pin that
	# every real destination resolves through the prefix table.
	for dest in TeleportMenu.DESTINATIONS:
		var id: String = dest["id"]
		var matched := false
		for prefix in FastTravelMenuScript.WORLD_TIERS:
			if id.begins_with(prefix):
				matched = true
				break
		assert_true(matched, "WORLD_TIERS must prefix-match %s" % id)


func test_travel_cost_scales_with_tier_distance() -> void:
	assert_eq(FastTravelMenuScript.travel_cost("harmonia_village", "whispering_cave"), 50,
		"same world = base cost")
	assert_eq(FastTravelMenuScript.travel_cost("harmonia_village", "suburban_overworld"), 150,
		"1 tier apart = base + 100")
	assert_eq(FastTravelMenuScript.travel_cost("harmonia_village", "abstract_overworld"), 550,
		"5 tiers apart = base + 500")
	assert_eq(
		FastTravelMenuScript.travel_cost("abstract_overworld", "harmonia_village"),
		FastTravelMenuScript.travel_cost("harmonia_village", "abstract_overworld"),
		"cost is symmetric")


func test_menu_lists_only_attuned_crystals_excluding_current() -> void:
	GameState.activate_crystal("harmonia_village")
	GameState.activate_crystal("brasston_village")
	GameState.activate_crystal("vertex_village")
	var menu = FastTravelMenuScript.new()
	menu.current_map_id = "harmonia_village"
	menu._collect_rows()
	var ids: Array = []
	for row in menu._rows:
		ids.append(row["id"])
	assert_does_not_have(ids, "harmonia_village", "current location excluded")
	assert_has(ids, "brasston_village")
	assert_has(ids, "vertex_village")
	assert_eq(ids.size(), 2)
	menu.free()


func test_menu_rows_sorted_cheapest_first() -> void:
	GameState.activate_crystal("vertex_village")
	GameState.activate_crystal("whispering_cave")
	var menu = FastTravelMenuScript.new()
	menu.current_map_id = "harmonia_village"
	menu._collect_rows()
	assert_eq(menu._rows[0]["id"], "whispering_cave",
		"same-world crystal (50g) sorts before W6 crystal (550g)")
	menu.free()
