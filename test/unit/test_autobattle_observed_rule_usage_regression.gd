extends GutTest

## The observed half of Simulate.
##
## Simulate answers "what SHOULD this grid do". Nothing answered "what DID it do", and every
## autogrind defect found on 2026-09-09/10 was invisible for that one reason: a frozen turn
## counter that killed seven shipped openers, three ap<0 rules dead by construction, a revival
## rule that could not be targeted. In all of them the grid looked right and simply never ran.
##
## The counters ride the real selector — execute_grid_autobattle, the same call the resolver
## makes — so they cannot drift from what actually executed.
##
## THE DENOMINATOR IS THE DESIGN. "fired 0 times" is evidence of a dead rule only when turns > 0;
## across zero turns it means "not measured yet". Reporting a bare zero would manufacture exactly
## the false alarm this panel exists to prevent, which is the failure mode I hit three times in
## two days by believing a zero whose precondition was never instantiated.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _abs: Node = null
var _cid: String = ""


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_cid = ""


func after_each() -> void:
	if _abs and _cid != "":
		_abs.character_profiles.erase(_cid)
		_abs.reset_rule_fire_counts(_cid)


func _hero(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": 400, "max_mp": 60,
		"attack": 20, "defense": 30, "magic": 20, "speed": 12})
	add_child_autofree(c)
	return c


func _foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": "Observed Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(e)
	return e


func _install(hero: Combatant, rules: Array) -> void:
	_cid = hero.combatant_name.to_lower().replace(" ", "_")
	_abs.reset_rule_fire_counts(_cid)
	_abs.set_character_script(_cid, {"rules": rules})


func test_a_rule_that_runs_is_counted_and_one_that_cannot_stays_zero() -> void:
	var hero := _hero("Observed Hero")
	## Rule 0 needs three enemies and there is one, so it can never match. Rule 1 always does.
	## A counter that merely incremented something would fail this pair.
	_install(hero, [
		{"enabled": true, "conditions": [{"type": "enemy_count", "op": ">=", "value": 3}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	])
	assert_eq(_abs.get_rule_eval_count(_cid), 0, "precondition: nothing observed before the fight")

	var resolver := HeadlessBattleResolver.new()
	var result: Dictionary = resolver.resolve_battle([hero], [_foe()])
	var rounds: int = int(result.get("rounds", 0))
	assert_gt(rounds, 1, "precondition: the battle ran enough turns to observe")

	var counts: Dictionary = _abs.get_rule_fire_counts(_cid)
	assert_eq(int(counts.get(0, 0)), 0,
		"a rule requiring three enemies must never fire against one — a counter that credits the wrong rule would show this non-zero")
	assert_eq(int(counts.get(1, 0)), rounds,
		"the always-rule fired once per turn, so its count must equal the battle's round count")
	assert_eq(_abs.get_rule_eval_count(_cid), rounds,
		"the denominator must equal the turns the script was consulted")


func test_the_readout_names_a_dead_rule_and_carries_its_denominator() -> void:
	var hero := _hero("Readout Hero")
	_install(hero, [
		{"enabled": true, "conditions": [{"type": "enemy_count", "op": ">=", "value": 3}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	])
	var resolver := HeadlessBattleResolver.new()
	resolver.resolve_battle([hero], [_foe()])

	var e: Node = load(EDITOR).new()
	e.character_id = _cid
	e.character_name = hero.combatant_name
	add_child_autofree(e)
	var lines: Array = e._observed_report(_abs.get_character_script(_cid).get("rules", []))
	var blob: String = "\n".join(PackedStringArray(lines))

	assert_true(blob.contains("rule 1  never fired"),
		"the rule that cannot match must be NAMED as never fired — that is the whole point: %s" % blob)
	## Both halves, or a counter stuck at zero passes by reporting EVERY rule dead.
	assert_true(blob.contains("rule 2  fired"),
		"the rule that ran every turn must be reported as fired, not silently lumped in with the dead one: %s" % blob)
	assert_true(blob.contains("OBSERVED"),
		"the block must be labelled so it is not mistaken for the simulated prediction above it")
	assert_true(blob.contains("turns this session"),
		"a zero without its denominator is not evidence — the turn count must be on screen: %s" % blob)


func test_zero_turns_reports_NOT_MEASURED_rather_than_a_dead_rule() -> void:
	## The honesty property. Opening Simulate before fighting must not accuse every rule of being
	## dead — a zero whose precondition was never instantiated is the exact false alarm this
	## feature would otherwise create at scale.
	var hero := _hero("Fresh Hero")
	_install(hero, [
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	])
	var e: Node = load(EDITOR).new()
	e.character_id = _cid
	e.character_name = hero.combatant_name
	add_child_autofree(e)
	var blob: String = "\n".join(PackedStringArray(e._observed_report(
		_abs.get_character_script(_cid).get("rules", []))))

	assert_false(blob.contains("never fired"),
		"with no turns recorded, no rule may be reported dead: %s" % blob)
	assert_true(blob.contains("no turns recorded yet"),
		"it must say it has not measured anything, rather than showing zeros: %s" % blob)


func test_the_counters_are_per_character() -> void:
	## character_id keys the store; two characters sharing a counter would report each other's
	## fights and make a live rule look dead on the character that never ran it.
	var a := _hero("Split Alpha")
	_install(a, [{"enabled": true, "conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}])
	var resolver := HeadlessBattleResolver.new()
	resolver.resolve_battle([a], [_foe()])
	var alpha_turns: int = _abs.get_rule_eval_count(_cid)
	var alpha_id: String = _cid

	assert_gt(alpha_turns, 0, "precondition: alpha actually fought")
	assert_eq(_abs.get_rule_eval_count("split_beta"), 0,
		"a character who never fought must report zero turns, not alpha's")
	_abs.reset_rule_fire_counts(alpha_id)
	assert_eq(_abs.get_rule_eval_count(alpha_id), 0, "reset must clear the character it names")


func test_editing_the_grid_discards_counts_that_would_describe_other_rules() -> void:
	## Counts are keyed by rule INDEX. Insert a rule at the top and every stored count now names
	## a different rule — the readout would report confident numbers about rules that never ran
	## them. A stale count is worse than no count, because it reads as evidence.
	var hero := _hero("Renumber Hero")
	_install(hero, [
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	])
	var resolver := HeadlessBattleResolver.new()
	resolver.resolve_battle([hero], [_foe()])
	assert_gt(_abs.get_rule_eval_count(_cid), 0, "precondition: counts exist before the edit")

	_abs.set_character_script(_cid, {"rules": [
		{"enabled": true, "conditions": [{"type": "hp_percent", "op": "<", "value": 20}],
		 "actions": [{"type": "item", "id": "potion", "target": "self"}]},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	]})

	assert_eq(_abs.get_rule_eval_count(_cid), 0,
		"editing the grid must discard the observed counts — they were measured against the old numbering")
	assert_eq(_abs.get_rule_fire_counts(_cid).size(), 0,
		"per-rule counts must go too, not just the denominator")
