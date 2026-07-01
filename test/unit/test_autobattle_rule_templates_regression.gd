extends GutTest

## Item 13 (playtest backlog): starter autobattle presets.
##
## Guards three layers:
##  1. Catalog integrity — 15 templates (3 stances × 5 starter jobs), every
##     condition/action/target resolvable by AutobattleSystem's evaluator,
##     every ability in that job's LEVEL-1 base kit (level-gated abilities
##     would fizzle-consume the turn for a fresh character).
##  2. The fizzle-turn lint — every costed-ability rule either carries a
##     sufficient mp_percent guard or sits below a 0-cost MP-refill rule,
##     so a preset can never burn a turn on an unaffordable ability.
##  3. Installer contract (mirrors AutogrindRuleTemplates): install creates
##     a new profile, writes the template rules, and RESTORES the player's
##     active profile. Fails cleanly on unknown id / null system.
##  4. Default-profile seeding — new characters get real Defensive/Aggressive
##     preset content, not empty attack-only shells (the user's complaint).

const TemplatesClass = preload("res://src/autobattle/AutobattleRuleTemplates.gd")
const AutobattleSystemScript = preload("res://src/autobattle/AutobattleSystem.gd")

const STARTER_JOBS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]
const STANCES: Array[String] = ["defensive", "balanced", "aggressive"]


func before_each() -> void:
	TemplatesClass._reset_cache_for_test()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must open" % path)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


## ── Catalog integrity ────────────────────────────────────────────────────

func test_catalog_has_15_templates_3_per_job() -> void:
	var cat: Array = TemplatesClass.catalog()
	assert_eq(cat.size(), 15, "catalog must hold 3 stances × 5 starter jobs")
	for job in STARTER_JOBS:
		var for_job: Array = TemplatesClass.find_for_job(job)
		assert_eq(for_job.size(), 3, "job '%s' must have 3 presets" % job)
		var stances: Array = []
		for t in for_job:
			stances.append(t.get("stance", ""))
		for stance in STANCES:
			assert_true(stance in stances, "job '%s' missing '%s' stance" % [job, stance])


func test_every_condition_action_target_supported() -> void:
	var ab_system = AutobattleSystemScript.new()
	for t in TemplatesClass.catalog():
		for rule in t.get("rules", []):
			for cond in rule.get("conditions", []):
				var ctype: String = str(cond.get("type", ""))
				assert_true(ab_system.CONDITION_TYPES.has(ctype),
					"template '%s' uses unsupported condition '%s'" % [t["id"], ctype])
			for action in rule.get("actions", []):
				var atype: String = str(action.get("type", ""))
				assert_true(ab_system.ACTION_TYPES.has(atype),
					"template '%s' uses unsupported action '%s'" % [t["id"], atype])
				if action.has("target"):
					var tgt: String = str(action.get("target", ""))
					assert_true(ab_system.TARGET_TYPES.has(tgt),
						"template '%s' uses unsupported target '%s'" % [t["id"], tgt])
	ab_system.free()


func test_every_ability_in_job_level1_base_kit() -> void:
	var jobs: Dictionary = _load_json("res://data/jobs.json")
	for t in TemplatesClass.catalog():
		var job: Dictionary = jobs.get(t["job_id"], {})
		assert_false(job.is_empty(), "job '%s' must exist in jobs.json" % t["job_id"])
		var allowed: Array = (job.get("abilities", []) as Array).duplicate()
		var free_move: Dictionary = job.get("free_move", {})
		if free_move.has("ability_id"):
			allowed.append(free_move["ability_id"])
		for rule in t.get("rules", []):
			for action in rule.get("actions", []):
				if str(action.get("type", "")) != "ability":
					continue
				var aid: String = str(action.get("id", ""))
				assert_true(aid in allowed,
					"template '%s' references '%s' — not in %s's level-1 kit (would fizzle-consume the turn)" % [t["id"], aid, t["job_id"]])


func test_costed_ability_rules_cannot_fizzle() -> void:
	## The fizzle-turn lint: for each rule with costed-ability actions, either
	## (a) the rule has an mp_percent >= guard covering the summed MP cost, or
	## (b) an EARLIER rule catches low MP unconditionally with a 0-cost refill
	##     (mp_percent < X → 0-cost actions, X covering this rule's cost).
	var jobs: Dictionary = _load_json("res://data/jobs.json")
	var abilities: Dictionary = _load_json("res://data/abilities.json")
	for t in TemplatesClass.catalog():
		var job: Dictionary = jobs.get(t["job_id"], {})
		var max_mp: int = int(job.get("stat_modifiers", {}).get("max_mp", 1))
		var rules: Array = t.get("rules", [])
		for i in range(rules.size()):
			var cost: int = 0
			for action in rules[i].get("actions", []):
				if str(action.get("type", "")) == "ability":
					cost += int(abilities.get(str(action.get("id", "")), {}).get("mp_cost", 0))
			if cost <= 0:
				continue
			var need_pct: int = ceili(float(cost) / float(max_mp) * 100.0)
			var guarded: bool = false
			for cond in rules[i].get("conditions", []):
				if str(cond.get("type", "")) == "mp_percent" and str(cond.get("op", "")) == ">=" \
						and int(cond.get("value", 0)) >= need_pct:
					guarded = true
			if not guarded:
				for j in range(i):
					var earlier: Array = rules[j].get("conditions", [])
					if earlier.size() != 1 or str(earlier[0].get("type", "")) != "mp_percent" \
							or str(earlier[0].get("op", "")) != "<":
						continue
					if int(earlier[0].get("value", 0)) < need_pct:
						continue
					var refill_free: bool = true
					for ea in rules[j].get("actions", []):
						if str(ea.get("type", "")) == "ability" \
								and int(abilities.get(str(ea.get("id", "")), {}).get("mp_cost", 0)) > 0:
							refill_free = false
					if refill_free:
						guarded = true
						break
			assert_true(guarded,
				"template '%s' rule %d costs %d MP (%d%%) with no sufficient guard — would fizzle-consume the turn" % [t["id"], i, cost, need_pct])


