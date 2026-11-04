extends GutTest

## struktured 2026-11-01, via cowir-main: "why can't the Cleric use Anima Reddita (raise) out of battle"
## — and then "ANY heal abilities are allowed out of battle". The reachable field menu (AbilitiesMenu)
## had no Cast at all; MenuScene's healing-only Cast was dead code. These arms drive FieldCast and the
## menu itself, one per restorative kind, plus the derived-set floor and the battle-only refusal.


func _pc(name: String, hp: int = 100, mp: int = 50) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name
	c.max_hp = 200
	c.current_hp = hp
	c.max_mp = 60
	c.current_mp = mp
	c.magic = 10
	c.is_alive = hp > 0
	autofree(c)
	return c


func _all_abilities() -> Dictionary:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	return d.get("abilities", d)


## FLOOR: the set is derived, so pin that it reaches every restorative TYPE the data authors and
## refuses every damaging one. A filter that drops a kind (the old healing-only Cast) reds here by name.
func test_the_castable_set_covers_every_restorative_kind_and_no_damage() -> void:
	var kinds := {}
	var leaked: Array = []
	for id in _all_abilities():
		var a: Dictionary = _all_abilities()[id]
		var k := FieldCast.kind(a)
		if k != "":
			kinds[k] = true
		if str(a.get("type", "")) in ["magic", "physical"] and k != "":
			leaked.append(id)
	for want in ["heal", "revive", "mp", "cleanse", "regen"]:
		assert_true(kinds.has(want), "no ability resolved to field kind '%s' — got %s" % [want, kinds.keys()])
	assert_eq(leaked, [], "damaging abilities must stay battle-only")
	assert_false(FieldCast.castable(JobSystem.get_ability("fire")), "Fire is battle-only")
	assert_false(FieldCast.castable(JobSystem.get_ability("protect")), "a combat buff is battle-only")


func test_raise_revives_a_fallen_ally_and_spends_mp() -> void:
	var cleric := _pc("Cleric")
	var down := _pc("Fighter", 0)
	var r := FieldCast.cast(cleric, "raise", [down])
	assert_true(r["ok"], "raise on a KO'd ally must land: %s" % r["text"])
	assert_true(down.is_alive, "the fallen ally stands up")
	assert_eq(down.current_hp, 100, "revive_percentage 50 of 200")
	assert_eq(cleric.current_mp, 50 - JobSystem.get_ability_mp_cost(cleric, "raise"), "raise costs its MP")


func test_raise_on_the_living_is_refused_and_free() -> void:
	var cleric := _pc("Cleric")
	var up := _pc("Fighter", 120)
	var r := FieldCast.cast(cleric, "raise", [up])
	assert_false(r["ok"], "raise on a living ally does nothing")
	assert_string_contains(r["text"], "isn't down")
	assert_eq(cleric.current_mp, 50, "a refused cast spends no MP")


func test_cure_heals_and_a_full_target_is_refused() -> void:
	var cleric := _pc("Cleric")
	var hurt := _pc("Mage", 50)
	var r := FieldCast.cast(cleric, "cure", [hurt])
	assert_true(r["ok"], r["text"])
	assert_gt(hurt.current_hp, 50, "cure heals in the field")
	var full := _pc("Rogue", 200)
	var mp_before := cleric.current_mp
	assert_false(FieldCast.cast(cleric, "cure", [full])["ok"], "a full-HP target is refused")
	assert_eq(cleric.current_mp, mp_before, "and the refusal is free")
	var down := _pc("Bard", 0)
	assert_false(FieldCast.cast(cleric, "cure", [down])["ok"], "cure cannot reach a KO'd ally")


func test_pray_restores_mp_and_esuna_cures() -> void:
	var cleric := _pc("Cleric")
	var drained := _pc("Mage", 100, 5)
	assert_true(FieldCast.cast(cleric, "pray", [drained])["ok"])
	assert_gt(drained.current_mp, 5, "pray restores MP in the field")
	var sick := _pc("Fighter", 100)
	sick.add_status("poison", 3)
	assert_true(sick.has_status("poison"), "CONTROL: the fixture is poisoned")
	assert_true(FieldCast.cast(cleric, "esuna", [sick])["ok"])
	assert_false(sick.has_status("poison"), "esuna cures in the field")


func test_regenerate_delivers_its_whole_course_at_once() -> void:
	var a: Dictionary = JobSystem.get_ability("regenerate")
	var pc := _pc("Cleric", 20)
	assert_true(FieldCast.cast(pc, "regenerate", [pc])["ok"])
	assert_eq(pc.current_hp, 20 + int(a["regen_per_turn"]) * int(a["duration"]), "per-turn x turns")


func test_the_menu_casts_raise_on_the_fallen_member() -> void:
	var cleric := _pc("Cleric")
	cleric.learned_abilities.append("raise")
	var down := _pc("Fighter", 0)
	var menu = load("res://src/ui/AbilitiesMenu.gd").new()
	menu.setup(cleric, [cleric, down])
	add_child_autofree(menu)
	await get_tree().process_frame
	var idx := -1
	for i in range(menu._abilities_list.size()):
		if menu._abilities_list[i]["id"] == "raise":
			idx = i
	assert_ne(idx, -1, "PRECONDITION: raise is in the cleric's list")
	if idx == -1:
		return
	menu.selected_index = idx
	menu._begin_cast()
	assert_true(menu._picking, "a single-target cast opens the target picker")
	assert_eq(menu._pick_index, 1, "the picker starts on the fallen member")
	menu._finish_cast([menu.party[menu._pick_index]])
	assert_true(down.is_alive, "Accept in the picker revives them")
	assert_false(menu._picking, "with no one left to raise, the picker closes")


## Items' rule (struktured 2026-07-16): a second potion needs no reselect, and neither does a second Cure.
func test_the_picker_stays_open_while_another_cast_can_help() -> void:
	var cleric := _pc("Cleric")
	cleric.learned_abilities.append("cure")
	var a := _pc("Fighter", 20)
	var b := _pc("Mage", 30)
	var menu = load("res://src/ui/AbilitiesMenu.gd").new()
	menu.setup(cleric, [cleric, a, b])
	add_child_autofree(menu)
	await get_tree().process_frame
	var idx := -1
	for i in range(menu._abilities_list.size()):
		if menu._abilities_list[i]["id"] == "cure":
			idx = i
	assert_ne(idx, -1, "PRECONDITION: cure is in the cleric's list")
	if idx == -1:
		return
	menu.selected_index = idx
	menu._begin_cast()
	assert_true(menu._picking, "CONTROL: cure opens the picker")
	menu._finish_cast([menu.party[menu._pick_index]])
	assert_true(menu._picking, "two hurt members and MP to spare: the picker stays open for the next cast")
	cleric.current_mp = 0
	menu._finish_cast([b])
	assert_true(menu._picking, "CONTROL: a refused cast (no MP) leaves the picker where it was")
	cleric.current_mp = JobSystem.get_ability_mp_cost(cleric, "cure")
	menu._finish_cast([b])
	assert_false(menu._picking, "MP for exactly one more cast, spent: the picker closes")
