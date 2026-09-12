extends GutTest

## A preset must be able to pay for every rule it can actually reach.
##
## `bard_defensive` shipped with `always -> lullaby` as its catch-all — a 12 MP song with no MP
## guard — and it worked only because an unrelated rule above it (`mp_percent < 20 -> riff`) caught
## the low-MP case first. Lullaby became reachable at 13 MP and cost 12: a margin of ONE MP, resting
## on a threshold nobody had connected to it. A cost change, a pool change, or a tweak to that
## threshold would have turned the stance's fallback into "can't use Lullaby right now" every turn,
## and that preset had no attack in it to fall through to.
##
## ⚠️ `AutobattleSystem._deep_check_rule` cannot answer this. Its own comment says it is
## "deliberately STRICTER than the preset catalog's whole-script lint (no earlier-refill-rule
## credit)" — and that whole-script lint EXISTED NOWHERE, in src/ or test/, so the comment compared
## its strictness to nothing. Run the deep check over the catalog and four correct presets fail it.
## This is that missing lint: same arithmetic, plus the credit the catalog's own design rules grant.

const TEMPLATES := "res://data/autobattle_rule_templates.json"


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "CONTROL: %s parses" % path)
	return parsed


func _pool_for(job_id: String) -> int:
	var jobs: Dictionary = _json("res://data/jobs.json")
	jobs = jobs.get("jobs", jobs)
	return int((jobs.get(job_id, {}) as Dictionary).get("stat_modifiers", {}).get("max_mp", 0))


func _rule_mp_cost(rule: Dictionary, abilities: Dictionary) -> int:
	var total: int = 0
	for a in (rule.get("actions", []) as Array):
		var ad: Dictionary = a
		if str(ad.get("type", "")) == "ability":
			total += int((abilities.get(str(ad.get("id", "")), {}) as Dictionary).get("mp_cost", 0))
	return total


## The MP percentage at or above which this rule can actually be reached.
##
## Two sources, and only two, both conservative: the rule's OWN `mp_percent >=` guard, and an
## earlier rule whose SOLE condition is `mp_percent < X` — which therefore fires unconditionally
## below X and the rule below it can never be reached there. An earlier rule with extra conditions
## MIGHT protect and might not, so it earns no credit. That direction matters: not crediting a real
## protector can raise a false alarm someone reads; crediting a fake one reports a clean catalog.
func _reachable_floor_pct(rules: Array, index: int) -> int:
	var floor_pct: int = 0
	for j in range(index):
		var conds: Array = (rules[j] as Dictionary).get("conditions", []) as Array
		if conds.size() != 1:
			continue
		var c: Dictionary = conds[0]
		if str(c.get("type", "")) == "mp_percent" and str(c.get("op", "")) == "<":
			floor_pct = maxi(floor_pct, int(c.get("value", 0)))
	for c in ((rules[index] as Dictionary).get("conditions", []) as Array):
		var cd: Dictionary = c
		if str(cd.get("type", "")) == "mp_percent" and str(cd.get("op", "")) == ">=":
			floor_pct = maxi(floor_pct, int(cd.get("value", 0)))
	return floor_pct


## Returns the offending rules for a template list — shared so the detector can be pointed at a
## deliberately broken fixture as well as at the shipped catalog.
func _unaffordable(templates: Array, abilities: Dictionary, counter: Array) -> Array:
	var out: Array = []
	for t in templates:
		var td: Dictionary = t
		var pool: int = _pool_for(str(td.get("job_id", "")))
		if pool <= 0:
			continue
		var rules: Array = td.get("rules", []) as Array
		for i in range(rules.size()):
			var cost: int = _rule_mp_cost(rules[i], abilities)
			if cost <= 0:
				continue
			counter[0] += 1
			var required: int = int(ceil(float(cost) / float(pool) * 100.0))
			var floor_pct: int = _reachable_floor_pct(rules, i)
			if floor_pct < required:
				out.append("%s rule %d: costs %d MP of %d (needs >= %d%%), reachable at %d%%"
					% [str(td.get("id", "")), i + 1, cost, pool, required, floor_pct])
	return out


