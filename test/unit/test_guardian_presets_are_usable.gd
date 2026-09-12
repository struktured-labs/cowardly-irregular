extends GutTest

## A player who unlocks the Guardian in chapter 2 opened the autobattle preset catalog and found
## NOTHING. Five starter jobs ship three presets each; five REACHABLE non-starter jobs shipped zero
## — guardian and speculator (story ch.2), summoner (ch.3), bossbinder (boss count), skiptrotter
## (completion). In a game whose stated pillar is that autobattle IS the game.
##
## This file covers the Guardian's three. The other four jobs are the same gap and are not fixed
## here — I would rather ship one job authored against its real kit than five authored against a
## guess, and the arms below are what make "its real kit" a measurement.
##
## ⚠️ The trap this file exists to avoid is already documented next door: guardian's DEFAULT SCRIPT
## authors iron_guard, protect and taunt, none of which the Guardian can know — two are monster
## abilities. test_default_scripts_reference_their_own_kit carries all six as KNOWN_MISMATCHED.
## Presets authored the same way would be a second copy of that defect, so every ability id below
## is checked against jobs.json rather than against what sounds like a Guardian move.

const TEMPLATES := "res://data/autobattle_rule_templates.json"
const STANCES := ["defensive", "balanced", "aggressive"]

func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "CONTROL: %s parses" % path)
	return parsed

func _guardian_templates() -> Array:
	var all: Array = (_json(TEMPLATES).get("templates", []) as Array)
	assert_gt(all.size(), 14, "CONTROL: the catalog is populated (%d)" % all.size())
	return all.filter(func(t): return str((t as Dictionary).get("job_id", "")) == "guardian")

func _guardian_kit() -> Dictionary:
	var jobs: Dictionary = _json("res://data/jobs.json")
	jobs = jobs.get("jobs", jobs)
	var g: Dictionary = jobs.get("guardian", {})
	var out: Dictionary = {}
	for a in (g.get("abilities", []) as Array):
		out[str(a)] = true
	var at_level = g.get("abilities_at_level", {})
	if at_level is Dictionary:
		for lv in (at_level as Dictionary).keys():
			for a in ((at_level as Dictionary)[lv] as Array):
				out[str(a)] = true
	assert_gt(out.size(), 2, "CONTROL: the Guardian kit reads non-empty (%d)" % out.size())
	return out

func test_the_guardian_has_one_preset_per_stance() -> void:
	var mine := _guardian_templates()
	assert_eq(mine.size(), 3, "three stances, like every starter job")
	var seen: Array = []
	for t in mine:
		seen.append(str((t as Dictionary).get("stance", "")))
	seen.sort()
	var want := STANCES.duplicate()
	want.sort()
	assert_eq(seen, want, "one each of defensive/balanced/aggressive, got %s" % str(seen))

func test_every_ability_is_one_the_guardian_can_actually_know() -> void:
	## The whole point. An ability the job cannot learn is a rule that never fires — and the
	## Guardian's default script already ships three of those.
	var kit := _guardian_kit()
	var bad: Array = []
	for t in _guardian_templates():
		for r in ((t as Dictionary).get("rules", []) as Array):
			for a in ((r as Dictionary).get("actions", []) as Array):
				var ad: Dictionary = a
				if str(ad.get("type", "")) != "ability":
					continue
				var aid: String = str(ad.get("id", ""))
				if not kit.has(aid):
					bad.append("%s/%s" % [str((t as Dictionary).get("id", "")), aid])
	assert_eq(bad.size(), 0,
		"a preset uses an ability outside the Guardian's kit — it can never fire: " + str(bad))

func test_every_condition_action_and_target_is_in_the_grammar() -> void:
	## Authored against AutobattleSystem's own constants, not against what looks plausible. A type
	## in neither map is one validate_rule waves through unexamined.
	var abs_node = Engine.get_main_loop().root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		pending("AutobattleSystem autoload required")
		return
	var conds: Dictionary = abs_node.CONDITION_TYPES
	var acts: Dictionary = abs_node.ACTION_TYPES
	var targets: Dictionary = abs_node.TARGET_TYPES
	var ops: Dictionary = abs_node.OPERATORS
	assert_gt(conds.size(), 5, "CONTROL: the grammar constants are readable")

	var bad: Array = []
	for t in _guardian_templates():
		for r in ((t as Dictionary).get("rules", []) as Array):
			for c in ((r as Dictionary).get("conditions", []) as Array):
				var cd: Dictionary = c
				if not conds.has(str(cd.get("type", ""))):
					bad.append("condition %s" % str(cd.get("type", "")))
				if cd.has("op") and not ops.has(str(cd["op"])):
					bad.append("operator %s" % str(cd["op"]))
			for a in ((r as Dictionary).get("actions", []) as Array):
				var ad: Dictionary = a
				if not acts.has(str(ad.get("type", ""))):
					bad.append("action %s" % str(ad.get("type", "")))
				if ad.has("target") and not targets.has(str(ad["target"])):
					bad.append("target %s" % str(ad["target"]))
	assert_eq(bad.size(), 0, "authored against something the grammar does not define: " + str(bad))

