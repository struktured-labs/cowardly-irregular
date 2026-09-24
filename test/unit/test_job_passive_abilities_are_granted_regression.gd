extends GutTest

## jobs.json lists passive_abilities on every job, and the battle code
## already applies them once they sit in equipped_passives. assign_job
## and assign_secondary_job never taught or equipped that list, so a
## New Game Bard's songs stayed at the authored duration (Encore), a
## Cleric's Cure ignored Healing Boost and a KO'd Cleric earned no
## posthumous EXP, and a Rogue secondary never lent Steal Boost or
## Evasion Up. The abilities menu lists every passive and refuses an
## unlearned one with "Passive not learned", so the player could not
## turn them on either.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func test_assigning_bard_equips_encore_and_lengthens_songs() -> void:
	var c: Combatant = _make("Lyre")
	assert_eq(c._get_passive_meta_effect_sum("song_duration_bonus"), 0.0,
		"a combatant with no job must not already carry a song bonus")
	assert_true(JobSystem.assign_job(c, "bard"), "assign_job('bard') must succeed")
	assert_true("encore" in c.learned_passives,
		"assigning Bard must teach encore — the abilities menu refuses an unlearned passive")
	assert_true("encore" in c.equipped_passives,
		"the first time Bard is assigned, encore must occupy a free passive slot")
	assert_gt(c._get_passive_meta_effect_sum("song_duration_bonus"), 0.0,
		"an assigned Bard's songs must pick up encore's song_duration_bonus")


func test_assigning_fighter_does_not_grant_encore() -> void:
	var c: Combatant = _make("Blade")
	assert_true(JobSystem.assign_job(c, "fighter"))
	assert_true("weapon_mastery" in c.equipped_passives,
		"the grant must still equip the job's own passive")
	assert_false("encore" in c.learned_passives)
	assert_eq(c._get_passive_meta_effect_sum("song_duration_bonus"), 0.0,
		"Fighter's roster must not lengthen songs")


func test_a_second_assign_does_not_stack_the_passive() -> void:
	var c: Combatant = _make("Lyre")
	assert_true(JobSystem.assign_job(c, "bard"))
	var equipped_before: int = c.equipped_passives.size()
	assert_true(JobSystem.assign_job(c, "bard"))
	assert_eq(c.equipped_passives.count("encore"), 1,
		"assigning Bard twice must not equip encore a second time")
	assert_eq(c.learned_passives.count("encore"), 1,
		"assigning Bard twice must not append a second learned copy")
	assert_eq(c.equipped_passives.size(), equipped_before,
		"a second assign must not grow the equipped bar")


func test_an_already_learned_passive_is_not_forced_back_on() -> void:
	var c: Combatant = _make("Lyre")
	c.learn_passive("encore")
	assert_true(JobSystem.assign_job(c, "bard"))
	assert_false("encore" in c.equipped_passives,
		"a passive the player already knows and left unequipped must stay off across assign and Continue")
	assert_eq(c._get_passive_meta_effect_sum("song_duration_bonus"), 0.0,
		"an unequipped encore must not lengthen songs")


func test_a_full_bar_learns_the_job_passive_without_equipping_it() -> void:
	var c: Combatant = _make("Lyre")
	var fillers: Array[String] = ["weapon_mastery", "hp_boost", "magic_boost", "mp_boost", "speed_boost"]
	for passive_id in fillers:
		c.learn_passive(passive_id)
		assert_true(PassiveSystem.equip_passive(c, passive_id), "filler %s must equip" % passive_id)
	assert_eq(c.equipped_passives.size(), c.max_passive_slots)
	assert_true(JobSystem.assign_job(c, "bard"))
	assert_true("encore" in c.learned_passives,
		"a full bar must still teach the job passive so the player can equip it later")
	assert_false("encore" in c.equipped_passives,
		"a full bar must not evict an equipped passive to make room")
	assert_eq(c.equipped_passives.size(), c.max_passive_slots)


func test_assigning_cleric_equips_healing_boost_and_posthumous_credit() -> void:
	var healer: Combatant = _make("Mira")
	assert_true(JobSystem.assign_job(healer, "cleric"))
	assert_true("healing_boost" in healer.equipped_passives)
	assert_true("posthumous_credit" in healer.equipped_passives)
	healer.current_hp = 10
	assert_eq(healer.heal(40), 60,
		"a Cleric's Healing Boost must turn heal(40) into 60")
	assert_true(BattleManager.earns_exp_while_dead(healer),
		"a Cleric's Posthumous Credit must let them earn EXP while KO'd")

	var blade: Combatant = _make("Blade")
	assert_true(JobSystem.assign_job(blade, "fighter"))
	blade.current_hp = 10
	assert_eq(blade.heal(40), 40,
		"a Fighter must not inherit the Cleric heal bonus")
	assert_false(BattleManager.earns_exp_while_dead(blade),
		"a Fighter must not earn EXP while KO'd")


func test_secondary_rogue_lends_steal_boost_and_evasion_up() -> void:
	var c: Combatant = _make("Blade")
	assert_true(JobSystem.assign_job(c, "fighter"))
	assert_true(JobSystem.assign_secondary_job(c, "rogue"))
	assert_true("steal_boost" in c.learned_passives)
	assert_true("evasion_up" in c.learned_passives)
	assert_true("steal_boost" in c.equipped_passives,
		"a Rogue secondary must equip Steal Boost when a slot is free")
	assert_true("evasion_up" in c.equipped_passives,
		"a Rogue secondary must equip Evasion Up when a slot is free")
	var mods: Dictionary = PassiveSystem.get_passive_mods(c)
	assert_gt(float(mods.get("steal_chance", 0.0)), 0.0,
		"Steal Boost must raise steal_chance once the secondary is assigned")
	assert_gt(float(mods.get("evasion", 0.0)), 0.0,
		"Evasion Up must raise evasion once the secondary is assigned")
	assert_eq(c.equipped_passives.count("weapon_mastery"), 1,
		"lending the secondary must not duplicate the primary's passive")
