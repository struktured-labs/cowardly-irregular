extends GutTest

## Regression: OverworldNPC._resolve_archetype picks a "villager"'s sheet by hash(npc_name) % 2 over
## [young_man, young_woman], a coin flip that cannot read a name. Replaying Godot's djb2 String.hash over
## the 18 unpinned named villagers (2026-10-31) found three drawn as the other sex: Keeper Yrsa and Doreen
## ("My mother ran it. HER mother ran it.") as young men, Bram Coll as a young woman. Each is now pinned
## with sprite_archetype, which wins over the hash in BOTH _resolve_archetype (the body) and _portrait_key
## (the face), so the pair moves together and lands on an already-reviewed face/body ledger row.
## Second pass (2026-11-01): that replay only read `x.npc_name = ...` placements and missed every `_create_npc(...)`
## helper call, which is most of the game: 110 hash-picked NPCs, not 18, and the elder (old_man/old_woman) pair too.
## Ten more read against their own lines: Martha, Miner Trude ("my husband"), Clockkeeper Yara and Karen drawn as
## men; Dewey, Hermit Kael and Conspiracy Theorist Rex (their code comments say "he"), Tyler, Surplus Ray and
## Pizza Delivery Pete drawn as women. And Greta the Grey ("her stashed cave-story") drawn as an old man.
## Built through the real interior scripts, so a pin that is removed, renamed or set on the wrong variable reds.

const CASES := [
	["res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd", "Keeper Yrsa", "young_woman"],
	["res://src/maps/interiors/MapleGarageSaleInterior.gd", "Doreen", "young_woman"],
	["res://src/maps/interiors/HarmoniaChapelInterior.gd", "Bram Coll", "young_man"],
	["res://src/maps/interiors/TavernInterior.gd", "Martha", "young_woman"],
	["res://src/maps/interiors/TavernInterior.gd", "Dewey", "young_man"],
	["res://src/maps/villages/GrimhollowVillage.gd", "Miner Trude", "young_woman"],
	["res://src/maps/villages/FrostholdVillage.gd", "Clockkeeper Yara", "old_woman"],
	["res://src/maps/villages/FrostholdVillage.gd", "Hermit Kael", "young_man"],
	["res://src/maps/villages/MapleHeightsVillage.gd", "Tyler on Bike", "young_man"],
	["res://src/maps/villages/MapleHeightsVillage.gd", "Surplus Ray", "young_man"],
	["res://src/maps/villages/SandriftVillage.gd", "Conspiracy Theorist Rex", "young_man"],
	["res://src/maps/villages/HarmoniaVillage.gd", "Greta the Grey", "old_woman"],
]

## Placed by the Suburban overworld, too heavy to build here: judged at the source, on the variable that is added.
const OVERWORLD_PINS := [
	["res://src/exploration/SuburbanOverworld.gd", "karen", "Karen", "young_woman"],
	["res://src/exploration/SuburbanOverworld.gd", "pete", "Pizza Delivery Pete", "young_man"],
]


func test_each_overworld_pin_is_on_the_npc_that_is_added() -> void:
	for c in OVERWORLD_PINS:
		var src := FileAccess.get_file_as_string(c[0])
		assert_true(src.contains('var %s = _create_npc("%s"' % [c[1], c[2]]), "CONTROL: %s must still be built as `%s`" % [c[2], c[1]])
		var at := src.find('var %s = _create_npc("%s"' % [c[1], c[2]])
		var added := src.find("npcs.add_child(%s)" % c[1], at)
		var pin := src.find('%s.sprite_archetype = "%s"' % [c[1], c[3]], at)
		assert_true(pin > at and pin < added, "%s must be pinned to %s before it is added (its _ready reads the pin)" % [c[2], c[3]])


## The placed NPC named `who` in a freshly built copy of the interior, or null.
func _placed(path: String, who: String) -> Node:
	var script = load(path)
	if script == null:
		return null
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = script.new()
	if not (made is Node):
		return null
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in (made as Node).find_children("*", "Area2D", true, false):
		if str(n.get("npc_name")) == who:
			return n
	return null


func test_each_is_found_in_the_room_they_live_in() -> void:
	for c in CASES:
		var n = await _placed(c[0], c[1])
		assert_not_null(n, "CONTROL: %s must be placed by %s, or the arms below judge nobody" % [c[1], c[0].get_file()])


func test_each_walks_on_their_names_sheet() -> void:
	for c in CASES:
		var n = await _placed(c[0], c[1])
		if n == null:
			continue
		assert_eq(str(n.call("_resolve_archetype")), c[2],
			"%s walks as %s; the name says %s (the name-hash pair picked the other sex)" % [c[1], n.call("_resolve_archetype"), c[2]])


func test_each_speaks_with_the_matching_face() -> void:
	for c in CASES:
		var n = await _placed(c[0], c[1])
		if n == null:
			continue
		assert_eq(str(n.call("_portrait_key")), c[2],
			"%s's dialogue face is %s, not the %s their body now is" % [c[1], n.call("_portrait_key"), c[2]])
