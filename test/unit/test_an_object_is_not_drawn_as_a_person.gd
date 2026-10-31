extends GutTest

## An object that speaks (a clock, a ledger, a map) was placed as an OverworldNPC with npc_type "villager"
## or "scholar", so it stood in its room as a person: the villager coin flip or the scholar sheet, with a face
## in its dialogue box (cowir-sprites 20506, sized by cowir-adhoc 20508 and cowir-overworld 20512). These
## five rooms already DRAW the object, so the fix is no person at all: OverworldNPC.is_object draws nothing,
## resolves no archetype and hides the portrait, while the interaction, quest wiring and dialogue stay.
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


func test_a_person_still_draws_one() -> void:
	# CONTROL for the arm above: a real villager in the same room keeps its sheet, so the empty texture is the
	# flag at work and not a room that draws nobody.
	var n = await _placed("res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd", "Keeper Yrsa")
	assert_not_null(n, "CONTROL: Keeper Yrsa must be placed beside the clock")
	if n != null:
		var spr = n.get("sprite")
		assert_true(spr is Sprite2D and (spr as Sprite2D).texture != null, "a person in the same room must still be drawn")
