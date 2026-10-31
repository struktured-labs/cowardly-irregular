extends GutTest

## The Rogue's default script named steal an OPENER in its own comment ("grab items from a healthy
## enemy at fight start") and gated it only on `enemy_hp_percent > 75`. A boss HP pool keeps that
## true for the whole battle, so first-match-wins re-picked steal every round and the backstab rule
## beneath it was unreachable: measured against Mordaine (16500 HP) in the balance harness, the Rogue
## stole gold for five straight rounds and dealt ZERO damage while the party was wiped.
##
## The Bard's battle_hymn and the Speculator's forecast openers already carry `turn <= 1`; this file
## pins that the Rogue's does too, BEHAVIOURALLY -- a source assert that the condition is spelled in
## the dict would certify spelling, not that the rule stops firing.
##
## The mutation arm is load-bearing: steal is stochastic (success_rate 0.5) and both outcomes log, so
## the counter here counts ATTEMPTS. Without an arm that strips the gate and watches the count climb,
## "attempts <= 1" is also what a Rogue who can never steal at all reports.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

## Boss-shaped: HP it cannot be dented out of 75%, attack that cannot kill the Rogue inside
## MAX_ROUNDS. Both halves are what hold the broken condition true for a long battle.
const BOSS_HP := 2000000
const BOSS_ATTACK := 1


func _abs_node() -> Node:
	return get_node_or_null("/root/AutobattleSystem")


func before_each() -> void:
	var ab := _abs_node()
	if ab != null and "_test_disable_persistence" in ab:
		ab._test_disable_persistence = true


func _rogue() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Rogue"
	c.job_level = 20
	add_child_autofree(c)
	var js: Node = get_node_or_null("/root/JobSystem")
	if js != null and js.has_method("assign_job"):
		js.assign_job(c, "rogue")
	c.recalculate_stats()
	c.max_mp = 9999
	c.current_mp = c.max_mp
	c.current_hp = c.max_hp
	c.is_alive = true
	return c


func _boss() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Standing Order", "max_hp": BOSS_HP, "max_mp": 0,
		"attack": BOSS_ATTACK, "defense": 10, "magic": 0, "speed": 1})
	add_child_autofree(c)
	c.current_hp = BOSS_HP
	c.is_alive = true
	return c


## Both outcomes of a steal roll, so the count is of the RULE FIRING rather than of its luck.
func _steal_attempts(log_lines: Array) -> int:
	var n := 0
	for line in log_lines:
		var s := str(line)
		if s.begins_with("Rogue steals ") or s.begins_with("Rogue fails to steal "):
			n += 1
	return n


func _run_battle() -> Dictionary:
	var resolver = ResolverScript.new()
	return resolver.resolve_battle([_rogue()], [_boss()])


func test_the_rogue_can_steal_at_all() -> void:
	## FLOOR, and it is what separates a working gate from a Rogue who never reaches the rule: the
	## kit must hold steal and the script must hold a steal action, or every count below is 0 for a
	## reason that has nothing to do with the turn gate.
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null:
		pass_test("JobSystem autoload unavailable")
		return
	var rogue := _rogue()
	assert_true(rogue.knows_ability("steal"), "the Rogue kit no longer holds steal — the arms below would measure nothing")
	var ab := _abs_node()
	assert_not_null(ab, "AutobattleSystem autoload absent — no script drives the Rogue")
	var script: Dictionary = ab.get_character_script("rogue")
	var steal_rules := 0
	for rule in script.get("rules", []):
		for action in (rule as Dictionary).get("actions", []):
			if str((action as Dictionary).get("id", "")) == "steal":
				steal_rules += 1
	assert_eq(steal_rules, 1, "the Rogue default script should carry exactly one steal rule")


func test_the_rogue_steals_once_not_all_fight() -> void:
	var ab := _abs_node()
	if ab == null or get_node_or_null("/root/JobSystem") == null:
		pass_test("autoloads unavailable")
		return
	var result := _run_battle()
	var attempts := _steal_attempts(result.get("log", []) as Array)
	assert_eq(attempts, 1, "steal is an OPENER: it fired %d times across %d rounds against a boss-HP target" % [
		attempts, int(result.get("rounds", 0))])
	assert_gt(int(result.get("rounds", 0)), 3, "CONTROL: the battle must outlast the opener, or one attempt is trivially all there was")


func test_without_the_turn_gate_steal_fires_every_round() -> void:
	## MUTATION: strip `turn` from the shipped script and the same counter must climb. This is the
	## only arm that proves the assertion above is about the gate rather than about a Rogue who
	## cannot steal, and it reproduces exactly the shape measured against Mordaine.
	var ab := _abs_node()
	if ab == null or get_node_or_null("/root/JobSystem") == null:
		pass_test("autoloads unavailable")
		return
	var script: Dictionary = ab.get_character_script("rogue").duplicate(true)
	var stripped := 0
	for rule in script.get("rules", []):
		var r: Dictionary = rule
		var holds_steal := false
		for action in r.get("actions", []):
			if str((action as Dictionary).get("id", "")) == "steal":
				holds_steal = true
		if not holds_steal:
			continue
		var kept: Array = []
		for cond in r.get("conditions", []):
			if str((cond as Dictionary).get("type", "")) == "turn":
				stripped += 1
				continue
			kept.append(cond)
		r["conditions"] = kept
	assert_eq(stripped, 1, "nothing to strip — the shipped steal rule carries no turn condition, which IS the defect")
	ab.set_character_script("rogue", script)
	var result := _run_battle()
	var attempts := _steal_attempts(result.get("log", []) as Array)
	assert_gt(attempts, 1, "with the gate removed steal must fire repeatedly, else the counter cannot see the defect")
