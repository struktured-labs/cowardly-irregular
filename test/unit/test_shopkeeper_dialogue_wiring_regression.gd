extends GutTest
## 19.6 KB of authored per-village shopkeeper prose had ZERO src/ consumers until this wiring.

const ShopDialogueScript := preload("res://src/exploration/ShopDialogue.gd")
const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")

## Absolute literals, NOT read back from the JSON under test -- a typo'd key must not verify itself.
const VILLAGE_MAP_IDS := [
	"harmonia_village", "eldertree_village", "frosthold_village", "grimhollow_village",
	"ironhaven_village", "sandrift_village", "maple_heights_village", "brasston_village",
	"rivet_row_village", "node_prime_village", "vertex_village",
]
const LINE_KINDS := ["greeting", "browse", "buy", "sell", "farewell"]


func test_the_loader_is_live() -> void:
	var keys: Array = ShopDialogueScript.village_keys()
	assert_gt(keys.size(), 0, "no villages loaded -- every assert below would be vacuously true")
	assert_eq(ShopDialogueScript.village_key("harmonia_village"), "harmonia",
		"map id must normalise to the JSON's village key")


## The wiring's real failure mode: a key mismatch silently falls back to the generic lines.
func test_every_real_village_resolves_for_every_shop_type() -> void:
	var missing: Array = []
	for map_id in VILLAGE_MAP_IDS:
		for shop_type in ShopDialogueScript.SHOP_TYPE_KEYS:
			var entry: Dictionary = ShopDialogueScript.lines_for(map_id, shop_type)
			if entry.is_empty():
				missing.append(map_id + "/" + str(ShopDialogueScript.SHOP_TYPE_KEYS[shop_type]))
	assert_eq(missing, [], "village/shop pairs with no authored dialogue: " + str(missing))


func test_no_authored_village_is_unreachable_from_a_real_map_id() -> void:
	var reachable: Array = []
	for map_id in VILLAGE_MAP_IDS:
		reachable.append(ShopDialogueScript.village_key(map_id))
	var orphans: Array = []
	for key in ShopDialogueScript.village_keys():
		if not reachable.has(key):
			orphans.append(key)
	assert_eq(orphans, [], "authored villages no map id can reach: " + str(orphans))


func test_every_entry_carries_all_five_line_kinds() -> void:
	var gaps: Array = []
	for map_id in VILLAGE_MAP_IDS:
		for shop_type in ShopDialogueScript.SHOP_TYPE_KEYS:
			var entry: Dictionary = ShopDialogueScript.lines_for(map_id, shop_type)
			for kind in LINE_KINDS:
				if str(entry.get(kind, "")) == "":
					gaps.append(map_id + "/" + str(shop_type) + "/" + kind)
	assert_eq(gaps, [], "missing or blank authored lines: " + str(gaps))


## Derived from the enum, so a fifth ShopType reds instead of silently having no key.
func test_shop_type_keys_cover_every_enum_value() -> void:
	var uncovered: Array = []
	for name in ShopInteriorScript.ShopType.keys():
		var value: int = ShopInteriorScript.ShopType[name]
		if not ShopDialogueScript.SHOP_TYPE_KEYS.has(value):
			uncovered.append(str(name))
	assert_eq(uncovered, [], "ShopType values with no JSON key: " + str(uncovered))
	assert_eq(ShopDialogueScript.SHOP_TYPE_KEYS.size(), ShopInteriorScript.ShopType.size(),
		"the key table and the enum must stay the same size")


func test_two_villages_actually_differ() -> void:
	var a: Dictionary = ShopDialogueScript.lines_for("harmonia_village", 0)
	var b: Dictionary = ShopDialogueScript.lines_for("brasston_village", 0)
	assert_ne(str(a.get("greeting", "")), str(b.get("greeting", "")),
		"per-village dialogue that is identical across villages is not per-village")


func test_ambient_lines_are_speaker_prefixed_and_ordered() -> void:
	var lines: Array = ShopDialogueScript.ambient_lines("harmonia_village", 0, "Willow")
	assert_eq(lines.size(), ShopDialogueScript.AMBIENT_KINDS.size(),
		"one ambient line per AMBIENT_KIND; got " + str(lines.size()))
	for line in lines:
		assert_true(str(line).begins_with("Willow: "), "keeper lines must name the speaker: " + str(line))


func test_an_unknown_village_yields_nothing_so_the_caller_falls_back() -> void:
	assert_eq(ShopDialogueScript.lines_for("not_a_village", 0), {},
		"an unknown map id must return empty, not a partial or defaulted entry")
	assert_eq(ShopDialogueScript.ambient_lines("not_a_village", 0, "X"), [],
		"no authored lines means the caller keeps its own generic set")


## The fallback must survive: no GameLoop origin -> the shipped per-type lines, never nothing.
func test_shop_interior_still_has_dialogue_without_a_village_origin() -> void:
	var interior = ShopInteriorScript.new()
	interior.keeper_name = "Willow"
	interior.shop_type = 0
	var lines: Array = interior._keeper_dialogue()
	assert_gt(lines.size(), 0, "the keeper must always say something, authored or generic")
	interior.free()


## The load-bearing arm: without it, reverting the wiring leaves every other test green.
func test_shop_interior_prefers_the_authored_line_over_the_generic_one() -> void:
	var interior = ShopInteriorScript.new()
	interior.keeper_name = "Willow"
	interior.shop_type = 0
	var authored_lines: Array = interior._keeper_dialogue_for("brasston_village")
	var generic_lines: Array = interior._keeper_dialogue_for("")
	interior.free()
	var authored: String = str(ShopDialogueScript.lines_for("brasston_village", 0).get("greeting", ""))
	assert_ne(authored, "", "the fixture village must have an authored greeting")
	assert_gt(authored_lines.size(), 0, "keeper must speak with a known village")
	assert_true(str(authored_lines[0]).ends_with(authored),
		"must speak the AUTHORED line, not the generic one; got: " + str(authored_lines[0]))
	assert_gt(generic_lines.size(), 0, "keeper must still speak with no village origin")
	assert_false(str(generic_lines[0]).ends_with(authored),
		"with no origin the generic set must be used, not the authored one")


## The node lookup itself: absent GameLoop must degrade to "", never abort or return junk.
func test_origin_lookup_degrades_without_a_gameloop() -> void:
	var interior = ShopInteriorScript.new()
	var origin: String = interior._origin_map_id()
	interior.free()
	assert_eq(origin, "", "no GameLoop in the harness, so the origin must be empty")
