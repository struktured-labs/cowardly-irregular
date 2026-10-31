extends GutTest

## An object that speaks (a clock, a ledger, a map) was placed as an OverworldNPC with npc_type "villager"
## or "scholar", so it stood in its room as a person: the villager coin flip or the scholar sheet, with a face
## in its dialogue box (cowir-sprites 20506, sized by cowir-adhoc 20508 and cowir-overworld 20512). These
## five rooms already DRAW the object, so the fix is no person at all: OverworldNPC.is_object draws nothing,
## resolves no archetype and hides the portrait, while the interaction, quest wiring and dialogue stay.
## Part 2: where the room draws NOTHING, the object shows its own T1 sprite (object_art, tools/gen_object_props.py):
## the Cache Register, Incident Board, Shelf 7, Graffiti Wall and Potted Plant, and The Dog shows a dog.
## Judged on what RENDERS on the map (the sprite's texture, the resolved sheet), not on the flag's spelling.
## The hidden dialogue face rides the same flag (hide_portrait) and is not driven here: it needs a live dialogue.

const CASES := [
	["res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd", "The Meltwater Clock"],
	["res://src/maps/interiors/GrimhollowLanternDebtInterior.gd", "The Debt Book"],
	["res://src/maps/interiors/HarmoniaCartographerInterior.gd", "The Living Map"],
	["res://src/maps/interiors/IronhavenStrikeRegistryInterior.gd", "The Ledger"],
	["res://src/maps/interiors/SandriftRainLedgerInterior.gd", "The Rain Ledger"],
]


## The placed node named `who` in a freshly built copy of the interior, or null.
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


func test_each_object_is_still_placed_and_interactable() -> void:
	for c in CASES:
		var n = await _placed(c[0], c[1])
		assert_not_null(n, "CONTROL: %s must still be placed by %s, or the arms below judge nothing" % [c[1], c[0].get_file()])
		if n != null:
			assert_true(bool(n.get("interactable")), "%s must still be interactable: hiding the person must not hide the object" % c[1])


func test_no_object_draws_a_person() -> void:
	for c in CASES:
		var n = await _placed(c[0], c[1])
		if n == null:
			continue
		var spr = n.get("sprite")
		assert_true(spr is Sprite2D, "CONTROL: %s's sprite node must exist (code elsewhere reaches it)" % c[1])
		if spr is Sprite2D:
			assert_null((spr as Sprite2D).texture, "%s draws a texture: an object must not stand in its room as a person" % c[1])
		assert_eq(str(n.call("_resolve_archetype")), "", "%s resolves the '%s' person sheet" % [c[1], n.call("_resolve_archetype")])


## Objects in rooms that draw nothing for them: each shows its own art, exactly.
const ART_CASES := [
	["res://src/maps/interiors/NodePrimeCacheInterior.gd", "The Cache Register", "res://assets/sprites/objects/cache_register.png"],
	["res://src/maps/interiors/RivetRowIncidentBoardInterior.gd", "The Incident Board", "res://assets/sprites/objects/incident_board.png"],
	["res://src/maps/interiors/BrasstonRedundancyArchiveInterior.gd", "Shelf 7", "res://assets/sprites/objects/shelf_7.png"],
]


func test_an_object_the_room_does_not_draw_shows_its_own_art() -> void:
	for c in ART_CASES:
		var n = await _placed(c[0], c[1])
		assert_not_null(n, "CONTROL: %s must be placed by %s" % [c[1], c[0].get_file()])
		if n == null:
			continue
		var spr = n.get("sprite")
		var tex: Texture2D = (spr as Sprite2D).texture if spr is Sprite2D else null
		assert_not_null(tex, "%s draws nothing, but its room draws nothing for it either: it would be invisible" % c[1])
		if tex != null:
			assert_eq(tex.resource_path, c[2], "%s must draw its own art" % c[1])
		assert_eq(str(n.call("_resolve_archetype")), "", "%s must still resolve no person sheet" % c[1])


func test_every_object_art_path_in_src_exists() -> void:
	# The outdoor objects (Graffiti Wall, Potted Plant, The Dog) are placed by village/overworld scripts too heavy to
	# build here, so their art is judged at the source: every object_art the code names must exist on disk.
	var seen := 0
	var missing: Array = []
	var re := RegEx.new()
	re.compile('object_art = "(res://[^"]+)"')
	for dir in ["res://src/maps/interiors", "res://src/maps/villages", "res://src/exploration"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			for m in re.search_all(FileAccess.get_file_as_string(dir + "/" + f)):
				seen += 1
				if not FileAccess.file_exists(m.get_string(1)):
					missing.append("%s -> %s" % [f, m.get_string(1)])
	assert_gte(seen, 6, "FLOOR: the six object_art placements must be found, or this judged nothing (%d)" % seen)
	assert_eq(missing, [], "object_art names a file that is not there, so the object would draw nothing: %s" % [missing])


func test_object_art_is_what_draws() -> void:
	# CONTROL for the mechanism, both directions, on a bare NPC: with art it draws that art, without art nothing.
	var NPC = load("res://src/exploration/OverworldNPC.gd")
	var with_art = NPC.new()
	with_art.npc_name = "probe with art"
	with_art.is_object = true
	with_art.object_art = "res://assets/sprites/objects/dog.png"
	add_child_autofree(with_art)
	var bare = NPC.new()
	bare.npc_name = "probe bare"
	bare.is_object = true
	add_child_autofree(bare)
	await get_tree().process_frame
	var t1: Texture2D = (with_art.get("sprite") as Sprite2D).texture
	assert_not_null(t1, "an object with object_art must draw it")
	if t1 != null:
		assert_eq(t1.resource_path, "res://assets/sprites/objects/dog.png", "it must draw exactly the named art")
	assert_null((bare.get("sprite") as Sprite2D).texture, "an object with no art must draw nothing")


func test_a_person_still_draws_one() -> void:
	# CONTROL for the arm above: a real villager in the same room keeps its sheet, so the empty texture is the
	# flag at work and not a room that draws nobody.
	var n = await _placed("res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd", "Keeper Yrsa")
	assert_not_null(n, "CONTROL: Keeper Yrsa must be placed beside the clock")
	if n != null:
		var spr = n.get("sprite")
		assert_true(spr is Sprite2D and (spr as Sprite2D).texture != null, "a person in the same room must still be drawn")
