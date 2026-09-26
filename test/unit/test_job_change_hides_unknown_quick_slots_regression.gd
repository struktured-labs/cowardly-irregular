extends GutTest

## A kit spell lives on the job, not in learned_abilities. Casting it records an MRU
## shortcut. Changing jobs drops that spell from knows_ability and from the Ability
## submenu, but the command bar still offered it. Confirming spent the turn and
## BattleManager refused with "can't use it right now." The shortcut list is kept,
## so switching back puts the same spell on the bar again. A spell that was actually
## learned stays usable on the new job and must stay on the bar.

const SCENE_PATH := "res://src/battle/BattleScene.gd"
const MenuClass = preload("res://src/battle/BattleCommandMenu.gd")


func before_each() -> void:
	var live_e: Array = []
	for e in BattleManager.enemy_party:
		if is_instance_valid(e):
			live_e.append(e)
	BattleManager.enemy_party.assign(live_e)
	var live_p: Array = []
	for p in BattleManager.player_party:
		if is_instance_valid(p):
			live_p.append(p)
	BattleManager.player_party.assign(live_p)


func test_switching_off_a_job_hides_its_kit_shortcut_and_switching_back_restores_it() -> void:
	var scene = await _scene_with_enemies()
	var c := _hero()
	assert_true(JobSystem.assign_job(c, "mage"), "setup assign mage failed")
	c.record_ability_use("fire")
	assert_false("fire" in c.learned_abilities,
		"Ignis is the mage kit, not a learned spell — that is what makes it leave on a job change")
	assert_true(_top_offers(await _rows(scene, c), "fire"),
		"CONTROL: a mage who just cast Ignis gets it as a command-bar shortcut")
	assert_true(JobSystem.assign_job(c, "fighter"), "switch to fighter failed")
	assert_false(c.knows_ability("fire"), "a fighter does not know the mage kit spell")
	assert_false(JobSystem.can_use_ability(c, "fire"),
		"the battle will refuse Ignis — the bar must not offer a turn that fizzles")
	assert_true(c.recent_abilities.has("fire"),
		"the shortcut memory stays; only the bar hides it")
	assert_false(_top_offers(await _rows(scene, c), "fire"),
		"after leaving mage, Ignis must not sit on the command bar")
	assert_false(_submenu_offers(await _rows(scene, c), "fire"),
		"the Ability submenu already omits Ignis — the bar was the surface that disagreed")
	assert_true(JobSystem.assign_job(c, "mage"), "switch back to mage failed")
	assert_true(c.knows_ability("fire"), "the mage kit returns with the job")
	assert_true(_top_offers(await _rows(scene, c), "fire"),
		"switching back to mage puts the remembered Ignis shortcut on the bar again")


func test_a_learned_spell_stays_on_the_bar_after_a_job_change() -> void:
	var scene = await _scene_with_enemies()
	var c := _hero()
	assert_true(JobSystem.assign_job(c, "fighter"), "setup assign fighter failed")
	assert_true(c.learn_ability("cure"), "Sanatio must be newly learned for this arm")
	c.record_ability_use("cure")
	assert_true(JobSystem.assign_job(c, "rogue"), "switch to rogue failed")
	assert_true(c.knows_ability("cure"), "a learned spell is still known on the new job")
	assert_true(JobSystem.can_use_ability(c, "cure"), "the rogue can actually cast the learned Sanatio")
	assert_true(_top_offers(await _rows(scene, c), "cure"),
		"a spell the character can still cast must stay on the command bar")


func test_clearing_a_secondary_hides_a_shortcut_only_that_job_lent() -> void:
	var scene = await _scene_with_enemies()
	var c := _hero()
	assert_true(JobSystem.assign_job(c, "fighter"), "setup assign fighter failed")
	assert_true(JobSystem.assign_secondary_job(c, "mage"), "setup secondary mage failed")
	assert_true(c.knows_ability("fire"), "CONTROL: the secondary mage kit is castable")
	c.record_ability_use("fire")
	c.secondary_job = null
	c.secondary_job_id = ""
	assert_false(c.knows_ability("fire"), "clearing the secondary takes its kit back")
	assert_false(JobSystem.can_use_ability(c, "fire"))
	assert_true(c.recent_abilities.has("fire"), "clearing the secondary does not wipe shortcut memory")
	assert_false(_top_offers(await _rows(scene, c), "fire"),
		"Ignis lent only by the secondary must leave the command bar when that job is cleared")


func _hero() -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Shortcut"
	c.current_mp = 50
	return c


func _scene_with_enemies() -> Node:
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var enemies: Array = []
	for i in 2:
		var e := Combatant.new()
		add_child_autofree(e)
		e.combatant_name = "Dummy%d" % i
		e.max_hp = 30
		e.current_hp = 30
		e.is_alive = true
		enemies.append(e)
	scene.test_enemies.assign(enemies)
	return scene


func _rows(scene: Node, c: Combatant) -> Array:
	var menu = MenuClass.new(scene)
	return menu.build_command_menu_items_with_targets(c)


func _top_offers(rows: Array, ability_id: String) -> bool:
	for r in rows:
		if not (r is Dictionary):
			continue
		if str(r.get("id", "")) == "ability_menu":
			continue
		if _row_is_ability(r, ability_id):
			return true
	return false


func _submenu_offers(rows: Array, ability_id: String) -> bool:
	for r in rows:
		if r is Dictionary and str(r.get("id", "")) == "ability_menu":
			for sub in r.get("submenu", []):
				if _row_is_ability(sub, ability_id):
					return true
	return false


func _row_is_ability(row: Variant, ability_id: String) -> bool:
	if not (row is Dictionary):
		return false
	var id := str((row as Dictionary).get("id", ""))
	if id == "ability_menu_%s" % ability_id or id == "ability_%s" % ability_id:
		return true
	var data: Variant = (row as Dictionary).get("data", null)
	return data is Dictionary and str((data as Dictionary).get("ability_id", "")) == ability_id
