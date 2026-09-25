extends GutTest

## Warden and Arbiter tilts are baked into defense, max HP, and attack inside
## recalculate_stats. Equipping or handing off a Lens only wrote the assignment,
## so the status screen and the next fight kept the old numbers — and taking
## the Lens off left the bonus in place until some unrelated recalc.

const _DEF_BASE := 1000
const _HP_BASE := 1000


class _PartyHost:
	extends Node
	var party: Array = []


var _saved_recipes: Array[String] = []
var _saved_owned: Array[String] = []
var _saved_assign: Dictionary = {}
var _host: Node = null


func before_each() -> void:
	_saved_recipes = GameState.unlocked_lens_recipes.duplicate()
	_saved_owned = GameState.owned_lenses.duplicate()
	_saved_assign = GameState.lens_assignments.duplicate()
	GameState.unlocked_lens_recipes.clear()
	GameState.owned_lenses.clear()
	GameState.lens_assignments.clear()
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"a GameLoop is already in the tree — this test would refresh the wrong party")
	_host = _PartyHost.new()
	_host.name = "GameLoop"
	get_tree().root.add_child(_host)


func after_each() -> void:
	GameState.unlocked_lens_recipes = _saved_recipes
	GameState.owned_lenses = _saved_owned
	GameState.lens_assignments = _saved_assign
	if _host != null and is_instance_valid(_host):
		_host.free()
		_host = null


func test_equipping_the_warden_lens_changes_defense_and_hp_immediately() -> void:
	var fighter := _member("Fighter")
	var defense_before: int = fighter.defense
	var hp_before: int = fighter.max_hp
	GameState.owned_lenses.append("warden")
	assert_true(LensSystem.equip_lens("fighter", "warden"))
	var mult: float = _tilt("warden", "defense_multiplier")
	var hp_mult: float = _tilt("warden", "max_hp_multiplier")
	assert_eq(fighter.defense, int(defense_before * mult),
		"wearing the Warden Lens must raise the defense the status screen and battles read")
	assert_eq(fighter.max_hp, int(hp_before * hp_mult),
		"and the max HP, which is baked in the same pass")
	assert_true(LensSystem.unequip_lens("fighter"))
	assert_eq(fighter.defense, defense_before,
		"taking the Lens off must drop defense back — the bonus must not stick")
	assert_eq(fighter.max_hp, hp_before,
		"and max HP with it")


func test_moving_the_lens_moves_the_baked_bonus() -> void:
	var fighter := _member("Fighter")
	var cleric := _member("Cleric")
	var fighter_before: int = fighter.defense
	var cleric_before: int = cleric.defense
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	var mult: float = _tilt("warden", "defense_multiplier")
	assert_eq(fighter.defense, int(fighter_before * mult),
		"the Fighter's defense must include the Warden tilt as soon as the Lens is worn")
	assert_eq(cleric.defense, cleric_before,
		"a Lens on the Fighter must not raise the Cleric")
	LensSystem.equip_lens("cleric", "warden")
	assert_eq(fighter.defense, fighter_before,
		"the previous wearer loses the defense when the Lens moves")
	assert_eq(cleric.defense, int(cleric_before * mult),
		"the new wearer gains it in the same step")


func test_the_arbiter_lens_changes_attack_once() -> void:
	var fighter := _member("Fighter")
	fighter.base_attack = _DEF_BASE
	fighter.recalculate_stats()
	var attack_before: int = fighter.attack
	GameState.owned_lenses.append("arbiter")
	assert_true(LensSystem.equip_lens("fighter", "arbiter"))
	var mult: float = _tilt("arbiter", "attack_multiplier")
	var tilted: int = int(attack_before * mult)
	assert_eq(fighter.attack, tilted,
		"wearing the Arbiter Lens must raise the attack battles read")
	assert_true(LensSystem.equip_lens("fighter", "arbiter"))
	fighter.recalculate_stats()
	assert_eq(fighter.attack, tilted,
		"equipping the same Lens again and recalculating must not stack the tilt")
	assert_true(LensSystem.unequip_lens("fighter"))
	assert_eq(fighter.attack, attack_before,
		"taking the Arbiter Lens off must drop attack back")


func test_a_lens_without_a_stat_tilt_leaves_baked_stats_alone() -> void:
	var fighter := _member("Fighter")
	var defense_before: int = fighter.defense
	var hp_before: int = fighter.max_hp
	var attack_before: int = fighter.attack
	GameState.owned_lenses.append("tempo")
	GameState.owned_lenses.append("curator")
	assert_true(LensSystem.equip_lens("fighter", "tempo"))
	assert_eq(fighter.defense, defense_before)
	assert_eq(fighter.max_hp, hp_before)
	assert_eq(fighter.attack, attack_before)
	assert_true(LensSystem.equip_lens("fighter", "curator"))
	assert_eq(fighter.defense, defense_before,
		"Tempo and Curator have no stat tilt, so equipping them must not move defense")
	assert_eq(fighter.max_hp, hp_before)
	assert_eq(fighter.attack, attack_before)


