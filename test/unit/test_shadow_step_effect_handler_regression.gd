extends GutTest

## tick 381: BattleManager handles the shadow_step effect from the
## shadow_step ability.
##
## Pre-fix data/abilities.json shadow_step authored:
##   {effect: "shadow_step", duration: 1, evasion_bonus: 1.0, next_crit: true}
##   description: "Vanish into shadows, gaining evasion and guaranteeing next attack crits"
##
## The effect fell through to `_:` push_warning default — the ability
## consumed MP+AP, ran the cast animation, and produced ZERO mechanical
## effect. Players got nothing for the shadow-step flavor.
##
## Post-fix maps the two intents to existing engine mechanics:
##   - 100% dodge: _target_dodges_physical recognizes shadow_step
##     status (mirrors invisible: falls off on hit).
##   - Guaranteed crit: _calculate_crit_chance returns 1.0 when the
##     attacker has the shadow_step status.
##
## Self-buff target. Duration 1 turn by default (per the data).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


# ── Source pin: shadow_step arm exists in support-effect dispatch ───

func test_shadow_step_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the case label and the status apply.
	var arm_idx: int = src.find("\"shadow_step\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have a shadow_step arm")
	# Within ~400 chars of the arm we should see the status apply.
	var window: String = src.substr(arm_idx, 400)
	assert_true(window.contains("add_status(\"shadow_step\""),
		"shadow_step arm must apply the shadow_step status")


# ── Source pin: _target_dodges_physical recognizes shadow_step ──────

func test_dodge_recognizes_shadow_step() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _target_dodges_physical")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("has_status(\"shadow_step\")"),
		"_target_dodges_physical must check shadow_step status")
	assert_true(body.contains("remove_status(\"shadow_step\")"),
		"_target_dodges_physical must consume shadow_step on hit attempt (falls-off semantic)")


# ── Source pin: _calculate_crit_chance returns 1.0 for shadow_step ──

func test_crit_chance_returns_one_for_shadow_step() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _calculate_crit_chance")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("has_status(\"shadow_step\")"),
		"_calculate_crit_chance must check shadow_step status")
	assert_true(body.contains("return 1.0"),
		"_calculate_crit_chance must return 1.0 when shadow_step is active")


# ── Source pin: data still authors shadow_step effect ───────────────

func test_shadow_step_ability_still_authors_effect() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("shadow_step"),
		"shadow_step ability must exist in abilities.json")
	assert_eq(str(data["shadow_step"].get("effect", "")), "shadow_step",
		"shadow_step ability must still author effect=shadow_step")


# ── Behavioral: dispatch applies the status to self ─────────────────

func test_dispatch_applies_shadow_step_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("shadow_step"):
		pending("shadow_step ability data required")
		return
	var c: Combatant = _make("Rogue")
	var ability: Dictionary = js.abilities["shadow_step"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, typed_targets)
	assert_true("shadow_step" in c.status_effects,
		"shadow_step status must be present on the caster after using the shadow_step ability")


# ── Behavioral: enemy attacking shadow_stepped target dodges ────────

func test_attack_against_shadow_step_target_dodges() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var attacker: Combatant = _make("Goblin")
	var target: Combatant = _make("Rogue")
	target.add_status("shadow_step", 1)

	var dodged: bool = bm._target_dodges_physical(attacker, target)
	assert_true(dodged,
		"attack against shadow_step target must dodge (mirrors invisible 100% miss)")
	# Status must be consumed (falls-off semantic).
	assert_false("shadow_step" in target.status_effects,
		"shadow_step must be removed after the dodge fires (consumed on hit attempt)")


# ── Behavioral: caster with shadow_step gets guaranteed crit ────────

func test_shadow_step_caster_gets_guaranteed_crit() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var attacker: Combatant = _make("Rogue")
	attacker.add_status("shadow_step", 1)
	var crit_chance: float = bm._calculate_crit_chance(attacker)
	assert_eq(crit_chance, 1.0,
		"shadow_step caster must get guaranteed crit (1.0 crit chance)")


# ── Behavioral: vanilla attacker (no shadow_step) → normal crit calc ─

func test_vanilla_attacker_normal_crit() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var attacker: Combatant = _make("Fighter")
	attacker.status_effects.clear()
	var crit_chance: float = bm._calculate_crit_chance(attacker)
	# Should be base 0.05 + speed bonus (speed=10 → +0.10) = 0.15. Cap is 0.50.
	assert_lt(crit_chance, 1.0,
		"vanilla attacker must NOT get guaranteed crit — fix must not silently buff baseline")
