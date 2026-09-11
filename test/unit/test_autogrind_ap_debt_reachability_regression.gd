extends GutTest

## Settling a question I reported twice as "a design call" and never measured.
##
## Three shipped autobattle templates — fighter_defensive #3, mage_defensive #1, rogue_defensive #2
## — carry `ap < 0 -> defer`. I observed that every rule in those templates has exactly ONE action
## and inferred the condition could never be true there. That inference was right, but it was an
## inference, and it left the more important question open: is `ap < 0` reachable AT ALL, or is it
## dead vocabulary?
##
## MEASURED, and the two halves have different answers:
##
##   AP debt is REAL          can_brave permits current_ap - cost >= -4, and spend_ap clamps to
##                            [-4, 4]. Only spending AP descends, and only a MULTI-ACTION
##                            (Advance) rule spends it.
##   single-action scripts     never spend, so AP climbs to the +4 cap and stays there. `ap < 0`
##                            cannot become true — which is exactly the three templates' shape.
##
## So the condition is sound and the three shipped rules are unreachable WITHIN THEIR OWN TEMPLATE.
## That is a content decision for the catalog owner (drop the rule, or give the template an Advance
## rule), and this test exists so the decision rests on a measurement instead of my reasoning.
##
## TWO UPDATES FOR WHOEVER MAKES THAT CALL, both from 2026-09-11.
##
## 1. THE VOCABULARY IS LIVE, ONLY THE POSITION IS STRANDED — which points at "give the template an
##    Advance rule" rather than "drop the rule". The evidence is
##    test_the_condition_itself_reads_the_debt_when_it_exists below: `ap < 0` is TRUE for a
##    combatant in real debt and FALSE once it is paid. Authored-but-unreachable, not stale.
##
##    ⚠️ I first credited this to a cross-lane "dead set references a dead vocabulary" signal, which
##    @cowir-story RETRACTED an hour later — every trigger in their corpus scored 0 because nothing
##    reads triggers at all, so live and dead scenes were indistinguishable. My conclusion does not
##    depend on it and never did; the behavioural arm below is the discriminator and predates the
##    borrowed one. But I had called the borrowed signal "the discriminator I was missing" while
##    already holding a better one, and a justification travels further than the finding it
##    decorates. Borrowing a signal without re-running its control on your own corpus is the
##    mistake even when, as here, it changes nothing.
##
## 2. THE THRESHOLD MOVED, AND I MOVED IT. The resolver now charges billed_ap for an Advance
##    instead of size-1, so a 2-action rule costs 2 AP per round against the natural +1 rather than
##    1. Measured on that shape over 50 rounds: steady state went 0 -> -1. So if the catalog owner
##    gives one of these templates an Advance rule, `ap < 0` becomes reachable SOONER than it would
##    have before, and a 2-action rule now suffices where it previously did not descend at all.

var _abs: Node = null
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_fixture_ids.clear()


func after_each() -> void:
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _hero(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": 600, "max_mp": 60,
		"attack": 15, "defense": 40, "magic": 15, "speed": 12})
	add_child_autofree(c)
	return c


func _punching_bag() -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": "AP Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(e)
	return e


func _install(hero: Combatant, rules: Array) -> void:
	var cid: String = hero.combatant_name.to_lower().replace(" ", "_")
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"rules": rules})


func _attack() -> Dictionary:
	return {"type": "attack", "target": "lowest_hp_enemy"}


func test_ap_debt_is_reachable_with_an_advance_rule() -> void:
	## Four actions cost 4 AP (billed_ap, since 2026-09-11 — this said 3 while the resolver underpriced
	## every Advance by one). Sustained over rounds the natural +1 cannot keep up, so AP descends
	## past zero — the state the condition is written for.
	var hero := _hero("Advance Hero")
	_install(hero, [
		{"conditions": [{"type": "always"}],
		 "actions": [_attack(), _attack(), _attack(), _attack()], "enabled": true},
	])
	var resolver := HeadlessBattleResolver.new()
	resolver.resolve_battle([hero], [_punching_bag()])
	assert_true(is_instance_valid(hero), "precondition: the fixture survived to be read")
	assert_lt(hero.current_ap, 0,
		"a sustained 4-action Advance script must drive AP into debt — if this cannot happen, `ap < 0` is dead vocabulary rather than an unreachable rule")


func test_a_single_action_script_never_reaches_debt() -> void:
	## The three shipped templates' shape. Nothing spends, so AP rises to the cap and stays.
	var hero := _hero("Single Hero")
	_install(hero, [
		{"conditions": [{"type": "always"}], "actions": [_attack()], "enabled": true},
	])
	var resolver := HeadlessBattleResolver.new()
	resolver.resolve_battle([hero], [_punching_bag()])
	assert_gte(hero.current_ap, 0,
		"a script that never Advances cannot spend AP, so it can never owe any")
	assert_eq(hero.current_ap, 4,
		"and it parks at the +4 cap — which is why `ap < 0` in those templates is unreachable, not merely rare")


func test_the_condition_itself_reads_the_debt_when_it_exists() -> void:
	## Separating the two failure modes: the condition could be fine and the templates wrong, or
	## the condition itself could be broken. Pin the condition against a combatant in real debt.
	var hero := _hero("Probe Hero")
	hero.spend_ap(3)
	assert_lt(hero.current_ap, 0, "precondition: the probe is genuinely in debt (%d)" % hero.current_ap)
	assert_true(_abs._evaluate_grid_condition(hero, {"type": "ap", "op": "<", "value": 0}),
		"`ap < 0` must be TRUE for a combatant who owes AP — the condition is sound, the three shipped rules just sit in templates that never spend")
	hero.gain_ap(4)
	assert_false(_abs._evaluate_grid_condition(hero, {"type": "ap", "op": "<", "value": 0}),
		"control: and FALSE once the debt is paid, or the assertion above proves nothing")


func test_the_three_shipped_templates_still_have_no_advance_rule() -> void:
	## The content half, derived from the catalog rather than from my notes. If someone later gives
	## one of these templates a multi-action rule, its `ap < 0` rule becomes live and this test
	## should stop flagging it — so the finding cannot rot into a stale complaint.
	var f := FileAccess.open("res://data/autobattle_rule_templates.json", FileAccess.READ)
	assert_true(f != null, "control: the shipped catalog must be readable")
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var stranded: Array = []
	var checked := 0
	for tmpl in data.get("templates", []):
		var rules: Array = (tmpl as Dictionary).get("rules", [])
		var has_advance := false
		for r in rules:
			if (r as Dictionary).get("actions", []).size() > 1:
				has_advance = true
		for ri in range(rules.size()):
			for c in (rules[ri] as Dictionary).get("conditions", []):
				if str((c as Dictionary).get("type", "")) != "ap":
					continue
				checked += 1
				if str((c as Dictionary).get("op", "")) == "<" and float((c as Dictionary).get("value", 0)) <= 0.0 and not has_advance:
					stranded.append("%s rule %d" % [str(tmpl.get("id", "?")), ri + 1])
	assert_gt(checked, 0, "control: the catalog must still contain ap conditions to examine")
	gut.p("ap-debt rules stranded in templates with no Advance rule: %s" % str(stranded))
	assert_eq(stranded.size(), 3,
		("exactly the three known stranded rules are expected; a change here means the catalog " +
		"moved and the content decision needs revisiting: %s") % str(stranded))
