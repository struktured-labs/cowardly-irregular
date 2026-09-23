extends GutTest

## First visit to a job-combo key goes through Combatant.fork_profile, which
## copies equipment and does not recalculate. JobMenu's secondary-clear arm
## already recalculated after that fork. The primary/secondary assign arm did
## not, so a successful JobSystem.assign_job left the combatant on
## _apply_job_stats' raw caps: no job_level multiplier, no secondary lend, no
## equipment, and no magic_defense (that arm never writes it). A later recalc
## only clamps current HP/MP down; it does not heal the gap the raw fill opened.
##
## These arms drive JobMenu._assign_selected_job onto a profile key that is
## absent, then compare every moddable stat to a second combatant that only
## ran recalculate_stats. The oracle is checked against three ablations
## (no level, no secondary, no weapon) and against the raw caps, so a match
## cannot be the unscaled job line.

const LEVEL := 8
const WEAPON := "iron_sword"
const STATS: Array = Combatant.MODDABLE_STATS


func before_each() -> void:
	assert_not_null(JobSystem, "JobSystem autoload required")
	assert_not_null(EquipmentSystem, "EquipmentSystem autoload required")


func test_fixture_level_weapon_and_lend_fraction_are_live() -> void:
	assert_gt(LEVEL, 1, "job_level must sit above 1 or scaled stats collapse to the raw caps")
	assert_gt(Combatant.SECONDARY_JOB_STAT_FRACTION, 0.0,
		"a zero lend fraction makes the secondary half of every oracle compare a value to itself")
	assert_lt(Combatant.SECONDARY_JOB_STAT_FRACTION, 1.0,
		"the lend is a fraction of the secondary job, not a second primary")
	var atk: int = int(EquipmentSystem.get_weapon(WEAPON).get("stat_mods", {}).get("attack", 0))
	assert_gt(atk, 0, "%s must add attack or the equipment ablation is vacuous" % WEAPON)


func test_first_primary_job_fork_uses_full_recalc_not_raw_caps() -> void:
	var c := _hero("fighter", "rogue")
	var stale_mdf: int = c.magic_defense
	var raw: Dictionary = JobSystem.get_job("mage").get("stat_modifiers", {})
	assert_false(c.job_profiles.has("mage:rogue"), "the combo key must be absent so the menu takes fork_profile")
	_assign_via_menu(c, 0, "mage")
	assert_eq(c.get_profile_key(), "mage:rogue")
	assert_true(c.job_profiles.has("mage:rogue"), "first visit must fork the profile, not skip the swap")
	assert_eq(str(c.job_profiles["mage:rogue"].get("weapon", "")), WEAPON,
		"the fork must carry the equipped weapon into the new combo")
	var oracle := _oracle("mage", "rogue")
	_assert_oracle_beats_raw_and_ablations(oracle, "mage", "rogue")
	_assert_stats(c, oracle)
	assert_ne(c.magic_defense, stale_mdf,
		"magic_defense was left on the previous job — _apply_job_stats never writes it, only recalculate_stats does")
	# assign_job fills current to the raw cap. Recalc clamps; it must not top up to the scaled max.
	assert_eq(c.current_hp, int(raw["max_hp"]),
		"current HP should stay on the job-assign fill (raw cap), not jump to the scaled max")
	assert_lt(c.current_hp, c.max_hp, "level scale opens a max-HP gap the clamp does not heal")
	assert_eq(c.current_mp, int(raw["max_mp"]),
		"current MP should stay on the job-assign fill (raw cap), not jump to the scaled max")
	assert_lt(c.current_mp, c.max_mp, "level scale opens a max-MP gap the clamp does not heal")


func test_first_secondary_job_fork_keeps_lend_and_does_not_heal() -> void:
	# assign_secondary_job already recalculates. This arm still goes through the
	# menu so a fork of fighter:mage lands on the same full expectation, and so
	# the shared post-swap recalc cannot heal the wounded pool.
	var c := _hero("fighter", "")
	var wounded_hp: int = c.current_hp
	var wounded_mp: int = c.current_mp
	assert_false(c.job_profiles.has("fighter:mage"))
	_assign_via_menu(c, 1, "mage")
	assert_eq(c.get_profile_key(), "fighter:mage")
	assert_true(c.job_profiles.has("fighter:mage"), "first secondary must fork")
	var oracle := _oracle("fighter", "mage")
	_assert_oracle_beats_raw_and_ablations(oracle, "fighter", "mage")
	_assert_stats(c, oracle)
	assert_eq(c.current_hp, wounded_hp, "secondary assign must not heal HP")
	assert_eq(c.current_mp, wounded_mp, "secondary assign must not heal MP")
	assert_gt(c.max_hp, c.current_hp)


