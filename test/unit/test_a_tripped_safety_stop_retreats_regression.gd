extends GutTest

## struktured, preview: "I had any hp < 30 stop grinding and somehow had whole party dead". The rule was only asked BETWEEN
## battles, so a fight entered above 30% wiped inside one round. His ruling: when a stop rule trips mid-battle the party
## RETREATS — one escape try per round (Flee's own odds, refused against a boss), everyone else heals the weakest or Defers —
## and the grind stops after the fight with the reason named.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const CTRL := "res://src/autogrind/AutogrindController.gd"

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	BattleManager.autogrind_retreat = false
	BattleManager._retreat_escape_round = -1


func after_each() -> void:
	BattleManager.autogrind_retreat = false
	BattleManager._retreat_escape_round = -1
	BattleManager.escape_allowed = true
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)


func _member(name: String, hp_pct: float, job_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name
	add_child_autofree(c)
	if job_id != "":
		c.job = JobSystem.get_job(job_id)
		c.job_level = 10
		c.recalculate_stats()
	else:
		c.max_hp = 100
	c.current_hp = maxi(1, int(c.max_hp * hp_pct))
	c.current_mp = c.max_mp
	c.is_alive = true
	return c


func test_a_member_under_the_safety_line_names_the_retreat() -> void:
	AutogrindSystem.set_interrupt_rules({"hp_threshold": 30.0})
	AutogrindSystem.set_autogrind_rules([])
	var cleric := _member("Cleric", 0.22)
	assert_string_contains(AutogrindSystem.safety_retreat_reason([_member("Fighter", 0.9), cleric]), "Cleric 22% HP",
		"a member under the safety line must turn the party to retreat, named")
	assert_eq(AutogrindSystem.safety_retreat_reason([_member("Fighter", 0.9), _member("Mage", 0.5)]), "",
		"CONTROL: nobody under the line, nothing changes")


func test_his_own_stop_rule_trips_it_too() -> void:
	AutogrindSystem.set_interrupt_rules({"hp_threshold": 0.0})
	assert_true(AutogrindSystem.set_autogrind_rules([{"conditions": [{"type": "member_hp", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}], "enabled": true}]), "CONTROL: his rule is valid")
	assert_string_contains(AutogrindSystem.safety_retreat_reason([_member("Rogue", 0.2)]), "rule #1",
		"the rule he wrote, member_hp < 30 → stop, must trip mid-battle")


func test_one_escape_try_per_round_then_heal_or_defer() -> void:
	BattleManager.escape_allowed = true
	BattleManager.current_round = 3
	var hurt := _member("Rogue", 0.3)
	var cleric := _member("Cleric", 0.9, "cleric")
	var first: Dictionary = BattleManager._retreat_action(cleric, [hurt, cleric])
	assert_eq(str(first.get("type")), "retreat", "the first to act in a round tries to escape")
	var second: Dictionary = BattleManager._retreat_action(cleric, [hurt, cleric])
	assert_ne(str(second.get("type")), "retreat", "one escape try per round")
	assert_eq(str(second.get("type")), "ability", "a Cleric who can heal heals")
	assert_true(hurt in (second.get("targets", []) as Array), "and heals the weakest")
	var fighter := _member("Fighter", 0.9, "fighter")
	assert_eq(str(BattleManager._retreat_action(fighter, [hurt, fighter]).get("type")), "defer", "one who cannot heal Defers")
	BattleManager.current_round = 4
	assert_eq(str(BattleManager._retreat_action(fighter, [hurt, fighter]).get("type")), "retreat", "a failed escape is retried next round")


func test_a_boss_fight_never_tries_to_escape() -> void:
	BattleManager.escape_allowed = false
	BattleManager.current_round = 1
	var fighter := _member("Fighter", 0.9, "fighter")
	for i in 3:
		assert_ne(str(BattleManager._retreat_action(fighter, [fighter]).get("type")), "retreat", "no escape is attempted where none is allowed")


func test_a_retreat_that_got_away_stops_the_grind_with_its_reason() -> void:
	var ctrl: Node = load(CTRL).new()
	add_child_autofree(ctrl)
	ctrl._party = [_member("Fighter", 0.6)]
	ctrl._state = ctrl.State.BATTLE_RUNNING
	watch_signals(ctrl)
	ctrl.request_safety_retreat("Safety stop: retreated at Cleric 22% HP")
	ctrl.on_battle_ended(false)
	## An escape after a safety stop is not "Party defeated": the grind stops with the reason that sent it home.
	assert_signal_emitted_with_parameters(ctrl, "grind_complete", ["Safety stop: retreated at Cleric 22% HP"])


## Ludicrous (headless) grinds never take party turns, so the resolver asks the same check each round and retreats on its own.
func _headless_fight(enemy_type: String, seed_value: int) -> Dictionary:
	seed(seed_value)
	var r = HeadlessBattleResolver.new()
	r.safety_check = func(_p: Array) -> String: return "Safety stop: retreated at Bard 9% HP"
	var party: Array = [_member("Fighter", 0.9, "fighter")]
	var foe := Combatant.new()
	foe.combatant_name = enemy_type
	foe.max_hp = 9999
	foe.current_hp = 9999
	foe.attack = 1
	foe.is_alive = true
	foe.set_meta("monster_type", enemy_type)
	add_child_autofree(foe)
	var result: Dictionary = r.resolve_battle(party, [foe])
	result["reason_seen"] = r.retreat_reason
	return result


func test_a_headless_grind_retreats_on_its_own() -> void:
	var escaped := 0
	for s in 12:
		var res := _headless_fight("goblin", 100 + s)
		assert_eq(str(res.get("reason_seen", "")), "Safety stop: retreated at Bard 9% HP", "CONTROL: the resolver asked the check and kept its reason")
		if str(res.get("termination_reason", "")) == "retreat":
			escaped += 1
			assert_false(bool(res.get("victory", true)), "an escape is not a win")
	assert_gt(escaped, 6, "at Flee's 75%%, most of 12 tripped fights must end in a retreat (got %d)" % escaped)


func test_a_headless_boss_fight_is_never_fled() -> void:
	for s in 6:
		assert_ne(str(_headless_fight("chancellor_mordaine", 200 + s).get("termination_reason", "")), "retreat",
			"a boss fight must not be fled, in a fast grind as in a watched one")
