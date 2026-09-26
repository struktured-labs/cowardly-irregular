extends GutTest

## New Game stamps a nature on each starter (Fighter Brave, Mage Scholarly).
## The Dancing Tonberry piano plays only for Brave or Scholarly.
## That nature lived on the Combatant and never entered the save file, so
## Continue handed back the same party unable to play.

const SLOT := 97


func before_each() -> void:
	_delete_slot()


func after_each() -> void:
	_delete_slot()


func _delete_slot() -> void:
	var path := SaveSystem._get_save_path(SLOT)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Same gate as TavernInterior._check_can_play_piano. The interior itself is not
## constructed here — its _ready builds the piano, which is the #224 hang.
func _piano_allows(member: Combatant) -> bool:
	if member.customization == null:
		return false
	var nature = member.customization.personality
	return nature == CharacterCustomization.Personality.SCHOLARLY \
			or nature == CharacterCustomization.Personality.BRAVE


func _round_trip(member_dict: Dictionary) -> Combatant:
	var save := {
		"party": [member_dict],
		"game_state": {"player_party": [member_dict]},
	}
	assert_true(SaveSystem._write_save_file(SLOT, save), "save file must be written")
	var loaded: Dictionary = SaveSystem._read_save_file(SLOT)
	var party: Variant = (loaded.get("game_state", {}) as Dictionary).get("player_party", [])
	assert_true(party is Array and (party as Array).size() == 1, "the save must carry the party member")
	var restored := Combatant.new()
	restored.from_dict((party as Array)[0])
	return restored


func test_a_chosen_nature_survives_the_save_file() -> void:
	var member := Combatant.new()
	member.combatant_name = "Lute"
	var look := CharacterCustomization.new("Lute")
	look.personality = CharacterCustomization.Personality.SCHOLARLY
	look.hair_color = Color(0.11, 0.22, 0.33)
	look.hair_style = CharacterCustomization.HairStyle.MOHAWK
	member.customization = look
	assert_true(_piano_allows(member), "CONTROL: a Scholarly member can play before the save")

	var restored := _round_trip(member.to_dict())
	assert_not_null(restored.customization, "Continue dropped the nature, so the tavern piano refuses the party")
	assert_eq(restored.customization.personality, CharacterCustomization.Personality.SCHOLARLY,
			"the saved nature must still be Scholarly")
	assert_true(_piano_allows(restored), "the tavern piano must still accept this member after load")
	assert_almost_eq(restored.customization.hair_color.r, 0.11, 0.001, "hair color must survive the file")
	assert_eq(restored.customization.hair_style, CharacterCustomization.HairStyle.MOHAWK,
			"hair style must survive the file")
	member.queue_free()
	restored.queue_free()


func test_an_old_save_keeps_the_starter_natures() -> void:
	var mage := Combatant.new()
	mage.combatant_name = "Mage"
	var mage_dict: Dictionary = mage.to_dict()
	mage_dict.erase("customization")
	var restored_mage := _round_trip(mage_dict)
	assert_not_null(restored_mage.customization, "a pre-fix save of the Mage came back with no nature")
	assert_eq(restored_mage.customization.personality, CharacterCustomization.Personality.SCHOLARLY,
			"the starter Mage is Scholarly — that is who can play the piano")
	assert_true(_piano_allows(restored_mage), "the starter Mage must still be allowed to play after Continue")

	var cleric := Combatant.new()
	cleric.combatant_name = "Cleric"
	var cleric_dict: Dictionary = cleric.to_dict()
	cleric_dict.erase("customization")
	var cleric_save := {
		"party": [cleric_dict],
		"game_state": {"player_party": [cleric_dict]},
	}
	assert_true(SaveSystem._write_save_file(SLOT, cleric_save), "cleric save must be written")
	var loaded: Dictionary = SaveSystem._read_save_file(SLOT)
	var party: Array = (loaded["game_state"] as Dictionary)["player_party"]
	var restored_cleric := Combatant.new()
	restored_cleric.from_dict(party[0])
	assert_eq(restored_cleric.customization.personality, CharacterCustomization.Personality.CAUTIOUS,
			"the starter Cleric is Cautious, not a second Scholar")
	assert_false(_piano_allows(restored_cleric), "Cautious is the fail-line nature, not a piano nature")

	var stranger := Combatant.new()
	stranger.from_dict({"name": "Slime"})
	assert_null(stranger.customization, "only the five starters get a nature when the file omitted one")

	mage.queue_free()
	restored_mage.queue_free()
	cleric.queue_free()
	restored_cleric.queue_free()
	stranger.queue_free()
