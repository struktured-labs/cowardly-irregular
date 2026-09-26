extends GutTest

## A new character's starting kit lives on the job, not in learned_abilities.
## The overworld abilities menu, party status, and the autogrind "Member Casts"
## seeder read only that array, so a fresh Mage's screen said "No abilities learned"
## while battle listed Ignis, and Member Casts was filled in as the lead Fighter
## casting Cure — a spell he does not know, so the rule saved and never fired.

func _fresh(job_id: String, secondary_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.combatant_name = job_id.capitalize()
	c.job_level = 1
	c.job = JobSystem.get_job(job_id)
	if secondary_id != "":
		c.secondary_job = JobSystem.get_job(secondary_id)
		c.secondary_job_id = secondary_id
	return c


func _menu_ids(c: Combatant) -> Array:
	var menu := AbilitiesMenu.new()
	menu.setup(c)
	var ids: Array = []
	for row in menu._abilities_list:
		ids.append(str((row as Dictionary).get("id", "")))
	menu.free()
	return ids


func test_abilities_menu_lists_the_starting_kit_and_the_secondary_kit() -> void:
	var mage := _fresh("mage")
	assert_eq(mage.learned_abilities.size(), 0, "control: a new mage has learned nothing yet")
	var mage_ids := _menu_ids(mage)
	assert_true(mage_ids.has("fire"), "the abilities menu must list Ignis from the mage's starting kit")
	assert_true(mage_ids.has("blizzard") and mage_ids.has("thunder"),
		"the rest of the starting kit must be listed too, got %s" % str(mage_ids))
	assert_false(mage_ids.has("fira"), "a level-6 unlock must stay hidden at job level 1")
	assert_false(mage_ids.has("channel"), "the free-move row stays out of this list; battle already has its own")
	mage.learned_abilities.append("fira")
	assert_true(_menu_ids(mage).has("fira"), "a spell already in learned_abilities must still be listed")
	mage.free()

	var hero := _fresh("fighter", "rogue")
	assert_eq(hero.learned_abilities.size(), 0, "control: the starting hero has learned nothing yet")
	var hero_ids := _menu_ids(hero)
	assert_true(hero_ids.has("power_strike"), "the fighter's own kit must be listed")
	assert_true(hero_ids.has("steal"), "the rogue secondary's base kit must be listed")
	assert_false(hero_ids.has("smoke_bomb"), "the secondary's level unlocks are not lent at level 1")
	hero.free()


func test_party_status_lists_the_starting_kit() -> void:
	var screen := PartyStatusScreen.new()
	add_child_autofree(screen)
	var panel := Control.new()
	screen._detail_panel = panel
	screen.add_child(panel)
	var mage := _fresh("mage")
	screen._build_abilities_column(mage, 0, 0, 240, 800)
	var texts: PackedStringArray = PackedStringArray()
	for child in panel.get_children():
		if child is Label:
			texts.append(str(child.text))
	assert_false(texts.has("— None learned —"),
		"party status must not claim a fresh mage learned nothing, got %s" % str(texts))
	assert_true(texts.has("• Ignis"), "party status must name the starting spell, got %s" % str(texts))
	mage.free()


func test_member_casts_seeds_a_caster_who_knows_the_spell() -> void:
	AutogrindSystem._test_disable_persistence = true
	var ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(ui)
	var fighter := _fresh("fighter")
	var cleric := _fresh("cleric")
	add_child_autofree(fighter)
	add_child_autofree(cleric)
	assert_eq(fighter.learned_abilities.size(), 0)
	assert_eq(cleric.learned_abilities.size(), 0)
	assert_false(fighter.knows_ability("cure"), "control: the lead fighter does not know Cure")
	assert_true(cleric.knows_ability("cure"), "control: Cure is on the cleric's job")
	ui._party = [fighter, cleric]
	var action := {"type": "member_ability"}
	ui._seed_required_action_fields(action)
	assert_eq(str(action.get("member", "")), "cleric",
		"Member Casts must seed the cleric, not the lead fighter, got %s" % str(action))
	assert_eq(str(action.get("ability", "")), "cure",
		"the seeded spell must be Cure, got %s" % str(action))
	assert_true(cleric.knows_ability(str(action.get("ability", ""))))
	assert_true(ui._can_apply_between_battles(str(action.get("ability", ""))),
		"the seeded spell must be one the between-battle cast can actually run")
	AutogrindSystem._test_disable_persistence = false


func test_member_casts_can_offer_the_mages_channel() -> void:
	AutogrindSystem._test_disable_persistence = true
	var ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(ui)
	var mage := _fresh("mage")
	add_child_autofree(mage)
	assert_true(mage.knows_ability("channel"), "control: Channel is the mage's free move")
	assert_eq(mage.learned_abilities.size(), 0)
	ui._party = [mage]
	var act := {"type": "member_ability", "member": "mage", "ability": "fire"}
	ui.rules = [{"conditions": [{"type": "always"}], "actions": [act], "enabled": true}]
	ui.cursor_row = 0
	ui.cursor_col = 1
	ui._cycle_ability_on_cursor_cell()
	assert_eq(str(act.get("ability", "")), "channel",
		"cycling Member Casts on a fresh mage must offer Channel, got %s" % str(act.get("ability", "")))
	assert_true(ui._can_apply_between_battles("channel"))
	AutogrindSystem._test_disable_persistence = false
