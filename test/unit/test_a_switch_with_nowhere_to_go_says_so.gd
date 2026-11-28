extends GutTest

## Switching character or profile in a rule editor with nowhere to go buzzed with no reason, and with every other member spotlight-locked it clicked menu_select and "switched" to the same character.
## Each now plays menu_error and says why; a real switch still clicks. Read through cooldown stamps, whose CONTROL is the first arm.

const AB_EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const AG_EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

var _abs
var _profiles_backup: Dictionary = {}
var _scripts_backup: Dictionary = {}
var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	_profiles_backup = (_abs.character_profiles as Dictionary).duplicate(true)
	SoundManager._sfx_cooldowns.clear()


func after_each() -> void:
	var live: Dictionary = _abs.character_profiles
	live.clear()
	for k in _profiles_backup:
		live[k] = _profiles_backup[k]
	AutogrindState.restore(_ag)
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


func _member(n: String, locked: bool = false) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = n
	c.autobattle_locked = locked
	return c


func _ab_editor(party: Array) -> Node:
	var ed: Node = load(AB_EDITOR).new()
	ed.size = Vector2(1280, 720)
	add_child_autofree(ed)
	await get_tree().process_frame
	ed.setup("hero", "Hero", party[0], party)
	await get_tree().process_frame
	SoundManager._sfx_cooldowns.clear()
	return ed


func _ag_editor() -> Node:
	var ed: Node = load(AG_EDITOR).new()
	ed.size = Vector2(1280, 720)
	add_child_autofree(ed)
	await get_tree().process_frame
	ed.setup([])
	await get_tree().process_frame
	SoundManager._sfx_cooldowns.clear()
	return ed


func _shown(ed: Node) -> String:
	var label: Label = ed.get("_flash_label") if ed.get("_flash_label") != null else ed.get("_status_label")
	return str(label.text) if label != null else ""


## hero gets exactly n profiles, so one and two are the fixture's, not the save's.
func _give_hero(n: int) -> void:
	_abs.get_character_profiles("hero")
	var list: Array = []
	for i in n:
		list.append({"name": "P%d" % i, "rules": []})
	(_abs.character_profiles["hero"] as Dictionary)["profiles"] = list
	(_abs.character_profiles["hero"] as Dictionary)["active"] = 0


func test_the_cue_oracle_can_see_a_cue() -> void:
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table starts clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"), "CONTROL: play_ui leaves a stamp, or every arm here measures nothing")


func test_switching_to_an_unlocked_member_still_clicks() -> void:
	var party := [_member("Hero"), _member("Mira")]
	var ed: Node = await _ab_editor(party)
	ed._cycle_character(1)
	assert_eq(int(ed.current_party_index), 1, "CONTROL: the editor moved to Mira")
	assert_true(_stamped("menu_select"), "a real switch must still click")
	assert_false(_stamped("menu_error"), "a real switch must not play the refusal")


func test_a_party_of_one_is_refused_with_a_reason() -> void:
	var ed: Node = await _ab_editor([_member("Hero")])
	ed._cycle_character(1)
	assert_true(_stamped("menu_error"), "CONTROL: a party of one was already refused out loud")
	assert_string_contains(_shown(ed), "no one else", "the refusal must say why")


func test_every_other_member_locked_is_refused_not_a_switch_to_yourself() -> void:
	var party := [_member("Hero"), _member("Mira", true), _member("Zack", true)]
	var ed: Node = await _ab_editor(party)
	assert_eq(int(ed.current_party_index), 0, "CONTROL: the editor starts on the hero")
	var saves := [0]
	ed.script_saved.connect(func(_id, _s): saves[0] += 1)
	ed._cycle_character(1)
	assert_eq(int(ed.current_party_index), 0, "CONTROL: the lap came home to the hero")
	assert_eq(saves[0], 0, "a refused switch still wrote the script")
	assert_false(_stamped("menu_select"), "with everyone else locked the press clicked as a switch to the same character")
	assert_true(_stamped("menu_error"), "with everyone else locked the press was not refused")
	assert_string_contains(_shown(ed), "can be edited yet", "the refusal must say why")


func test_one_profile_is_refused_with_a_reason() -> void:
	_give_hero(1)
	var ed: Node = await _ab_editor([_member("Hero")])
	ed._cycle_profile()
	assert_true(_stamped("menu_error"), "CONTROL: one profile was already refused out loud")
	assert_string_contains(_shown(ed), "only one profile", "the refusal must say why")
	assert_string_contains(_shown(ed), "Hero", "the refusal must name whose profiles")


func test_one_grind_profile_is_refused_with_a_reason() -> void:
	var ed: Node = await _ag_editor()
	var profiles: Array = AutogrindSystem.get_autogrind_profiles()
	assert_true(profiles.size() >= 1, "CONTROL: the grind has a profile")
	while AutogrindSystem.get_autogrind_profiles().size() > 1:
		AutogrindSystem.get_autogrind_profiles().pop_back()
	assert_eq(AutogrindSystem.get_autogrind_profiles().size(), 1, "CONTROL: exactly one grind profile")
	ed._cycle_profile()
	assert_true(_stamped("menu_error"), "CONTROL: one grind profile was already refused out loud")
	assert_string_contains(_shown(ed), "only one grind profile", "the refusal must say why")
