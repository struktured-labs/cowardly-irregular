extends GutTest

## A profile name is capped where it is WRITTEN, once per system: autobattle at 16 and autogrind at 20, the numbers their
## rename keyboards already took (main 27563 kept both). An LLM-composed ruleset's title used to become the profile name
## uncapped and run off the editor's profile pill. Over the cap a name is cut with "…" inside the cap; the full composed
## title stays readable in the editor's install line. A name already in a save is NOT cut (no migration).

const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const AB_ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const AG_ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const LONG := "Aggressive late game boss killer with a healer standing by"  # 58 chars, a composer-sized title

var _ab_entry: Dictionary = {}
var _ag_state = null
var _saved_ab_persist := false
var _saved_ag_persist := false
var _ed: Node = null


func before_each() -> void:
	_saved_ab_persist = AutobattleSystem._test_disable_persistence
	_saved_ag_persist = AutogrindSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	AutogrindSystem._test_disable_persistence = true
	_ab_entry = ABProfiles.snapshot(AutobattleSystem)
	_ag_state = AutogrindState.snapshot()


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null
	ABProfiles.restore(AutobattleSystem, _ab_entry)
	AutogrindState.restore(_ag_state)
	AutobattleSystem._test_disable_persistence = _saved_ab_persist
	AutogrindSystem._test_disable_persistence = _saved_ag_persist


func _ab_names() -> Array:
	return AutobattleSystem.get_character_profiles("hero").map(func(p) -> String: return str(p.get("name", "")))


func _ag_profiles() -> Array:
	AutogrindSystem._ensure_autogrind_profiles()
	return AutogrindSystem.autogrind_profiles.get("profiles", [])


func _cut_ok(n: String, cap: int, tag: String) -> void:
	assert_lte(n.length(), cap, "%s: '%s' is at most %d characters" % [tag, n, cap])
	assert_true(n.ends_with("…"), "%s: a cut name says so with '…' ('%s')" % [tag, n])
	assert_true(LONG.begins_with(n.trim_suffix("…").strip_edges()), "%s: and keeps the start of the name" % tag)


func test_every_autobattle_writer_caps_at_16() -> void:
	assert_eq(AutobattleSystem.PROFILE_NAME_MAX, 16, "CONTROL: autobattle's cap is its keyboard's 16")
	assert_gt(LONG.length(), 16, "CONTROL: the fixture is over the cap")
	AutobattleSystem._ensure_character_profiles("hero")
	var i: int = AutobattleSystem.create_new_profile("hero", LONG)
	assert_gte(i, 0, "CONTROL: create_new_profile made a slot")
	if i >= 0:
		_cut_ok(_ab_names()[i], 16, "create_new_profile")
		assert_true(AutobattleSystem.rename_profile("hero", i, LONG), "CONTROL: rename_profile took it")
		_cut_ok(_ab_names()[i], 16, "rename_profile")
	var j: int = AutobattleSystem.install_composition_as_new_profile("hero", {"name": LONG, "description": "d", "rules": []})
	assert_gte(j, 0, "CONTROL: the composition installed")
	if j >= 0:
		_cut_ok(_ab_names()[j], 16, "install_composition_as_new_profile")
		var sc: Dictionary = AutobattleSystem.get_character_profiles("hero")[j].get("script", {})
		assert_eq(str(sc.get("name", "")), LONG, "the installed script keeps the full title")


func test_every_autogrind_writer_caps_at_20() -> void:
	assert_eq(AutogrindSystem.PROFILE_NAME_MAX, 20, "CONTROL: autogrind's cap is its keyboard's 20")
	var i: int = AutogrindSystem.create_new_autogrind_profile(LONG)
	assert_gte(i, 0, "CONTROL: create_new_autogrind_profile made a slot")
	if i >= 0:
		_cut_ok(str(_ag_profiles()[i].get("name", "")), 20, "create_new_autogrind_profile")
		assert_true(AutogrindSystem.rename_autogrind_profile(i, LONG), "CONTROL: rename took it")
		_cut_ok(str(_ag_profiles()[i].get("name", "")), 20, "rename_autogrind_profile")


