extends GutTest

## Nine NPC roles BORROW another role's walk sheet (a knight walks as a soldier, the inn's maid as a young woman) and
## each has a portrait drawn for the role itself. The dialogue face followed the borrowed sheet, so twelve named NPCs
## spoke with someone else's face and nine portraits were never seen: Tilly the maid, Sir Corvath, Pilgrim Lael, Aldric.
## A role with its own portrait speaks with it; an explicit sprite override still decides the face (Phil's rule).

const NpcScript := preload("res://src/exploration/OverworldNPC.gd")
const Dialogue := preload("res://src/cutscene/CutsceneDialogue.gd")
const NAMED := {
	"Tilly": "maid", "Sir Corvath": "knight", "Pilgrim Lael": "pilgrim", "Aldric": "hooded_mage", "Vex": "nervous",
	"Gethena": "herbalist", "Jend": "apprentice", "Osric": "bartender", "Kael": "adventurer",
}


func _key(npc_name: String, npc_type: String, override: String = "") -> String:
	var n = NpcScript.new()
	n.npc_name = npc_name
	n.npc_type = npc_type
	n.sprite_archetype = override
	var key: String = n._portrait_key()
	n.free()
	return key


func test_a_borrowed_walk_sheet_does_not_lend_its_face() -> void:
	var wrong: Array = []
	for who in NAMED:
		var role: String = NAMED[who]
		var path := str(Dialogue.PORTRAIT_SPRITES.get(role, ""))
		assert_true(path != "" and FileAccess.file_exists(path), "CONTROL: the %s portrait is registered and on disk" % role)
		assert_ne(str(NpcScript.NPC_TYPE_TO_ARCHETYPE.get(role, role)), role, "CONTROL: a %s borrows another role's walk sheet" % role)
		var key := _key(who, role)
		if key != role:
			wrong.append("%s the %s speaks as '%s'" % [who, role, key])
	assert_eq(wrong, [], "a role with its own portrait speaks with someone else's face")


func test_the_borrowed_sheet_is_still_what_they_walk_as() -> void:
	var n = NpcScript.new()
	n.npc_name = "Tilly"
	n.npc_type = "maid"
	assert_eq(n._resolve_archetype(), "young_woman", "the sprite is untouched: only the face changes")
	n.free()


func test_an_explicit_sprite_override_still_decides_the_face() -> void:
	assert_eq(_key("Phil the Lost", "villager", "phil"), "phil", "Phil's face follows his own sheet")
	assert_eq(_key("Someone", "maid", "phil"), "phil", "an override outranks the role's portrait")


func test_a_role_with_no_portrait_of_its_own_keeps_its_sheets_face() -> void:
	assert_false(Dialogue.PORTRAIT_SPRITES.has("noble_pair"), "CONTROL: noble_pair has no portrait of its own")
	assert_true(_key("Lord Example", "noble_pair") in ["noble", "noblewoman"], "the name-hash pick is unchanged")
	assert_true(_key("Pip", "villager") in ["young_man", "young_woman"], "a plain villager is unchanged")
