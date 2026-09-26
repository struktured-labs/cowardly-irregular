extends GutTest

## Character creation advertises a nature as a stat ("+2 ATK", "+2 DEF", "+2 MAG",
## "+2 SPD", "+2 MAG +1 SPD"). apply_stat_bonus stores that on base_attack and
## friends, then recalculate_stats replaces those fields with the job's
## stat_modifiers. Every created character has a job, so the status screen and
## every hit read the job number and the nature contributes 0.
##
## The bonus is added back only after the player confirms a nature
## (nature_bonus_live). A customization that merely carries a roster personality
## — the default party — must not move stats.


func _fighter_mods() -> Dictionary:
	return JobSystem.get_job("fighter").get("stat_modifiers", {})


func _level_mult(level: int) -> float:
	return 1.0 + float(level - 1) * 0.04


func _member() -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	# After _ready: it copies max into current, and anything set before that is gone.
	c.job_level = 6
	c.job = JobSystem.get_job("fighter")
	c.equipped_weapon = "iron_sword"
	return c


func _confirm_nature(c: Combatant, personality: int) -> void:
	var custom := CharacterCustomization.new("Hero")
	custom.personality = personality
	c.customization = custom
	custom.apply_stat_bonus(c)
	c.recalculate_stats()


func _expected_attack(job_attack: int, nature_attack: int, level: int, gear_attack: int) -> int:
	return int((job_attack + nature_attack) * _level_mult(level)) + gear_attack


func test_brave_nature_shows_on_the_status_attack() -> void:
	var c := _member()
	_confirm_nature(c, CharacterCustomization.Personality.BRAVE)
	var mods := _fighter_mods()
	var gear := int(EquipmentSystem.get_weapon("iron_sword").get("stat_mods", {}).get("attack", 0))
	assert_gt(gear, 0, "the iron sword must grant attack or the status number is not a geared character")
	var expected := _expected_attack(int(mods["attack"]), 2, c.job_level, gear)
	assert_eq(c.attack, expected,
		"Brave promises +2 ATK. Job mods replace base_attack, so the status attack was the bare job total")
	var plain := _member()
	plain.customization = CharacterCustomization.new("Fighter")
	plain.customization.personality = CharacterCustomization.Personality.BRAVE
	plain.recalculate_stats()
	assert_gt(c.attack, plain.attack,
		"a confirmed Brave nature must raise the attack the status screen prints above an unconfirmed one")
	var menu := StatusMenu.new()
	add_child_autofree(menu)
	menu.character = c
	var panel: Control = menu._create_stats_panel(Vector2(320, 480))
	add_child_autofree(panel)
	var shown := ""
	for node in _labels(panel):
		if node.text == "Attack":
			for sibling in node.get_parent().get_children():
				if sibling is Label and (sibling as Label).text.is_valid_int():
					shown = (sibling as Label).text
	assert_eq(shown, str(c.attack),
		"the status Attack row must print the attack combat uses, including the nature")
	assert_eq(int(shown), expected, "the row must be the job total plus the promised +2 ATK, after level and gear")


func test_each_confirmed_nature_lands_on_its_stat() -> void:
	var mods := _fighter_mods()
	var cases := [
		[CharacterCustomization.Personality.BRAVE, "attack", 2],
		[CharacterCustomization.Personality.CAUTIOUS, "defense", 2],
		[CharacterCustomization.Personality.SCHOLARLY, "magic", 2],
		[CharacterCustomization.Personality.QUICK, "speed", 2],
		[CharacterCustomization.Personality.CHARISMATIC, "magic", 2],
		[CharacterCustomization.Personality.CHARISMATIC, "speed", 1],
	]
	for row in cases:
		var c := _member()
		c.equipped_weapon = ""
		_confirm_nature(c, int(row[0]))
		var stat: String = str(row[1])
		var bonus: int = int(row[2])
		var expected := int((int(mods[stat]) + bonus) * _level_mult(c.job_level))
		assert_eq(int(c.get(stat)), expected,
			"%s must add %+d %s on top of the job total — the creation line is otherwise a lie" % [
				CharacterCustomization.get_personality_name(int(row[0])), bonus, stat])


func test_an_unconfirmed_roster_nature_does_not_change_stats() -> void:
	var c := _member()
	c.customization = CharacterCustomization.new("Fighter")
	c.customization.personality = CharacterCustomization.Personality.BRAVE
	c.recalculate_stats()
	var mods := _fighter_mods()
	var gear := int(EquipmentSystem.get_weapon("iron_sword").get("stat_mods", {}).get("attack", 0))
	assert_eq(c.attack, _expected_attack(int(mods["attack"]), 0, c.job_level, gear),
		"the default party stores Brave as flavor and never confirms it — that must not grant +2 ATK")


func test_confirmed_nature_survives_save_and_load() -> void:
	var c := _member()
	_confirm_nature(c, CharacterCustomization.Personality.BRAVE)
	var mods := _fighter_mods()
	var gear := int(EquipmentSystem.get_weapon("iron_sword").get("stat_mods", {}).get("attack", 0))
	var expected := _expected_attack(int(mods["attack"]), 2, c.job_level, gear)
	assert_eq(c.attack, expected, "the saved character must already be carrying the +2, or the round-trip asserts nothing")
	var data: Dictionary = c.to_dict()
	var loaded := Combatant.new()
	add_child_autofree(loaded)
	loaded.from_dict(data)
	loaded.job = JobSystem.get_job("fighter")
	loaded.equipped_weapon = "iron_sword"
	loaded.recalculate_stats()
	assert_eq(loaded.attack, expected,
		"loading a created character must keep the nature inside the attack the status screen shows")


func _labels(root: Node) -> Array:
	var found: Array = []
	_collect(root, found)
	return found


func _collect(n: Node, found: Array) -> void:
	if n is Label:
		found.append(n)
	for child in n.get_children():
		_collect(child, found)
