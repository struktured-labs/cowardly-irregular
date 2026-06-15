extends GutTest

## Defensive regression: HeadlessBattleResolver._resolve_attack() and
## _resolve_attack_with_power() must guard the denominator of their
## smoothing formula `damage * damage / (damage + def)` against the
## zero-attack + zero-defense corner case.
##
## Bug shape:
##   • Combatant.take_damage uses the same formula and explicitly
##     guards `var denom = max(1, amount + def_value)` (Combatant.gd
##     ~line 182) — autogrind's headless mirror didn't.
##   • Combatant.get_buffed_stat returns 0 for a base-0 stat (the
##     `maxi(1, …)` clamp only fires when base > 0). So an attacker
##     with attack == 0 (a stat-zero monster, or a debuffed PC at the
##     0.25× floor) hitting a target with defense == 0 (low-tier
##     monsters routinely have defense 0..3) produces:
##       damage = float(0) * randf_range(0.85, 1.15) = 0.0
##       def_val = float(0) = 0.0
##       (0 * 0) / (0 + 0) = 0/0 = NaN
##     int(NaN) returns INT_MIN, then max(1, INT_MIN) clamps to 1.
##     The result LOOKS sane (1 damage) but silently produced through
##     a NaN — any future tweak to the post-cast math (target HP
##     comparison, damage scaling, hp_changed signal payload) inherits
##     the NaN. Plus Godot prints a runtime divide-by-zero error.
##
## Fix: `var denom = maxf(1.0, damage + def_val)` — minimum 1 so the
## division is always well-defined. Mirrors Combatant.take_damage.
##
## Tests:
##   • Source pin: _resolve_attack uses maxf(1.0, ...) on the divisor
##   • Source pin: _resolve_attack_with_power uses the same guard
##   • Negative source pin: the bare division shape `(damage + def_val)`
##     in the divisor must NOT appear without the maxf guard in the
##     two functions
##   • Behavioural: a stat-zero attacker hitting a stat-zero target
##     resolves to a finite positive damage int (not NaN-as-INT_MIN)

const RESOLVER_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_resolve_attack_guards_divisor() -> void:
	var text := _read(RESOLVER_PATH)
	var idx := text.find("func _resolve_attack(attacker")
	assert_gt(idx, -1, "_resolve_attack must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("maxf(1.0, damage + def_val)"),
		"_resolve_attack must guard `damage + def_val` with maxf(1.0, …) to avoid 0/0")


func test_resolve_attack_with_power_guards_divisor() -> void:
	var text := _read(RESOLVER_PATH)
	var idx := text.find("func _resolve_attack_with_power")
	assert_gt(idx, -1, "_resolve_attack_with_power must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("maxf(1.0, dmg + def_val)"),
		"_resolve_attack_with_power must guard `dmg + def_val` with maxf(1.0, …)")


func test_no_bare_division_by_damage_plus_def_in_either_resolver() -> void:
	# Lint: neither function may divide by the raw sum without the maxf guard.
	# Walk both functions' non-comment code and assert the buggy shape is gone.
	var text := _read(RESOLVER_PATH)
	for fn_name in ["func _resolve_attack(attacker", "func _resolve_attack_with_power"]:
		var idx := text.find(fn_name)
		var rest := text.substr(idx)
		var next_fn := rest.find("\nfunc ", 1)
		var body := rest.substr(0, next_fn) if next_fn > -1 else rest
		# Strip comments so the teaching doc can cite the legacy shape.
		var lines := body.split("\n")
		var code_only: PackedStringArray = PackedStringArray()
		for line in lines:
			var ln: String = str(line)
			if ln.strip_edges().begins_with("#"):
				continue
			code_only.append(ln)
		var code := "\n".join(code_only)
		assert_false(code.contains("(damage + def_val)") and not code.contains("maxf(1.0, damage + def_val)"),
			"%s must NOT use the bare (damage + def_val) divisor" % fn_name)
		assert_false(code.contains("(dmg + def_val)") and not code.contains("maxf(1.0, dmg + def_val)"),
			"%s must NOT use the bare (dmg + def_val) divisor" % fn_name)


# ── Behavioural ──────────────────────────────────────────────────────────────

const ResolverScript := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _make_combatant(name: String, atk: int, def_: int, hp: int = 100) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name
	c.max_hp = hp
	c.attack = atk
	c.defense = def_
	c.speed = 10
	add_child_autofree(c)
	# Combatant._ready resets current_hp to max_hp on add_child.
	c.current_hp = hp
	c.is_alive = hp > 0
	return c


func test_zero_attack_zero_defense_resolves_without_nan() -> void:
	# Drive _resolve_attack on the canonical degenerate case: attacker
	# with attack == 0 hitting a target with defense == 0. Pre-fix the
	# divisor was 0.0 → 0/0 = NaN → int(NaN) → INT_MIN → max(1, INT_MIN)
	# = 1. So the FUNCTION still returned a sane int, but only because
	# max(1, …) clamped a NaN-cast value. The fix makes the math
	# itself well-defined.
	var atk := _make_combatant("ZeroAtk", 0, 5)
	var tgt := _make_combatant("ZeroDef", 5, 0)
	var resolver := ResolverScript.new()
	# The function does randf_range / crit roll internally, so we just
	# assert the result is a finite, positive int (no NaN cascade).
	var result: int = resolver._resolve_attack(atk, tgt)
	# Result must be 1 (the max(1, …) floor) since 0 damage smooths to 0
	# before the floor. Critically it must NOT be INT_MIN / 0 / negative.
	assert_gte(result, 1,
		"_resolve_attack with zero-attack vs zero-defense must return >= 1 (not a NaN-cast sentinel)")
	# Target HP must have decreased by exactly the returned damage —
	# a NaN would have propagated into take_damage's HP math.
	assert_eq(tgt.current_hp, 100 - result,
		"target current_hp must equal max_hp - returned damage (no NaN propagation through take_damage)")
