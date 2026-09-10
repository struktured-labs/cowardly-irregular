extends GutTest

## Catalog-wide ratchet for the frozen-turn-counter defect (fixed 2026-09-09, 832d6da4).
##
## `turn` reads BattleManager.current_round, whose only writers are on the LIVE path.
## HeadlessBattleResolver counted in its own _current_round and never mirrored it, so during a
## grind every turn-gated rule was permanently true or permanently false depending on how many
## rounds the last live battle ran.
##
## The first test of that fix pinned ONE template. The catalog has SEVEN turn-gated rules across
## seven templates, and every one of them is that template's OPENING move — Fighter provoke,
## Cleric protect, Rogue steal, Bard battle_hymn x3. All seven were dead in a grind. This walks
## the shipped catalog rather than restating it, so a template added with a turn-gated opener is
## covered the day it ships.
##
## Attribution comes from AutobattleSystem's own `script_executed` signal — the selector saying
## which rule it chose — not from reading the battle log for an ability name. A song logs once
## per target, so a log-line count reads party size as cast count.

var _abs: Node = null
var _fired: Dictionary = {}
var _rules_ref: Array = []
var _fixture_ids: Array[String] = []
var _connected: bool = false


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
		if not _connected:
			_abs.script_executed.connect(_on_script_executed)
			_connected = true
	_fixture_ids.clear()


func after_each() -> void:
	if _abs:
		if _connected:
			_abs.script_executed.disconnect(_on_script_executed)
			_connected = false
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _on_script_executed(_c, rule, _a) -> void:
	for i in range(_rules_ref.size()):
		if _rules_ref[i] == rule:
			_fired[i] = int(_fired.get(i, 0)) + 1
			return


func _member(cname: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 400, "max_mp": 60,
		"attack": 25, "defense": 20, "magic": 25, "speed": 12
	})
	if job_id != "":
		c.job = JobSystem.get_job(job_id)
	c.job_level = 1
	add_child_autofree(c)
	return c


func _punching_bag() -> Combatant:
	## Outlasts MAX_ROUNDS and cannot wipe the party, so every template gets the same 50 rounds
	## and no assertion here rides on a damage roll.
	var e := Combatant.new()
	e.initialize({
		"name": "Opener Foe", "max_hp": 40000, "max_mp": 99,
		"attack": 40, "defense": 15, "magic": 30, "speed": 10
	})
	add_child_autofree(e)
	return e


func _catalog() -> Dictionary:
	var f := FileAccess.open("res://data/autobattle_rule_templates.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _turn_gated() -> Array:
	var out: Array = []
	for tmpl in _catalog().get("templates", []):
		if not (tmpl is Dictionary):
			continue
		var rules: Array = (tmpl as Dictionary).get("rules", [])
		for ri in range(rules.size()):
			for c in (rules[ri] as Dictionary).get("conditions", []):
				if c is Dictionary and str((c as Dictionary).get("type", "")) == "turn":
					out.append({"tmpl": tmpl, "rule_index": ri})
					break
	return out


func _run_template(tmpl: Dictionary, tag: String) -> Dictionary:
	_rules_ref = tmpl["rules"]
	_fired = {}
	var hero := _member("Opener %s %s" % [tag, tmpl["id"]], str(tmpl["job_id"]))
	var mate := _member("Mate %s %s" % [tag, tmpl["id"]], "fighter")
	var cid: String = hero.combatant_name.to_lower().replace(" ", "_")
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"rules": tmpl["rules"]})
	var resolver := HeadlessBattleResolver.new()
	var result: Dictionary = resolver.resolve_battle([hero, mate], [_punching_bag()])
	return {"result": result, "fired": _fired.duplicate(), "hero": hero}


func test_every_shipped_turn_gated_opener_fires_exactly_once() -> void:
	var gated: Array = _turn_gated()
	assert_gt(gated.size(), 0,
		"control: the shipped catalog must still contain turn-gated rules, or this test is measuring nothing")

	var missed: Array = []
	var seen: Array = []
	for entry in gated:
		var tmpl: Dictionary = entry["tmpl"]
		var ri: int = int(entry["rule_index"])
		var run: Dictionary = _run_template(tmpl, "A")
		var fired: Dictionary = run["fired"]
		var n: int = int(fired.get(ri, 0))
		seen.append("%s#%d=%d" % [tmpl["id"], ri, n])
		assert_gt(int(run["result"].get("rounds", 0)), 1,
			"precondition: %s must run past round 1, or a `turn == 1` gate proves nothing" % tmpl["id"])
		if n != 1:
			missed.append("%s rule %d fired %d times" % [tmpl["id"], ri, n])

	assert_eq(missed.size(), 0,
		"every shipped `turn == 1` opener must fire exactly once per grind battle — 0 means the counter is frozen false, >1 means frozen true and the opener re-casts every round. Got: %s" % [", ".join(missed)])
	gut.p("openers fired: %s" % ", ".join(seen))
