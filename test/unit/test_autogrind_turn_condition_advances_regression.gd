extends GutTest

## SELECTION, not execution. The song and mp_restore arms in HeadlessBattleResolver are proven by
## tests that call _resolve_ability directly — which cannot see whether a grind ever ASKS for them.
## Asking cowir-main's standing question of my own two fixes ("who selects it, and can they?") found
## the selector reading a counter nobody advances.
##
## `turn` (AutobattleSystem:249) and the legacy TURN_COUNT (:1904) both read
## BattleManager.current_round. That field has exactly two writers, BattleManager:380 (reset) and
## :1259 (increment), both on the LIVE path. HeadlessBattleResolver counts in its own _current_round
## and never mirrors it, so during a grind `turn` is frozen at whatever the last live battle left —
## 0 on a fresh boot. Every turn-gated rule is then permanently false or permanently true, and which
## one you get depends on unrelated earlier play.
##
## This is not hypothetical: three shipped Bard templates gate battle_hymn on `turn == 1`, so the
## catalog's own opener never fires in a grind. GameLoop's console summary and dashboard read the
## same field for "(%d rounds)", so every autogrind battle also reports a stale round count.

var _abs: Node = null
var _bm: Node = null
var _round_before: int = 0
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_bm = get_node_or_null("/root/BattleManager")
	if _bm:
		_round_before = _bm.current_round
	_fixture_ids.clear()


func after_each() -> void:
	if _bm:
		_bm.current_round = _round_before
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _combatant(cname: String, job_id: String = "") -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 500, "max_mp": 60,
		"attack": 12, "defense": 50, "magic": 20, "speed": 10
	})
	if job_id != "":
		c.job = JobSystem.get_job(job_id)
		c.job_level = 1
	add_child_autofree(c)
	return c


func _punching_bag() -> Combatant:
	## Survives 50 rounds and cannot kill a 500 HP party — the battle stalemates by construction,
	## so round count is fixed and nothing here rides on a damage roll.
	var e := Combatant.new()
	e.initialize({
		"name": "Turnprobe Dummy", "max_hp": 999999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1
	})
	add_child_autofree(e)
	return e


func _install(caster: Combatant, rule: Dictionary) -> void:
	var cid: String = caster.combatant_name.to_lower().replace(" ", "_")
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"rules": [rule]})


func _shipped_rule_casting(ability_id: String) -> Dictionary:
	## Derived from the shipped catalog, never a copy of it: a test that restates the rule stops
	## measuring the rule players actually run the moment the catalog moves.
	var f := FileAccess.open("res://data/autobattle_rule_templates.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	for tmpl in (parsed as Dictionary).get("templates", []):
		if not (tmpl is Dictionary):
			continue
		for rule in (tmpl as Dictionary).get("rules", []):
			if not (rule is Dictionary):
				continue
			for act in (rule as Dictionary).get("actions", []):
				if act is Dictionary and str(act.get("type", "")) == "ability" \
						and str(act.get("id", "")) == ability_id:
					return rule
	return {}


func _count_lines_naming(log: Array, needle: String) -> int:
	var n := 0
	for line in log:
		if str(line).contains(needle):
			n += 1
	return n


func _count_casts(log: Array, ability_id: String, a_target: String) -> int:
	## The song arm logs once PER TARGET, so an all_allies song writes one line per party member
	## and a naive ability-name count reads party size as cast count. Counting lines that name one
	## fixed target counts casts.
	var n := 0
	for line in log:
		var s := str(line)
		if s.contains(ability_id) and s.contains(a_target):
			n += 1
	return n


func test_the_shipped_bard_opener_actually_fires_in_a_grind() -> void:
	## Catalog templates 12/13/14: {turn == 1, mp_percent >= 15} -> ability battle_hymn.
	var rule := _shipped_rule_casting("battle_hymn")
	assert_false(rule.is_empty(),
		"precondition: the shipped catalog must still contain a battle_hymn rule to measure")
	var gates: Array = []
	for c in rule.get("conditions", []):
		gates.append(str((c as Dictionary).get("type", "")))
	assert_true(gates.has("turn"),
		"precondition: the rule under test must be turn-gated — found conditions %s" % [gates])

	var bard := _combatant("Turnprobe Bard", "bard")
	assert_true(bard.knows_ability("battle_hymn"),
		"precondition: the Bard fixture must actually know the song being selected")
	var ally := _combatant("Turnprobe Ally")
	_install(bard, rule)

	var resolver := HeadlessBattleResolver.new()
	var result: Dictionary = resolver.resolve_battle([bard, ally], [_punching_bag()])
	var log: Array = result.get("log", [])
	assert_gt(log.size(), 0, "precondition: the battle produced a log to read")

	assert_eq(_count_casts(log, "battle_hymn", "Turnprobe Ally"), 1,
		"a `turn == 1` opener must fire exactly once in a grind — 0 means the condition is frozen false, >1 means it is frozen true and the Bard re-casts an 8 MP song every round")
	assert_eq(_count_lines_naming(log, "battle_hymn"), 2,
		"the one cast must reach BOTH party members — all_allies expansion is what makes it a party buff rather than a self-buff, and it is the reason a per-target line count is not a cast count")


func test_a_later_turn_gate_is_false_early_and_true_later() -> void:
	## ARM+ against fixing this by pinning the counter to 1: that would pass the test above and
	## still leave every other turn threshold unreachable.
	var bard := _combatant("Turnlate Bard", "bard")
	var ally := _combatant("Turnlate Ally")
	_install(bard, {
		"conditions": [{"type": "turn", "op": ">=", "value": 3}],
		"actions": [{"type": "ability", "id": "battle_hymn", "target": "all_allies"}],
		"enabled": true,
	})

	var resolver := HeadlessBattleResolver.new()
	var result: Dictionary = resolver.resolve_battle([bard, ally], [_punching_bag()])
	var log: Array = result.get("log", [])
	assert_gt(_count_casts(log, "battle_hymn", "Turnlate Ally"), 0,
		"a `turn >= 3` rule must become reachable once the grind passes round 3")


func test_a_grind_does_not_clobber_the_live_round_counter() -> void:
	## The fix writes a global that the live battle UI reads. It must put it back — a grind run
	## between two live rounds must not renumber the fight on screen.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	_bm.current_round = 7
	var bard := _combatant("Turnrestore Bard", "bard")
	_install(bard, {
		"conditions": [{"type": "turn", "op": ">=", "value": 1}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
		"enabled": true,
	})
	var resolver := HeadlessBattleResolver.new()
	resolver.resolve_battle([bard], [_punching_bag()])
	assert_eq(_bm.current_round, 7,
		"a headless grind battle must restore the live round counter it borrowed")