func test_every_rule_enabled_and_every_template_ends_with_always() -> void:
	for t in TemplatesClass.catalog():
		var rules: Array = t.get("rules", [])
		assert_gt(rules.size(), 0, "template '%s' must have rules" % t["id"])
		for rule in rules:
			assert_true(bool(rule.get("enabled", false)),
				"template '%s' has a disabled rule — presets must ship fully live" % t["id"])
		var last_conds: Array = rules[rules.size() - 1].get("conditions", [])
		assert_eq(last_conds.size(), 1, "template '%s' last rule must be a bare always" % t["id"])
		assert_eq(str(last_conds[0].get("type", "")), "always",
			"template '%s' must end with an always fallback so the PC never stalls" % t["id"])


func test_cleric_defensive_ordering_matches_user_ask() -> void:
	## The user's literal playtest complaint: healing priorities were opaque.
	## Pin the cleric Defensive order: emergency Cura → Esuna cleanse →
	## proactive Cure → Pray refill → Defer idle.
	var t: Dictionary = TemplatesClass.find("cleric_defensive")
	assert_false(t.is_empty(), "cleric_defensive must exist")
	var got: Array = []
	for rule in t.get("rules", []):
		var a: Dictionary = rule.get("actions", [])[0]
		got.append(str(a.get("id", a.get("type", ""))))
	assert_eq(got, ["cura", "esuna", "cure", "pray", "defer"],
		"cleric Defensive priority order regressed (user-validated ordering)")


## ── Installer contract ───────────────────────────────────────────────────

class FakeAutobattleSystem:
	var profiles: Array = [{"name": "Default", "script": {}}, {"name": "Custom", "script": {}}]
	var active: int = 1
	var written_scripts: Array = []
	var fail_create: bool = false

	func create_new_profile(_character_id: String, name: String) -> int:
		if fail_create:
			return -1
		profiles.append({"name": name, "script": {}})
		return profiles.size() - 1

	func get_active_profile_index(_character_id: String) -> int:
		return active

	func set_active_profile(_character_id: String, idx: int) -> void:
		active = idx

	func set_character_script(_character_id: String, script: Dictionary) -> void:
		profiles[active]["script"] = script
		written_scripts.append(script)


func test_install_writes_template_and_restores_active_profile() -> void:
	var fake := FakeAutobattleSystem.new()
	var idx: int = TemplatesClass.install_as_new_profile("fighter_defensive", fake, "hero")
	assert_eq(idx, 2, "install must return the new profile index")
	assert_eq(fake.active, 1, "player's active profile must be RESTORED after install")
	assert_eq(fake.profiles[2]["name"], "Defensive")
	assert_eq(fake.written_scripts.size(), 1)
	var script: Dictionary = fake.written_scripts[0]
	assert_eq(str(script.get("character_id", "")), "hero")
	assert_gt((script.get("rules", []) as Array).size(), 0, "installed script must carry the template rules")


func test_install_unknown_id_fails_cleanly() -> void:
	var fake := FakeAutobattleSystem.new()
	var idx: int = TemplatesClass.install_as_new_profile("nonexistent_preset", fake, "hero")
	assert_eq(idx, -1)
	assert_eq(fake.profiles.size(), 2, "no profile may be created for an unknown template id")
	assert_eq(fake.active, 1, "active profile untouched on failure")


func test_install_null_system_and_at_max_fail_cleanly() -> void:
	assert_eq(TemplatesClass.install_as_new_profile("fighter_defensive", null, "hero"), -1)
	var fake := FakeAutobattleSystem.new()
	fake.fail_create = true
	assert_eq(TemplatesClass.install_as_new_profile("fighter_defensive", fake, "hero"), -1,
		"create_new_profile returning -1 (max profiles) must propagate")
	assert_eq(fake.active, 1, "active profile untouched when create fails")


## ── Default-profile seeding ──────────────────────────────────────────────

func test_new_character_profiles_seed_real_preset_content() -> void:
	var ab_system = AutobattleSystemScript.new()
	for character_id in ["hero", "mira", "zack", "vex", "bard"]:
		var data: Dictionary = ab_system._create_default_profiles(character_id)
		var profiles: Array = data.get("profiles", [])
		assert_eq(profiles.size(), 3, "'%s' must seed 3 profiles" % character_id)
		assert_eq(profiles[0]["name"], "Default")
		var names: Array = [profiles[1]["name"], profiles[2]["name"]]
		assert_true("Defensive" in names and "Aggressive" in names,
			"'%s' profiles 1-2 must be the Defensive + Aggressive presets" % character_id)
		for i in [1, 2]:
			var rules: Array = profiles[i]["script"].get("rules", [])
			assert_gt(rules.size(), 1,
				"'%s' profile '%s' must hold real preset rules, not an empty attack-only shell" % [character_id, profiles[i]["name"]])
	ab_system.free()
