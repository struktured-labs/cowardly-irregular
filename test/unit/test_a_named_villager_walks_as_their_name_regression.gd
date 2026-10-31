extends GutTest

## Regression: OverworldNPC._resolve_archetype picks a "villager"'s sheet by hash(npc_name) % 2 over
## [young_man, young_woman], a coin flip that cannot read a name. Replaying Godot's djb2 String.hash over
## the 18 unpinned named villagers (2026-10-31) found three drawn as the other sex: Keeper Yrsa and Doreen
## ("My mother ran it. HER mother ran it.") as young men, Bram Coll as a young woman. Each is now pinned
## with sprite_archetype, which wins over the hash in BOTH _resolve_archetype (the body) and _portrait_key
## (the face), so the pair moves together and lands on an already-reviewed face/body ledger row.
## Built through the real interior scripts, so a pin that is removed, renamed or set on the wrong variable reds.

const CASES := [
	["res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd", "Keeper Yrsa", "young_woman"],
	["res://src/maps/interiors/MapleGarageSaleInterior.gd", "Doreen", "young_woman"],
	["res://src/maps/interiors/HarmoniaChapelInterior.gd", "Bram Coll", "young_man"],
]


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