func test_the_live_validator_accepts_every_rule() -> void:
	## Grammar membership is necessary and not sufficient — validate_rule is what the editor and the
	## share-code path run, and it refuses shapes a key-by-key check would pass.
	var abs_node = Engine.get_main_loop().root.get_node_or_null("AutobattleSystem")
	if abs_node == null or not abs_node.has_method("validate_rule"):
		pending("AutobattleSystem.validate_rule required")
		return
	var refused: Array = []
	var checked: int = 0
	for t in _guardian_templates():
		for r in ((t as Dictionary).get("rules", []) as Array):
			checked += 1
			var res = abs_node.validate_rule(r)
			var ok: bool = res if res is bool else bool((res as Dictionary).get("valid", true))
			if not ok:
				refused.append("%s rule %d: %s" % [str((t as Dictionary).get("id", "")), checked, str(res)])
	assert_gt(checked, 8, "CONTROL: rules were actually submitted to the validator (%d)" % checked)
	assert_eq(refused.size(), 0, "the live validator refuses an authored rule: " + str(refused))

func test_every_preset_ends_in_an_unconditional_rule() -> void:
	## First match wins, top to bottom. A preset whose last rule can fail to match leaves the
	## character doing nothing on a turn the player paid for — the silent-failure shape this
	## project cares most about.
	for t in _guardian_templates():
		var rules: Array = (t as Dictionary).get("rules", []) as Array
		assert_gt(rules.size(), 1, "%s has rules at all" % str((t as Dictionary).get("id", "")))
		var last: Dictionary = rules[rules.size() - 1]
		var conds: Array = last.get("conditions", []) as Array
		assert_eq(conds.size(), 1, "%s's last rule must be a single catch-all" % str((t as Dictionary).get("id", "")))
		assert_eq(str((conds[0] as Dictionary).get("type", "")), "always",
			"%s must end on `always` or the turn can be wasted" % str((t as Dictionary).get("id", "")))

func test_the_other_reachable_jobs_still_have_none() -> void:
	## Honest scope marker, and it reds when someone fixes one — the entry cannot outlive its reason.
	## These four have working unlock conditions and zero presets; only the Guardian is fixed here.
	var blob: String = FileAccess.get_file_as_string(TEMPLATES)
	var still_missing: Array = []
	## speculator dropped 2026-09-12 — it has three stances now. The list is a scope note and the
	## assert below counts it, so a job gaining presets reds here until someone updates both.
	for jid in ["bossbinder", "skiptrotter"]:
		if not blob.contains("\"job_id\": \"%s\"" % jid):
			still_missing.append(jid)
	assert_eq(still_missing.size(), 2,
		"if one of these gained presets, drop it from this list — it is a scope note, not a rule: " + str(still_missing))

func test_the_catalog_actually_offers_them_to_a_guardian() -> void:
	## EXECUTION is not SELECTION: three well-formed entries in a JSON file prove nothing about a
	## player seeing them. AutobattleRuleTemplates.find_for_job is what the picker calls, and it
	## drops any entry failing its own shape check at :40 — so this is the arm that says "reachable"
	## rather than "present".
	var cat = load("res://src/autobattle/AutobattleRuleTemplates.gd")
	assert_not_null(cat, "CONTROL: the catalog script loads")
	## ⚠️ `>` not `==`. My first version asserted the fighter offers exactly three — and a lane adding
	## a fourth fighter preset is CORRECT WORK that would have redded this file. Third exact-count
	## tax I have written today; the control only needs the API to return SOMETHING for a known job.
	var fighter: Array = cat.find_for_job("fighter")
	assert_gt(fighter.size(), 0, "CONTROL: find_for_job returns presets for a known job")
	## Guardian stays `==` deliberately: three stances is the deliverable, and a fourth would be a
	## deliberate design change that should surface here. cowir-overworld's question 2 — growth IS
	## the signal for this set, and is not for the fighter control above.
	var guardian: Array = cat.find_for_job("guardian")
	assert_eq(guardian.size(), 3,
		"a Guardian must be offered three presets; the catalog returned %d" % guardian.size())
	var names: Array = []
	for t in guardian:
		names.append(str((t as Dictionary).get("name", "")))
	names.sort()
	assert_eq(names, ["Aggressive", "Balanced", "Defensive"], "and they are the three stances: %s" % str(names))
