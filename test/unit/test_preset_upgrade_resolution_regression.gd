extends GutTest

## Item 13 fast-follow (cowir-main msg 2147 #1): preset action-level upgrades.
##
## Guards:
##  1. Resolver picks the strongest LEARNED upgrade at execute time; falls back
##     to baseline id when no upgrade qualifies.
##  2. Level-gating honored — job_level < gate means the upgrade isn't picked.
##  3. Deep-check accepts upgrades that are learnable somewhere in the job's
##     roster; rejects upgrades outside the job's kit; uses WORST-CASE MP cost
##     across baseline + upgrades for the fizzle guard.
##  4. The cleric_defensive user regression is fixed: at level 6 (cura learned)
##     the emergency heal cast is now cura, not cure forever.

const AutobattleSystemScript = preload("res://src/autobattle/AutobattleSystem.gd")

var _ab: Node


func before_each() -> void:
	_ab = AutobattleSystemScript.new()


func after_each() -> void:
	_ab.free()


func _fresh_combatant(job_id: String, level: int = 1) -> Combatant:
	# job_level is what the resolver reads; combatant_name doubles as the
	# character_id fallback path when GameState isn't in-tree (test mode).
	var c := Combatant.new()
	c.combatant_name = job_id
	c.job = JobSystem.get_job(job_id)
	c.job_level = level
	c.is_alive = true
	return c


## ── Resolver behavior ────────────────────────────────────────────────────

func test_resolver_returns_baseline_when_no_upgrades() -> void:
	var c := _fresh_combatant("cleric", 20)
	assert_eq(_ab._resolve_ability_upgrade(c, {"id": "cure"}), "cure",
		"no upgrades field → baseline id")
	c.free()


func test_resolver_returns_baseline_when_no_upgrade_learned() -> void:
	var c := _fresh_combatant("cleric", 1)
	assert_eq(_ab._resolve_ability_upgrade(c, {"id": "cure", "upgrades": ["cura"]}), "cure",
		"level 1 cleric hasn't learned cura → keep cure")
	c.free()


func test_resolver_picks_upgrade_when_learned() -> void:
	var c := _fresh_combatant("cleric", 6)
	assert_eq(_ab._resolve_ability_upgrade(c, {"id": "cure", "upgrades": ["cura"]}), "cura",
		"level 6 cleric has cura (unlocks at 6) → resolver picks it")
	c.free()


func test_resolver_walks_upgrades_and_keeps_last_learned() -> void:
	# curaga is authored in abilities.json but not in cleric's abilities_at_level,
	# so a cleric of ANY level will NOT learn it. cura at level 6 is the last learned.
	var c := _fresh_combatant("cleric", 20)
	assert_eq(_ab._resolve_ability_upgrade(c, {"id": "cure", "upgrades": ["cura", "curaga"]}), "cura",
		"walk order weakest→strongest; last learned wins; unlearned entries skipped")
	c.free()


func test_resolver_handles_free_move_upgrades() -> void:
	# pray is the cleric's free_move, in-kit from level 1.
	var c := _fresh_combatant("cleric", 1)
	assert_true(_ab._combatant_has_learned(c, "pray"), "free_move counts as learned")
	c.free()


## ── Deep-check with upgrades ────────────────────────────────────────────

func _rule(conds: Array, acts: Array) -> Dictionary:
	return {"conditions": conds, "actions": acts, "enabled": true}


func test_deep_check_accepts_upgrade_in_full_kit() -> void:
	# cura is learnable by cleric at level 6 — in the full kit even though not level-1.
	# Guard covers worst-case cura cost (12 MP / 70 pool = 18% → ceil 18%; >=20 covers).
	var rule := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 20}, {"type": "ally_hp_percent", "op": "<=", "value": 40}],
		[{"type": "ability", "id": "cure", "target": "lowest_hp_ally", "upgrades": ["cura"]}])
	assert_eq(_ab.validate_rule(rule, "mira").size(), 0,
		"upgrade in job's full roster + guard covering worst-case cost → deep-check passes")


