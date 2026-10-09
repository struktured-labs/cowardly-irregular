extends GutTest

## The Status screen printed each stat as "(base +bonus)" off Combatant.base_* -- placeholder defaults (10 ATK, 100 HP,
## 50 MP) that recalculate_stats() REPLACES with the job's own values. So a Lv1 Fighter read "Attack 414 (10 +404)",
## putting the whole job into the "bonus", and "Max MP 34 (50 -16)" in red, a penalty that does not exist. The
## breakdown is now (without gear +gear), the same gear figure the Equipment screen lists.

const StatusMenuScript := preload("res://src/ui/StatusMenu.gd")


func _fighter() -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Probe"
	JobSystem.assign_job(c, "fighter")
	EquipmentSystem.equip_weapon(c, "iron_sword")
	c.recalculate_stats()
	return c


func _breakdowns(n: Node, out: Array) -> Array:
	for ch in n.get_children():
		if ch is Label and (ch as Label).text.begins_with("(") and (ch as Label).text.ends_with(")"):
			out.append((ch as Label).text)
		_breakdowns(ch, out)
	return out


func test_the_attack_breakdown_is_the_weapon_not_the_job() -> void:
	var c := _fighter()
	var gear: Dictionary = EquipmentSystem.get_equipment_mods(c)
	assert_gt(int(gear.get("attack", 0)), 0, "CONTROL: the iron sword adds attack")
	var menu = StatusMenuScript.new()
	add_child_autofree(menu)
	menu.setup(c)
	await get_tree().process_frame
	var want := "(%d +%d)" % [c.attack - int(gear["attack"]), int(gear["attack"])]
	var got := _breakdowns(menu, [])
	assert_true(want in got, "Attack reads %s, the sword's own +%d (got %s)" % [want, int(gear["attack"]), str(got)])
	assert_false(("(%d +%d)" % [c.base_attack, c.attack - c.base_attack]) in got, "the placeholder base_attack no longer appears")


func test_a_stat_gear_does_not_touch_shows_no_breakdown() -> void:
	var c := _fighter()
	var gear: Dictionary = EquipmentSystem.get_equipment_mods(c)
	assert_eq(int(gear.get("max_mp", 0)), 0, "CONTROL: nothing equipped changes MP")
	var menu = StatusMenuScript.new()
	add_child_autofree(menu)
	menu.setup(c)
	await get_tree().process_frame
	for t in _breakdowns(menu, []):
		assert_false(t.begins_with("(%d " % c.base_max_mp), "no invented MP penalty against the placeholder base: %s" % t)