func test_every_costed_rule_is_affordable_wherever_it_can_be_reached() -> void:
	var abilities: Dictionary = _json("res://data/abilities.json")
	abilities = abilities.get("abilities", abilities)
	var counter: Array = [0]
	var bad: Array = _unaffordable(_json(TEMPLATES).get("templates", []) as Array, abilities, counter)
	assert_gt(counter[0], 30, "CONTROL: costed rules were actually examined (%d)" % counter[0])
	assert_eq(bad.size(), 0,
		"a preset can reach a rule it cannot pay for; the ability fizzles and the turn is consumed, "
		+ "every turn it is reached: " + str(bad))


func test_the_detector_catches_a_rule_that_cannot_be_paid_for() -> void:
	## The control bucket. The arm above reports "0 problems" and that is exactly what a broken
	## predicate reports, so point the same code at a template that IS broken and require a hit.
	var abilities: Dictionary = _json("res://data/abilities.json")
	abilities = abilities.get("abilities", abilities)
	var counter: Array = [0]
	## A bard catch-all singing a 12 MP song with nothing above it to catch the empty-pool case —
	## the exact shape bard_defensive shipped with.
	var broken: Array = [{
		"id": "synthetic_broken", "job_id": "bard", "stance": "defensive", "name": "Synthetic",
		"rules": [
			{"conditions": [{"type": "hp_percent", "op": "<", "value": 40},
				{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}],
			 "actions": [{"type": "item", "id": "potion", "target": "self"}], "enabled": true},
			{"conditions": [{"type": "always"}],
			 "actions": [{"type": "ability", "id": "lullaby", "target": "lowest_hp_enemy"}], "enabled": true},
		]}]
	var bad: Array = _unaffordable(broken, abilities, counter)
	assert_eq(bad.size(), 1, "the detector must flag an unguarded costed catch-all: " + str(bad))
	assert_true(str(bad[0]).contains("reachable at 0%"),
		"and it must say WHY — nothing above it protects the empty pool: %s" % str(bad[0]))


func test_the_refill_credit_is_what_makes_the_shipped_mage_presets_pass() -> void:
	## Names the mechanism rather than trusting it. Every mage preset puts `mp_percent < N -> channel`
	## (0 MP) above its catch-all; strip that one rule and the catch-all becomes unreachable-safe no
	## longer. This is also the exact credit the per-rule deep check withholds, which is why running
	## THAT over the catalog reports four correct presets as broken.
	var abilities: Dictionary = _json("res://data/abilities.json")
	abilities = abilities.get("abilities", abilities)
	var mage: Array = (_json(TEMPLATES).get("templates", []) as Array).filter(
		func(t): return str((t as Dictionary).get("job_id", "")) == "mage")
	assert_gt(mage.size(), 2, "CONTROL: the mage presets were found (%d)" % mage.size())

	var counter: Array = [0]
	assert_eq(_unaffordable(mage, abilities, counter).size(), 0, "CONTROL: they pass as shipped")

	var stripped: Array = []
	for t in mage:
		var copy: Dictionary = (t as Dictionary).duplicate(true)
		var kept: Array = []
		for r in (copy.get("rules", []) as Array):
			var conds: Array = (r as Dictionary).get("conditions", []) as Array
			var is_refill: bool = conds.size() == 1 and str((conds[0] as Dictionary).get("type", "")) == "mp_percent" \
				and str((conds[0] as Dictionary).get("op", "")) == "<"
			if not is_refill:
				kept.append(r)
		copy["rules"] = kept
		stripped.append(copy)
	var counter2: Array = [0]
	assert_gt(_unaffordable(stripped, abilities, counter2).size(), 0,
		"removing the 0-MP refill rule must make the mage catch-all unaffordable — if it does not, "
		+ "the credit this lint grants is not what is holding those presets up")
