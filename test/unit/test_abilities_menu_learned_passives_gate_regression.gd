extends GutTest

## Issue #192 playtesting caveat: AbilitiesMenu._build_passives_list stubbed
## `is_learned` with `or true`, so every catalog passive was treated as learned
## and any character could equip the full set instead of their learned 2.
##
## The stub is gone. `is_learned` is membership in character.learned_passives
## only, and _toggle_passive refuses to equip an unlearned id.
##
## Runtime arms below fail if the stub returns: every row would be learned,
## unlearned_count would be 0, and toggle on a catalog-only id would succeed.

const ABILITIES_MENU := "res://src/ui/AbilitiesMenu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const AbilitiesMenuScript = preload("res://src/ui/AbilitiesMenu.gd")

const LEARNED_ID := "hp_boost"


func _make_menu() -> AbilitiesMenu:
	var menu: AbilitiesMenu = AbilitiesMenuScript.new()
	add_child_autofree(menu)
	return menu


func _make_combatant() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "LearnedGateProbe"
	c.max_passive_slots = 5
	add_child_autofree(c)
	return c


func _fn_code(src: String, fn_name: String) -> String:
	var idx: int = src.find("func %s" % fn_name)
	assert_gt(idx, -1, "floor: %s must exist in AbilitiesMenu" % fn_name)
	if idx < 0:
		return ""
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func _index_of(menu: AbilitiesMenu, passive_id: String) -> int:
	for i in menu._passives_list.size():
		if str(menu._passives_list[i].get("id", "")) == passive_id:
			return i
	return -1


func _try_toggle(menu: AbilitiesMenu) -> void:
	menu._toggle_passive()


func test_file_reaches_the_gate_symbols() -> void:
	var menu := _make_menu()
	assert_true(menu.has_method("_build_passives_list"),
		"floor: _build_passives_list — this file's learned-flag arm dies silently if the method is renamed")
	assert_true(menu.has_method("_toggle_passive"),
		"floor: _toggle_passive — this file's equip-gate arm dies silently if the method is renamed")


func test_build_passives_list_has_no_or_true_stub() -> void:
	var parts: Dictionary = GdSource.split(FileAccess.get_file_as_string(ABILITIES_MENU))
	var code: String = str(parts.get("code", ""))
	assert_true(code.contains("func _build_passives_list"),
		"CONTROL: GdSource must still see _build_passives_list, else the stripper ate the subject")
	var body := _fn_code(code, "_build_passives_list")
	assert_true(body.contains("passive_id in character.learned_passives"),
		"_build_passives_list must compute is_learned from character.learned_passives")
	assert_false(body.contains("or true"),
		"`or true` stub must stay gone — that is the #192 learned-check bypass")


func test_toggle_passive_honors_learned_passives() -> void:
	var parts: Dictionary = GdSource.split(FileAccess.get_file_as_string(ABILITIES_MENU))
	var code: String = str(parts.get("code", ""))
	assert_true(code.contains("func _toggle_passive"),
		"CONTROL: GdSource must still see _toggle_passive, else the stripper ate the subject")
	var body := _fn_code(code, "_toggle_passive")
	assert_true(body.contains("character.learned_passives"),
		"_toggle_passive must consult character.learned_passives before equip — display flags alone would not stop the stub")
	assert_true(body.contains("Passive not learned"),
		"unlearned equip must toast rather than fail silently")


func test_only_learned_passives_are_marked_learned() -> void:
	var ps: Node = get_node_or_null("/root/PassiveSystem")
	assert_not_null(ps, "PassiveSystem autoload must exist")
	if ps == null:
		return
	assert_gt(ps.passives.size(), 1,
		"CONTROL: catalog must have more than one passive, else the stub cannot be seen")
	assert_true(ps.passives.has(LEARNED_ID),
		"CONTROL: %s must exist in the catalog" % LEARNED_ID)

	var menu := _make_menu()
	var c := _make_combatant()
	c.learn_passive(LEARNED_ID)
	menu.character = c
	menu._build_passives_list()

	assert_gt(menu._passives_list.size(), 1,
		"CONTROL: list must include catalog entries beyond the one learned id")

	var learned_marked: Array[String] = []
	var unlearned_count := 0
	for entry in menu._passives_list:
		var pid := str(entry.get("id", ""))
		if bool(entry.get("learned", false)):
			learned_marked.append(pid)
		else:
			unlearned_count += 1

	assert_true(LEARNED_ID in learned_marked,
		"the one learned passive must be marked learned")
	assert_eq(learned_marked.size(), 1,
		"exactly the learned set may be marked learned — the `or true` stub would mark the whole catalog")
	assert_gt(unlearned_count, 0,
		"must observe at least one unlearned row, else the stub is invisible")


func test_toggle_refuses_an_unlearned_passive() -> void:
	var ps: Node = get_node_or_null("/root/PassiveSystem")
	assert_not_null(ps, "PassiveSystem autoload must exist")
	if ps == null:
		return

	var menu := _make_menu()
	var c := _make_combatant()
	c.learn_passive(LEARNED_ID)
	menu.character = c
	menu.current_tab = AbilitiesMenu.Tab.PASSIVES
	menu._build_passives_list()

	var unlearned_id := ""
	for entry in menu._passives_list:
		var pid := str(entry.get("id", ""))
		if pid != "" and pid != LEARNED_ID:
			unlearned_id = pid
			break
	assert_ne(unlearned_id, "",
		"CONTROL: catalog must contain an id this character has not learned")

	menu.selected_index = _index_of(menu, unlearned_id)
	assert_gt(menu.selected_index, -1, "unlearned id must be in the list")
	_try_toggle(menu)
	assert_false(unlearned_id in c.equipped_passives,
		"unlearned passives must not equip — the #192 stub made every catalog id equippable")


func test_toggle_equips_a_learned_passive() -> void:
	var ps: Node = get_node_or_null("/root/PassiveSystem")
	assert_not_null(ps, "PassiveSystem autoload must exist")
	if ps == null:
		return
	assert_true(ps.passives.has(LEARNED_ID),
		"CONTROL: %s must exist so the learned-equip path is a real equip" % LEARNED_ID)

	var menu := _make_menu()
	var c := _make_combatant()
	c.learn_passive(LEARNED_ID)
	menu.character = c
	menu.current_tab = AbilitiesMenu.Tab.PASSIVES
	menu._build_passives_list()

	menu.selected_index = _index_of(menu, LEARNED_ID)
	assert_gt(menu.selected_index, -1, "%s must be in the passives list" % LEARNED_ID)
	_try_toggle(menu)
	assert_true(LEARNED_ID in c.equipped_passives,
		"CONTROL: a learned passive MUST still equip — otherwise the refuse arm is vacuously green")