func test_deep_check_rejects_upgrade_outside_job_kit() -> void:
	# fire is a real ability but not in the cleric's roster at any level.
	var rule := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 30}],
		[{"type": "ability", "id": "cure", "target": "lowest_hp_ally", "upgrades": ["fire"]}])
	var errors: Array = _ab.validate_rule(rule, "mira")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "upgrade ability 'fire' not learnable by cleric")


func test_deep_check_rejects_unknown_upgrade_id() -> void:
	var rule := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 30}],
		[{"type": "ability", "id": "cure", "target": "lowest_hp_ally", "upgrades": ["curificus_9000"]}])
	var errors: Array = _ab.validate_rule(rule, "mira")
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "unknown upgrade ability")


func test_deep_check_uses_worst_case_mp_cost() -> void:
	# cure alone is 6 MP (~9% of cleric's 70 pool); with cura upgrade, worst case
	# is 12 MP (~18%). A rule guard of >=15 is fine for cure but NOT for cura.
	var under := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 15}, {"type": "ally_hp_percent", "op": "<=", "value": 40}],
		[{"type": "ability", "id": "cure", "target": "lowest_hp_ally", "upgrades": ["cura"]}])
	var errors: Array = _ab.validate_rule(under, "mira")
	assert_eq(errors.size(), 1, "guard below worst-case cost must fail")
	assert_string_contains(errors[0], "12 MP")
	var over := _rule(
		[{"type": "mp_percent", "op": ">=", "value": 20}, {"type": "ally_hp_percent", "op": "<=", "value": 40}],
		[{"type": "ability", "id": "cure", "target": "lowest_hp_ally", "upgrades": ["cura"]}])
	assert_eq(_ab.validate_rule(over, "mira").size(), 0, "guard covering worst-case cost passes")


## ── User regression fix ─────────────────────────────────────────────────

func test_cleric_defensive_evolves_cure_to_cura_when_learned() -> void:
	# The literal item-13 user complaint: cleric_defensive was casting cure
	# in all heal slots forever. With upgrades wired, a level-6+ cleric
	# resolves the emergency-heal action to cura.
	var t: Dictionary = AutobattleRuleTemplates.find("cleric_defensive")
	assert_false(t.is_empty(), "cleric_defensive must exist")
	# Rule 0 = emergency heal; action 0 = cure with cura upgrade
	var emergency_action: Dictionary = t["rules"][0]["actions"][0]
	assert_eq(str(emergency_action.get("id", "")), "cure", "baseline stays cure")
	assert_true("cura" in (emergency_action.get("upgrades", []) as Array),
		"cleric_defensive emergency heal must upgrade to cura")
	var fresh := _fresh_combatant("cleric", 1)
	assert_eq(_ab._resolve_ability_upgrade(fresh, emergency_action), "cure",
		"level-1 cleric still casts cure")
	fresh.free()
	var leveled := _fresh_combatant("cleric", 6)
	assert_eq(_ab._resolve_ability_upgrade(leveled, emergency_action), "cura",
		"level-6 cleric autobattle now casts cura on emergency heal")
	leveled.free()


func test_mage_aggressive_burst_evolves_fire_to_fira_when_learned() -> void:
	# The double-cast burst rule was already 45%-MP-guarded for fira×2 (40% of
	# 80 pool). With upgrades wired, a level-6+ mage resolves both actions to fira.
	var t: Dictionary = AutobattleRuleTemplates.find("mage_aggressive")
	var burst_rule: Dictionary = t["rules"][2]
	assert_eq((burst_rule["actions"] as Array).size(), 2, "burst rule casts twice")
	for action in burst_rule["actions"]:
		assert_true("fira" in (action.get("upgrades", []) as Array),
			"both burst actions upgrade to fira")
	var leveled := _fresh_combatant("mage", 6)
	for action in burst_rule["actions"]:
		assert_eq(_ab._resolve_ability_upgrade(leveled, action), "fira",
			"level-6 mage burst now casts fira")
	leveled.free()