func test_first_secondary_clear_fork_drops_the_lent_stats() -> void:
	# The clear arm is the path that already recalculated. It now shares the
	# owner with assign, so dropping that call would keep the lend on a new key.
	var c := _hero("fighter", "mage")
	var lent_magic: int = c.magic
	var wounded_hp: int = c.current_hp
	assert_false(c.job_profiles.has("fighter:"))
	_assign_via_menu(c, 1, "__none__")
	assert_eq(c.get_profile_key(), "fighter:")
	assert_eq(c.secondary_job_id, "")
	assert_true(c.job_profiles.has("fighter:"), "clearing onto a new key must fork")
	var oracle := _oracle("fighter", "")
	_assert_oracle_beats_raw_and_ablations(oracle, "fighter", "")
	_assert_stats(c, oracle)
	assert_lt(c.magic, lent_magic, "clearing the secondary must give back the magic it lent")
	assert_eq(c.current_hp, wounded_hp, "clearing a secondary must not heal")


func _hero(primary_id: String, secondary_id: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Fork Hero"
	assert_true(JobSystem.assign_job(c, primary_id), "setup assign %s failed" % primary_id)
	c.job_level = LEVEL
	if secondary_id != "":
		c.secondary_job = JobSystem.get_job(secondary_id).duplicate(true)
		c.secondary_job_id = secondary_id
	c.equipped_weapon = WEAPON
	c.job_profiles.clear()
	c.recalculate_stats()
	c.current_hp = 1
	c.current_mp = 1
	return c


func _oracle(primary_id: String, secondary_id: String, level: int = LEVEL, weapon_id: String = WEAPON) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Oracle"
	c.job = JobSystem.get_job(primary_id).duplicate(true)
	c.job_level = level
	if secondary_id != "":
		c.secondary_job = JobSystem.get_job(secondary_id).duplicate(true)
		c.secondary_job_id = secondary_id
	c.equipped_weapon = weapon_id
	c.recalculate_stats()
	return c


func _assert_oracle_beats_raw_and_ablations(oracle: Combatant, primary_id: String, secondary_id: String) -> void:
	var raw: Dictionary = JobSystem.get_job(primary_id).get("stat_modifiers", {})
	assert_ne(oracle.max_hp, int(raw.get("max_hp", -1)), "oracle max_hp is the raw job cap")
	assert_ne(oracle.attack, int(raw.get("attack", -1)), "oracle attack is the raw job cap")
	assert_ne(oracle.magic_defense, int(raw.get("magic_defense", -1)), "oracle magic_defense is the raw job cap")
	var bare: Combatant = _oracle(primary_id, secondary_id, LEVEL, "")
	assert_gt(oracle.attack, bare.attack, "oracle attack is missing the weapon")
	var at_one: Combatant = _oracle(primary_id, secondary_id, 1, WEAPON)
	assert_gt(oracle.max_hp, at_one.max_hp, "oracle max_hp is missing the job_level multiplier")
	if secondary_id != "":
		var solo: Combatant = _oracle(primary_id, "", LEVEL, WEAPON)
		assert_gt(oracle.magic, solo.magic, "oracle magic is missing the secondary lend")


func _assert_stats(c: Combatant, oracle: Combatant) -> void:
	for stat in STATS:
		assert_eq(int(c.get(stat)), int(oracle.get(stat)),
			"%s is %s; full recalculate_stats (level, secondary lend, equipment) expects %s" % [stat, str(c.get(stat)), str(oracle.get(stat))])


func _assign_via_menu(c: Combatant, slot: int, job_id: String) -> void:
	var menu := JobMenu.new()
	add_child_autofree(menu)
	menu.character = c
	menu.selected_slot = slot
	var jobs: Array = menu._get_available_jobs()
	var idx: int = jobs.find(job_id)
	assert_ne(idx, -1, "job %s missing from slot %d (%s)" % [job_id, slot, str(jobs)])
	if idx < 0:
		return
	menu.selected_job_index = idx
	menu._assign_selected_job()
