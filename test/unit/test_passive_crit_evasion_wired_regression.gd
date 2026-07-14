extends GutTest

## tick 375: passive `crit_chance` and `evasion` stat_mods now actually
## affect combat.
##
## Pre-fix (two distinct bugs):
##
## BUG A — crit_chance code/data divergence:
##   _calculate_crit_chance hardcoded `if "critical_strike" in
##   attacker.equipped_passives: passive_bonus += 0.10`, but
##   data/passives.json authored critical_strike with stat_mods.crit_chance
##   = 0.25 (additive +25%). The hardcoded +0.10 silently nerfed the
##   passive by 15 points and ignored any future passive adding
##   crit_chance entirely.
##
## BUG B — evasion passive completely silent:
##   PassiveSystem accumulated evasion (passive `evasion_up`: 0.20)
##   into total_mods. StatusMenu rendered "Evasion: 20%". But the
##   _target_dodges_physical check only consulted the temporary
##   "evasion" STATUS effect (from abilities like Smoke Bomb), never
##   the passive mod — players equipped evasion_up expecting +20%
##   dodge and got nothing.
##
## Post-fix routes both through PassiveSystem.get_passive_mods, clamped
## to [0.0, 0.50] safety bands (50% crit cap matches the existing
## codepath cap; 50% dodge cap so stacked passive bundles can't make
## a target untouchable).
##
## Symmetric with ticks 373 (healing_multiplier) and 374
## (mp_cost_multiplier) — closes the known-broken slots of
## PassiveSystem.get_passive_mods.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: crit_chance read from passive_mods accumulator ──────

func test_crit_chance_reads_passive_mods() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _calculate_crit_chance")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("get_passive_mods(attacker)"),
		"_calculate_crit_chance must consult PassiveSystem.get_passive_mods")
	assert_true(body.contains("mods.get(\"crit_chance\""),
		"_calculate_crit_chance must read crit_chance from accumulator (was unused pre-fix)")
	# Negative pin: hardcoded +0.10 for critical_strike must be gone.
	assert_false(body.contains("passive_bonus += 0.10"),
		"hardcoded `passive_bonus += 0.10` must be removed — that was the code/data divergence")


# ── Source pin: passive evasion wired into dodge check ──────────────

func test_evasion_passive_wired_into_dodge_check() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _target_dodges_physical")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("get_passive_mods(target)"),
		"_target_dodges_physical must consult PassiveSystem.get_passive_mods for the TARGET")
	assert_true(body.contains("mods.get(\"evasion\""),
		"_target_dodges_physical must read evasion from accumulator (silent no-op pre-fix)")
	# The clamp must cap dodge probability so a stacked bundle can't
	# trivialize boss attacks.
	assert_true(body.contains("0.0, 0.50"),
		"passive evasion dodge must clamp to [0.0, 0.50] — preventing untouchable stacks")


# ── Behavioral: critical_strike passive grants its authored crit_chance

func test_critical_strike_passive_grants_authored_crit() -> void:
	# Confirm data file value is what we test against (so a future
	# rebalance that lowers the number invalidates this test cleanly).
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("critical_strike"):
		pending("data/passives.json must include critical_strike")
		return
	var stat_mods: Dictionary = ps.passives["critical_strike"].get("stat_mods", {})
	var authored_crit: float = float(stat_mods.get("crit_chance", 0.0))
	assert_gt(authored_crit, 0.0,
		"critical_strike passive must author a crit_chance stat_mod — base requirement for this fix")

	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Crit", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 0,
	})
	add_child_autofree(c)
	c.equipped_passives = ["critical_strike"]

	var crit_chance: float = bm._calculate_crit_chance(c)
	# Base 0.05 + speed_bonus (0) + passive_bonus = 0.05 + authored_crit.
	var expected_min: float = 0.05 + authored_crit - 0.001  # small epsilon for float compare
	# Capped at 0.50 by the existing cap.
	var expected: float = min(0.05 + authored_crit, 0.50)
	assert_almost_eq(crit_chance, expected, 0.01,
		"critical_strike crit chance must equal base + authored mod (clamped at 0.50)")
	# Pre-fix hardcoded +0.10 → 0.15. Post-fix uses authored 0.25 → 0.30.
	# This pin assumes authored > 0.10 (which it is, at 0.25). If
	# someone rebalances down below 0.10 they'd need to update this.
	if authored_crit > 0.10:
		assert_gt(crit_chance, 0.15,
			"crit_chance > 0.15 confirms post-fix authored value used (pre-fix was 0.15 with hardcoded +0.10)")


# ── Behavioral: no passives = base crit chance only ─────────────────

func test_no_passives_no_crit_bonus() -> void:
	# Regression guard: don't silently buff combatants without crit passives.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Vanilla", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 0,
	})
	add_child_autofree(c)
	c.equipped_passives = []
	var crit_chance: float = bm._calculate_crit_chance(c)
	assert_almost_eq(crit_chance, 0.05, 0.01,
		"no passives + 0 speed = base 5% crit only")


# ── Source pin: critical_strike list of equipped_passives check remains for legacy data ─

func test_critical_strike_hardcode_replaced_with_accumulator_read() -> void:
	# The pre-fix code was an `if "critical_strike" in
	# attacker.equipped_passives` check that ADDED +0.10 unconditionally.
	# Pin that the executable form of that check is gone — substring
	# search misses comments referencing "critical_strike" by name.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _calculate_crit_chance")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_false(body.contains("\"critical_strike\" in attacker.equipped_passives"),
		"the hardcoded `\"critical_strike\" in equipped_passives` check must be removed")
	assert_false(body.contains("passive_bonus += 0.10"),
		"the hardcoded +0.10 boost must be removed")
