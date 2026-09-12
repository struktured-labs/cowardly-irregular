extends GutTest

## Walk into the shop in Node Prime and the music becomes a harp.
##
## Every village in every world carries VillageShops, and all six routed through one bed:
## `interior_shop` — "The Merchant's Welcome", cozy piano/harp/flute, written for a medieval
## market. Measured before the fix, one village at a time:
##
##     W5 Node Prime   village = village_node_prime.ogg   inn = village_node_prime.ogg
##                     tavern  = village_node_prime.ogg   SHOP = shop.ogg
##
## The room's two siblings were already right, which is what makes this a defect rather than a
## taste question: `interior_inn` and `interior_tavern` have no bed, so they inherit the world's
## village bed and the walk stays continuous. Only the shop had a bed, so it never inherited —
## and the bed it had belongs to another world.
##
## 🔑 The fix is a bed declaring the worlds it was written for, not a rule about shops.
## `_resolve_interior_track` already prefers `interior_shop_<suffix>`; the new `worlds` field
## says what the BASE key means when no variant exists. Opt-in and absent everywhere else, so
## every other bed resolves exactly as before, and an authored `interior_shop_digital` still
## wins without touching this.
##
## ⛔ NOT "non-medieval worlds get silence": the room inherits, the same path an unauthored
## room takes. A shop in W2-W6 keeps the village bed playing without a restart.

const MANIFEST := "res://data/music_manifest.json"

## Each world's village area key, so the walk starts where a player's would.
const VILLAGE_BY_WORLD := {
	1: "village", 2: "maple_heights_village", 3: "brasston_village",
	4: "rivet_row_village", 5: "node_prime_village", 6: "vertex_village",
}

var _world_before: int = 1


func before_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		_world_before = int(gs.get("current_world"))


func after_each() -> void:
	SoundManager.stop_music()
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		gs.set("current_world", _world_before)


func _bed() -> String:
	var s: AudioStream = SoundManager._music_player.stream if SoundManager._music_player else null
	return s.resource_path.get_file() if s != null else "<none>"


func _enter(world: int, room: String) -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	gs.set("current_world", world)
	SoundManager.stop_music()
	SoundManager.play_area_music(str(VILLAGE_BY_WORLD[world]))
	for i in range(3):
		await get_tree().process_frame
	var village_bed: String = _bed()
	assert_ne(village_bed, "<none>", "CONTROL: W%d's village bed is playing before the door" % world)
	SoundManager.play_area_music(room)
	for i in range(3):
		await get_tree().process_frame
	return "%s|%s" % [village_bed, _bed()]


func test_the_shop_keeps_its_world_outside_the_one_it_was_written_for() -> void:
	for world in [2, 3, 4, 5, 6]:
		var pair: String = await _enter(world, "interior_shop")
		var village_bed: String = pair.split("|")[0]
		var shop_bed: String = pair.split("|")[1]
		assert_eq(shop_bed, village_bed,
			"W%d's shop must keep the village bed, not play %s — that bed names medieval" % [world, shop_bed])


func test_control_the_shop_still_has_its_own_bed_where_it_belongs() -> void:
	var pair: String = await _enter(1, "interior_shop")
	assert_eq(pair.split("|")[1], "shop.ogg",
		"CONTROL: W1 still gets The Merchant's Welcome — otherwise the arm above proves nothing but silence")


func test_the_shop_now_behaves_like_its_two_siblings() -> void:
	## inn and tavern were already inheriting; the defect was that one room of the three disagreed.
	for room in ["interior_inn", "interior_tavern"]:
		var pair: String = await _enter(5, room)
		assert_eq(pair.split("|")[1], pair.split("|")[0],
			"CONTROL: %s already inherits W5's village bed — the shop had to match it, not the reverse" % room)


func test_the_field_is_opt_in_and_only_the_shop_declares_one() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: manifest carries %d tracks" % tracks.size())
	var declaring: Array[String] = []
	for k in tracks.keys():
		if (tracks[k] as Dictionary).has("worlds"):
			declaring.append(str(k))
	declaring.sort()
	assert_eq(declaring, ["interior_shop"] as Array[String],
		"only interior_shop declares a world today; a new entry here narrows where that bed plays, which is a routing change and belongs in its own guard")
	assert_eq(tracks["interior_shop"]["worlds"], ["medieval"],
		"the shop bed names the world it was written for")


func test_a_bed_that_names_no_world_still_serves_every_one() -> void:
	## The opt-in default has no second subject in the corpus — interior_shop is the only base
	## interior bed — so the arms above cannot tell "absent field" from "empty list refuses
	## everything". Ask the helper directly, with the world established the way a door does:
	## it reads the resolver, and the resolver does not read GameState from a standing start.
	SoundManager._load_music_manifest()
	var gs: Node = get_node_or_null("/root/GameState")
	gs.set("current_world", 5)
	SoundManager.play_area_music(str(VILLAGE_BY_WORLD[5]))
	for i in range(3):
		await get_tree().process_frame
	assert_eq(SoundManager._get_current_world_suffix(), "digital", "CONTROL: the resolver is standing in W5")
	assert_true(SoundManager._bed_serves_this_world("village_harmonia"),
		"a bed with no worlds field serves every world — W1's village bed must not be refused in W5")
	assert_true(SoundManager._bed_serves_this_world("zzz_not_a_bed_at_all"),
		"a key with no entry carries no restriction")
	## A typo'd field must not take the music down — unreadable means unrestricted, not a crash.
	SoundManager._music_manifest["zzz_malformed_worlds"] = {"worlds": "medieval"}
	assert_true(SoundManager._bed_serves_this_world("zzz_malformed_worlds"),
		"a worlds field that is not a list must read as no restriction")
	SoundManager._music_manifest.erase("zzz_malformed_worlds")
	assert_false(SoundManager._bed_serves_this_world("interior_shop"),
		"the shop bed names medieval, so it does not serve W5")

	gs.set("current_world", 1)
	SoundManager.play_area_music(str(VILLAGE_BY_WORLD[1]))
	for i in range(3):
		await get_tree().process_frame
	assert_eq(SoundManager._get_current_world_suffix(), "medieval", "CONTROL: and now in W1")
	assert_true(SoundManager._bed_serves_this_world("interior_shop"),
		"and it does serve the world it names")
