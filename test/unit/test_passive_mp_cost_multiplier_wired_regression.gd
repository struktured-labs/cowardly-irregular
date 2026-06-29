extends GutTest

## tick 374: passive `mp_cost_multiplier` mod now actually affects
## ability MP cost.
##
## Pre-fix:
##   - PassiveSystem.get_passive_mods accumulated mp_cost_multiplier
##     into the total_mods dict (default 1.0).
##   - JobSystem.can_use_ability checked `combatant.current_mp <
##     ability["mp_cost"]` directly.
##   - BattleManager._execute_ability spent `ability.get("mp_cost", 0)`
##     directly.
##   - BattleManager enemy AI line ~1176 ditto.
##
## Three passives (mp_efficiency 0.75x, magic_amplifier 2.5x,
## elemental_affinity 0.75x) were COMPLETELY SILENT no-ops. Players
## equipped mp_efficiency expecting -25% MP cost and got nothing.
##
## Post-fix introduces JobSystem.get_ability_mp_cost(combatant, ability_id)
## as the canonical MP-cost resolver. Applies the passive multiplier
## clamped to [0.1, 10.0] (matching healing/damage clamps), routes all
## three call sites through it.
##
## Symmetric with tick 373's healing_multiplier wiring fix.

const JOB_SYSTEM_PATH := "res://src/jobs/JobSystem.gd"
const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: get_ability_mp_cost helper exists ───────────────────

func test_get_ability_mp_cost_helper_exists() -> void:
	var src := _read(JOB_SYSTEM_PATH)
	assert_true(src.contains("func get_ability_mp_cost(combatant: Combatant, ability_id: String) -> int"),
		"JobSystem must expose get_ability_mp_cost(combatant, ability_id) as the canonical resolver")
	assert_true(src.contains("mp_cost_multiplier"),
		"get_ability_mp_cost must consult mp_cost_multiplier")
	assert_true(src.contains("0.1, 10.0"),
		"mp_cost_multiplier must clamp to [0.1, 10.0] safety band")


# ── Source pin: can_use_ability routes through the helper ───────────

func test_can_use_ability_routes_through_helper() -> void:
	var src := _read(JOB_SYSTEM_PATH)
	var fn_idx: int = src.find("func can_use_ability(combatant: Combatant, ability_id: String)")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("get_ability_mp_cost(combatant, ability_id)"),
		"can_use_ability must check the multiplied cost — pre-fix read ability.mp_cost directly")
	# Negative pin: bare direct read must be gone.
	assert_false(body.contains("combatant.current_mp < ability[\"mp_cost\"]"),
		"bare `current_mp < ability['mp_cost']` direct read must be removed")


# ── Source pin: BattleManager._execute_ability routes through helper ─

func test_battle_manager_execute_ability_routes_through_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_ability(caster: Combatant, ability_id: String")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("JobSystem.get_ability_mp_cost(caster, ability_id)"),
		"_execute_ability must spend the multiplied cost — divergence between can_use_ability and _execute_ability would let mp_efficiency bypass the gate then spend the unmultiplied amount")


# ── Source pin: BattleManager enemy-AI affordability check too ──────

func test_enemy_ai_affordability_routes_through_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# This is the only OTHER mp_cost-affordability site in BattleManager.
	# Pin that JobSystem.get_ability_mp_cost is referenced near the line.
	assert_true(src.contains("JobSystem.get_ability_mp_cost(combatant, ability_id)"),
		"Enemy AI affordability check must also route through the helper for parity")


# ── Behavioral: mp_efficiency reduces cost ──────────────────────────

func test_mp_efficiency_passive_reduces_mp_cost() -> void:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if js == null or ps == null:
		pending("JobSystem and PassiveSystem autoloads required for this test")
		return
	if not ps.passives.has("mp_efficiency"):
		pending("data/passives.json must include mp_efficiency")
		return
	# Pick any ability with a non-zero mp_cost. Heal is a common cleric
	# ability — try it first, fall back to scanning.
	var test_ability_id: String = ""
	for ability_id in js.abilities:
		var ab: Dictionary = js.abilities[ability_id]
		if int(ab.get("mp_cost", 0)) >= 4:
			test_ability_id = ability_id
			break
	if test_ability_id == "":
		pending("no ability with mp_cost >= 4 found — can't test multiplier")
		return
	var base_mp_cost: int = int(js.abilities[test_ability_id].get("mp_cost", 0))

	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "MpEfficient", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	c.equipped_passives = ["mp_efficiency"]  # 0.75x mp_cost

	var got_cost: int = js.get_ability_mp_cost(c, test_ability_id)
	# Pre-fix: base_mp_cost. Post-fix: round(base_mp_cost * 0.75).
	var expected: int = int(round(base_mp_cost * 0.75))
	assert_eq(got_cost, expected,
		"mp_efficiency must reduce '%s' cost from %d to %d (0.75x)" % [test_ability_id, base_mp_cost, expected])
	assert_lt(got_cost, base_mp_cost,
		"mp_efficiency must produce strictly LOWER cost than base — was a silent no-op pre-fix")


# ── Behavioral: no passives = base cost (regression guard) ──────────

func test_no_passive_returns_base_cost() -> void:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null:
		pending("JobSystem autoload required for this test")
		return
	var test_ability_id: String = ""
	for ability_id in js.abilities:
		var ab: Dictionary = js.abilities[ability_id]
		if int(ab.get("mp_cost", 0)) >= 4:
			test_ability_id = ability_id
			break
	if test_ability_id == "":
		pending("no ability with mp_cost >= 4 found")
		return
	var base_mp_cost: int = int(js.abilities[test_ability_id].get("mp_cost", 0))

	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Vanilla", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	c.equipped_passives = []  # no passives

	assert_eq(js.get_ability_mp_cost(c, test_ability_id), base_mp_cost,
		"no passives must return the unmultiplied base mp_cost (no silent buff)")


# ── Behavioral: ability with 0 mp_cost stays 0 ──────────────────────

func test_zero_mp_cost_ability_stays_zero() -> void:
	# Free abilities (basic attack, Strike, Pray, etc.) must not be
	# spuriously multiplied into a positive cost.
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null:
		pending("JobSystem autoload required for this test")
		return
	# Find a 0-cost ability if one exists in the data.
	var zero_ability_id: String = ""
	for ability_id in js.abilities:
		var ab: Dictionary = js.abilities[ability_id]
		if int(ab.get("mp_cost", 0)) == 0:
			zero_ability_id = ability_id
			break
	if zero_ability_id == "":
		# Synthesize a transient test ability.
		js.abilities["__tick374_zero_cost__"] = {"name": "Zero", "mp_cost": 0}
		zero_ability_id = "__tick374_zero_cost__"

	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "TestZero", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	c.equipped_passives = []

	assert_eq(js.get_ability_mp_cost(c, zero_ability_id), 0,
		"0 mp_cost ability must stay 0 (no multiplier inflation)")

	if zero_ability_id == "__tick374_zero_cost__":
		js.abilities.erase("__tick374_zero_cost__")