func test_a_name_at_or_under_the_cap_is_stored_as_typed() -> void:
	for n in ["Boss", "ABCDEFGHIJKLMNOP"]:  # 4 and exactly 16
		assert_eq(AutobattleSystem.cap_profile_name(n), n, "autobattle keeps '%s' as typed" % n)
	for n in ["Grind", "ABCDEFGHIJKLMNOPQRST"]:  # 5 and exactly 20
		assert_eq(AutogrindSystem.cap_profile_name(n), n, "autogrind keeps '%s' as typed" % n)


func test_each_rename_keyboard_reads_its_systems_cap() -> void:
	var ab_src: String = FileAccess.get_file_as_string(AB_ED)
	var ag_src: String = FileAccess.get_file_as_string(AG_ED)
	assert_string_contains(ab_src, '_keyboard.setup("Rename Profile", current_name, AutobattleSystem.PROFILE_NAME_MAX)', "autobattle's keyboard reads 16 from the system")
	assert_string_contains(ag_src, '_keyboard.setup("Rename Autogrind Profile", current_name, AutogrindSystem.PROFILE_NAME_MAX)', "autogrind's keyboard reads 20 from the system")


func test_a_long_name_already_in_a_save_is_kept() -> void:
	## Loading puts the saved dictionary in place as is (no writer runs); nothing may cut it afterwards.
	AutobattleSystem._ensure_character_profiles("hero")
	var profs: Array = AutobattleSystem.character_profiles["hero"]["profiles"]
	profs[0]["name"] = LONG
	AutobattleSystem._ensure_character_profiles("hero")
	assert_eq(_ab_names()[0], LONG, "an autobattle save's long name is untouched")
	var ag: Array = _ag_profiles()
	ag[0]["name"] = LONG
	AutogrindSystem._ensure_autogrind_profiles()
	assert_eq(str(_ag_profiles()[0].get("name", "")), LONG, "an autogrind save's long name is untouched")


## The editors type _rule_composer_overlay as Control, so the stand-in must be one: a Node here aborted the arm, and GUT
## scored the aborted arm as a pass.
func _fake_overlay(title: String) -> Control:
	var s := GDScript.new()
	s.source_code = "extends Control\nvar _last_composition: Dictionary = {}\n"
	s.reload()
	var n: Control = s.new()
	n.set("_last_composition", {"name": title, "description": "", "rules": []})
	return n


func test_the_install_line_shows_the_full_title() -> void:
	## Autobattle: the editor's flash.
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	_ed = load(AB_ED).new()
	_ed.size = Vector2(1280, 720)
	vp.add_child(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame
	var j: int = AutobattleSystem.install_composition_as_new_profile("hero", {"name": LONG, "description": "", "rules": []})
	assert_gte(j, 0, "CONTROL: the composition installed")
	var ov := _fake_overlay(LONG)
	_ed.add_child(ov)
	_ed._rule_composer_overlay = ov
	_ed._on_composer_installed(j)
	assert_string_contains(_ed._flash_label.text, LONG, "autobattle: the install line names the whole title")
	_ed.queue_free()
	## Autogrind: the editor's status line.
	_ed = load(AG_ED).new()
	vp.add_child(_ed)
	await get_tree().process_frame
	_ed.setup([])
	await get_tree().process_frame
	var k: int = AutogrindSystem.create_new_autogrind_profile(LONG)
	assert_gte(k, 0, "CONTROL: a grind profile was made")
	var ov2 := _fake_overlay(LONG)
	_ed.add_child(ov2)
	_ed._rule_composer_overlay = ov2
	_ed._on_composer_installed(k)
	assert_string_contains(_ed._status_label.text, LONG, "autogrind: the install line names the whole title")
