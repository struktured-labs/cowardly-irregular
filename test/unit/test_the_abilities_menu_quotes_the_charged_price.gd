extends GutTest

## The field Abilities menu read each ability's AUTHORED mp_cost, while the engine charges
## JobSystem.get_ability_mp_cost: a mp_cost_multiplier passive (mp_efficiency 0.75x, magic_amplifier 2.5x)
## changes the price. The battle menu was routed through the resolver in tick 374
## (test_the_menu_quotes_the_price_the_engine_charges); this screen was its missed sibling.

const MENU := preload("res://src/ui/AbilitiesMenu.gd")


func _cost_passive() -> String:
	var ps = get_node_or_null("/root/PassiveSystem")
	if ps == null:
		return ""
	for pid in ps.passives:
		var m: Dictionary = (ps.passives[pid] as Dictionary).get("stat_mods", {})
		if m.has("mp_cost_multiplier") and not is_equal_approx(float(m["mp_cost_multiplier"]), 1.0):
			return str(pid)
	return ""


func test_the_row_and_the_details_quote_the_charged_price() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/AbilitiesMenu.gd")
	assert_false(src.contains('"%d MP" % data.get("mp_cost", 0)') or src.contains('"MP Cost: %d" % data.get("mp_cost", 0)'),
		"neither the row nor the details panel may print the authored cost directly")
	assert_eq(src.count("_charged_mp(ability, data)"), 2, "the row and the details panel both quote through _charged_mp")
	if not src.contains("func _charged_mp("):
		return
	var pid := _cost_passive()
	assert_ne(pid, "", "CONTROL: a passive must move MP cost, or both prices agree by coincidence")
	if pid == "":
		return
	var c := Combatant.new()
	c.initialize({"name": "Mage", "max_hp": 100, "max_mp": 999, "attack": 10, "defense": 10, "magic": 40, "speed": 10})
	add_child_autofree(c)
	c.equipped_passives = [pid] as Array[String]
	var ability := {"id": "cura", "data": JobSystem.get_ability("cura")}
	var authored: int = int(ability["data"].get("mp_cost", 0))
	var charged: int = JobSystem.get_ability_mp_cost(c, "cura")
	assert_ne(authored, charged, "CONTROL: with %s equipped Cura's price must move (%d vs %d)" % [pid, authored, charged])
	var menu = MENU.new()
	add_child_autofree(menu)
	menu.character = c
	assert_eq(menu._charged_mp(ability, ability["data"]), charged,
		"the Abilities menu must show what the engine charges (%d), not the authored %d" % [charged, authored])
