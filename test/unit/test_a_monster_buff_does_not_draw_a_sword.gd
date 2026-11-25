extends GutTest

## A support ability with no cue of its own fell through to ability_physical, a sword unsheathing: 65 monster
## abilities, every Masterite buff and debuff among them. Its landing is already cued by BattleScene._on_action_executed
## (buff / debuff / status_<effect>), so the cast is now silent instead of a weapon over a chime.

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const SWORD := "ability_physical"


var _saved_area: String = ""
var _saved_suffix: String = ""


## Pinned to World 1: a world leaked by an earlier test sends play_ability to a w6_ variant first.
func before_each() -> void:
	_saved_area = SoundManager._current_area
	_saved_suffix = SoundManager._current_world_suffix
	SoundManager._current_area = "overworld_medieval"
	SoundManager._current_world_suffix = "medieval"


func after_each() -> void:
	SoundManager._current_area = _saved_area
	SoundManager._current_world_suffix = _saved_suffix
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _abilities() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_true(parsed is Dictionary, "VOID: abilities.json did not parse")
	return (parsed as Dictionary).get("abilities", parsed) if parsed is Dictionary else {}


## What play_ability leaves on the ability player, from a cleared player: "" when it played nothing.
func _cast(id: String) -> String:
	var p: AudioStreamPlayer = SoundManager._ability_player
	p.stop()
	p.stream = null
	SoundManager._sfx_cooldowns.clear()
	SoundManager.play_ability(id)
	return p.stream.resource_path if p.stream != null else ""


func test_every_unmapped_support_ability_with_an_effect_casts_silently() -> void:
	var abilities := _abilities()
	var judged := 0
	var sword: Array[String] = []
	for aid in abilities:
		var a = abilities[aid]
		if not (a is Dictionary) or str(a.get("type", "")) != "support" or str(a.get("effect", "")) == "":
			continue
		if SoundManager._ability_sounds.has(str(aid)):
			continue
		judged += 1
		if not SoundManager._silent_cast_abilities.has(str(aid)):
			sword.append(str(aid))
	assert_gt(judged, 40, "CONTROL: the monster support kit was read")
	assert_eq(sword, [], "these support abilities still cast ability_physical, a sword: %s" % [sword])


func test_a_masterite_buff_plays_nothing_on_cast() -> void:
	assert_ne(_cast("fire"), "", "CONTROL: a mapped spell does leave its stream on the ability player")
	for id in ["masterite_proclamation", "masterite_slow", "crown_authority"]:
		assert_eq(_cast(id), "", "%s's cast must not draw a sword; its landing is cued by _on_action_executed" % id)


func test_a_support_ability_with_a_cue_of_its_own_keeps_it() -> void:
	var path := _cast("protect")
	assert_ne(path, "", "the hand map outranks the silent set: Protect still casts its own cue")
	assert_false(SoundManager._silent_cast_abilities.has("protect"), "a mapped ability is never put in the silent set")


func test_an_unmapped_physical_ability_still_swings() -> void:
	var abilities := _abilities()
	var phys := ""
	for aid in abilities:
		var a = abilities[aid]
		if a is Dictionary and str(a.get("type", "")) == "physical" and not SoundManager._ability_sounds.has(str(aid)):
			phys = str(aid)
			break
	assert_ne(phys, "", "CONTROL: an unmapped physical ability exists")
	var sword_file: String = str(SoundManager._sfx_manifest.get(SWORD, {}).get("file", "?"))
	assert_true(_cast(phys).ends_with(sword_file), "%s is a weapon strike and keeps the sword" % phys)