func test_recalculate_and_level_up_apply_the_tilt_once() -> void:
	var fighter := _member("Fighter")
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	var mult: float = _tilt("warden", "defense_multiplier")
	var once: int = int(_DEF_BASE * mult)
	assert_eq(fighter.defense, once)
	fighter.recalculate_stats()
	fighter.recalculate_stats()
	assert_eq(fighter.defense, once,
		"a second and third recalculation must not stack the Warden tilt")
	fighter.gain_job_exp(fighter.job_level * 100)
	assert_eq(fighter.job_level, 2)
	var level_mult := 1.0 + float(fighter.job_level - 1) * 0.04
	var leveled: int = int(int(_DEF_BASE * level_mult) * mult)
	assert_eq(fighter.defense, leveled,
		"a level-up recalculation includes the tilt once, on the new level")
	fighter.recalculate_stats()
	assert_eq(fighter.defense, leveled)


func test_equipping_does_not_heal_and_unequipping_clamps_hp() -> void:
	var fighter := _member("Fighter")
	fighter.current_hp = fighter.max_hp
	var full: int = fighter.current_hp
	var max_before: int = fighter.max_hp
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	assert_gt(fighter.max_hp, max_before)
	assert_eq(fighter.current_hp, full,
		"the extra max HP is room — equipping must not heal current HP")
	fighter.current_hp = fighter.max_hp
	LensSystem.unequip_lens("fighter")
	assert_eq(fighter.max_hp, max_before)
	assert_eq(fighter.current_hp, max_before,
		"current HP above the restored max must be cut back to it")
	fighter.current_hp = 400
	LensSystem.equip_lens("fighter", "warden")
	assert_eq(fighter.current_hp, 400,
		"a wounded wearer stays wounded when max HP rises")
	LensSystem.unequip_lens("fighter")
	assert_eq(fighter.current_hp, 400,
		"and stays wounded when the Lens comes off, as long as they are under the new max")
	assert_true(fighter.is_alive)


func test_a_job_change_keeps_the_lens_tilt_once() -> void:
	var fighter := _member("Fighter")
	_change_job(fighter, "fighter")
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	var defense_worn: int = fighter.defense
	var hp_worn: int = fighter.max_hp
	var mult: float = _tilt("warden", "defense_multiplier")
	var hp_mult: float = _tilt("warden", "max_hp_multiplier")
	var job_mods: Dictionary = JobSystem.get_job("fighter").get("stat_modifiers", {})
	assert_eq(defense_worn, int(int(job_mods["defense"]) * mult),
		"the baked defense is the job's defense with the Warden tilt applied once")
	assert_eq(hp_worn, int(int(job_mods["max_hp"]) * hp_mult),
		"and max HP the same way")
	_change_job(fighter, "mage")
	_change_job(fighter, "fighter")
	assert_eq(fighter.defense, defense_worn,
		"changing jobs and coming back must still include the Warden tilt once")
	assert_eq(fighter.max_hp, hp_worn)
	assert_lte(fighter.current_hp, fighter.max_hp)
	fighter.recalculate_stats()
	assert_eq(fighter.defense, defense_worn)
	assert_eq(fighter.max_hp, hp_worn)


func test_loading_a_save_with_the_lens_equipped_includes_the_bonus_once() -> void:
	var fighter := _member("Fighter")
	JobSystem.assign_job(fighter, "fighter")
	fighter.recalculate_stats()
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	fighter.current_hp = fighter.max_hp
	var worn_defense: int = fighter.defense
	var worn_hp: int = fighter.max_hp
	var saved_who: Dictionary = JSON.parse_string(JSON.stringify(fighter.to_dict()))
	var saved_assign: Dictionary = JSON.parse_string(JSON.stringify(GameState.lens_assignments))
	GameState.lens_assignments.clear()
	var again := Combatant.new()
	add_child(again)
	again.from_dict(saved_who)
	_host.party.append(again)
	for char_id in saved_assign:
		GameState.lens_assignments[str(char_id)] = str(saved_assign[char_id])
	assert_true(JobSystem.assign_job(again, str(saved_who.get("job_id", "fighter"))))
	again.recalculate_stats()
	again.current_hp = clampi(int(saved_who["current_hp"]), 0, again.max_hp)
	assert_eq(again.defense, worn_defense,
		"after load, defense includes the equipped Lens once")
	assert_eq(again.max_hp, worn_hp,
		"and max HP does too")
	assert_eq(again.current_hp, worn_hp)
	assert_lte(again.current_hp, again.max_hp)
	again.recalculate_stats()
	assert_eq(again.defense, worn_defense,
		"recalculating after load must not stack the tilt")
	assert_eq(again.max_hp, worn_hp)


func _tilt(axis: String, key: String) -> float:
	var mods: Dictionary = LensSystem.get_lens(axis).get("stat_mods", {})
	return float(mods.get(key, 1.0))


func _change_job(c: Combatant, job_id: String) -> void:
	var menu := JobMenu.new()
	add_child_autofree(menu)
	menu.character = c
	menu.selected_slot = 0
	var jobs: Array = menu._get_available_jobs()
	var idx: int = jobs.find(job_id)
	assert_ne(idx, -1, "job %s missing from the menu (%s)" % [job_id, str(jobs)])
	menu.selected_job_index = idx
	menu._assign_selected_job()


func _member(who: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.base_defense = _DEF_BASE
	c.base_max_hp = _HP_BASE
	add_child(c)
	c.recalculate_stats()
	_host.party.append(c)
	return c
