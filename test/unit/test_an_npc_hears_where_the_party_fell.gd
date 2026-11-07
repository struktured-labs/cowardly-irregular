extends GutTest

## A party wipe is logged as "Party wiped in " + its map id capitalized, so an NPC heard "Steampunk Overworld" where the map,
## the save slot and the area banner all say "Cogsworth Junction" (41 of 41 locations.json entries differed on 2026-11-07).
## The recent-events block now names the place as SaveSystem.location_display_name does; old saves' logged wipes read the same.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _wipe(map_id: String) -> Dictionary:
	return {"type": EventLog.TYPE_PARTY_WIPE, "summary": "Party wiped in %s" % map_id.replace("_", " ").capitalize(),
		"data": {"map_id": map_id, "survivors": 0, "party_size": 4}}


## A map whose display name its capitalized id does not spell; derived from the data.
func _renamed_map() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/locations.json"))
	if not (parsed is Dictionary):
		return ""
	for key in parsed:
		var e: Variant = parsed[key]
		if e is Dictionary:
			var mid: String = str((e as Dictionary).get("map_id", key))
			if SaveSystem.location_display_name(mid) != mid.replace("_", " ").capitalize():
				return mid
	return ""


func test_an_npc_hears_the_place_by_its_name() -> void:
	var mid: String = _renamed_map()
	assert_ne(mid, "", "CONTROL: a location whose name its id does not spell exists")
	if mid == "":
		return
	var shown: String = SaveSystem.location_display_name(mid)
	var p: String = DP.build_npc_opening("Theron", "an elder", "Harmonia", [_wipe(mid)])
	assert_string_contains(p, "Party wiped in %s" % shown, "the NPC hears where the party fell as the player reads it")
	assert_false(p.contains(mid.replace("_", " ").capitalize()), "THE DEFECT: the NPC heard the map's id dressed as a name")


func test_a_wipe_with_no_map_and_other_events_are_untouched() -> void:
	var bare: Dictionary = {"type": EventLog.TYPE_PARTY_WIPE, "summary": "Party wiped in the dark", "data": {}}
	var p: String = DP.build_npc_opening("Theron", "an elder", "Harmonia", [bare, {"type": "battle", "summary": "The Rat King fell"}])
	assert_string_contains(p, "Party wiped in the dark", "a wipe that names no map keeps its own summary")
	assert_string_contains(p, "The Rat King fell", "an ordinary event keeps its summary")
