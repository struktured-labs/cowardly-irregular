extends GutTest

## Warden's Key crescendo, vulnerability-shape (cowir-main msg 2485).
##
## Option 3 rewrite of the msg 2481/2483 mechanic. Instead of halving
## defense (which hit the engine's base×0.25 stat floor after one stack),
## the target gets a "Vault Crack" vulnerability debuff (stat="incoming_
## damage") that ADDITIVELY stacks per successful Backstab / Mug hit.
## Unclamped: each hit lands harder than the last, smooth crescendo.
##
## Numerics: Steal → +50%, each Backstab/Mug → +25% additive.
## Boss 260 HP, Backstab base ~30 → ~45, 52, 60, 67 per hit post-Steal.
##
## Design calls preserved from msg 2481/2483:
## - Mug (attack+steal in one action) fires both _apply_steal_response AND
##   counts for the crescendo.
## - Scope tied to _steal_response_consumed meta.
## - BossDialogue.get_backstab_widens_crack_line optional flavor pool.

const CombatantScript = preload("res://src/battle/Combatant.gd")


func _make_target() -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = "TestTarget"
	c.max_hp = 260
	c.current_hp = 260
	c.defense = 30
	c.attack = 40
	c.is_alive = true
	c.set_meta("monster_type", "rogue_lockward")
	add_child_autofree(c)
	return c


func _make_caster() -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = "Rogue"
	c.is_alive = true
	add_child_autofree(c)
	return c


## ── Combatant vulnerability primitives ─────────────────────────────────

func test_add_stacking_vulnerability_creates_debuff_with_incoming_damage_stat() -> void:
	var t := _make_target()
	t.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	assert_eq(t.active_debuffs.size(), 1)
	var d: Dictionary = t.active_debuffs[0]
	assert_eq(str(d.get("effect", "")), "Vault Crack")
	assert_eq(str(d.get("stat", "")), "incoming_damage",
		"stat name is the contract with get_incoming_damage_multiplier — reads this exact key")
	assert_almost_eq(float(d.get("modifier", 0.0)), 0.5, 0.001)
	assert_eq(int(d.get("remaining_turns", 0)), 99)


func test_add_stacking_vulnerability_stacks_additively_not_replace() -> void:
	# Unlike add_debuff (which refreshes / upgrades to a stronger modifier),
	# stacking must ADD. Two calls of +0.25 land at 0.5 total, not 0.25.
	var t := _make_target()
	t.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	t.add_stacking_vulnerability("Vault Crack", 0.25, 99)
	assert_eq(t.active_debuffs.size(), 1, "same effect name refreshes in place — no dup debuffs")
	var d: Dictionary = t.active_debuffs[0]
	assert_almost_eq(float(d["modifier"]), 0.75, 0.001,
		"0.5 + 0.25 = 0.75 — additive, not max/replace")


func test_get_incoming_damage_multiplier_sums_all_vulnerability_stacks() -> void:
	# The multiplier should sum every stat="incoming_damage" debuff (across
	# effects, not just one), so future independent vulnerabilities compose.
	var t := _make_target()
	t.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	# Manually add a second unrelated vulnerability effect (simulated).
	t.add_stacking_vulnerability("Marked", 0.20, 99)
	var mult: float = t.get_incoming_damage_multiplier()
	assert_almost_eq(mult, 1.70, 0.001,
		"1.0 baseline + 0.5 Vault Crack + 0.20 Marked = 1.70")


func test_get_incoming_damage_multiplier_baseline_is_one() -> void:
	var t := _make_target()
	assert_almost_eq(t.get_incoming_damage_multiplier(), 1.0, 0.001,
		"no vulnerability = 1.0 baseline (no damage change)")


func test_incoming_damage_debuff_does_not_affect_defense() -> void:
	# stat="incoming_damage" must NOT be picked up by get_buffed_stat as a
	# defense debuff — otherwise the vulnerability would DOUBLE-count via
	# both the multiplier AND the stat clamp.
	var t := _make_target()
	t.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	var eff_def: int = t.get_buffed_stat("defense", 30)
	assert_eq(eff_def, 30,
		"defense stat must be unchanged — incoming_damage is a distinct stat, not a defense debuff")


## ── take_damage applies vulnerability multiplier ───────────────────────

func test_take_damage_uncracked_baseline() -> void:
	# Baseline: no vulnerability, take_damage's formula produces some value X.
	# We just need the SAME setup to compare vs the vulnerable case below.
	var t := _make_target()
	var dmg: int = t.take_damage(100)
	assert_gt(dmg, 0)
	# Sanity: within a reasonable range given the attack² / (attack + def) formula.
	assert_gt(dmg, 50, "baseline 100-amount hit should land significant damage against def 30")


func test_take_damage_amplified_by_vault_crack() -> void:
	# +50% vulnerability should visibly increase actual damage taken vs
	# the baseline. Not testing the exact formula output — just monotone
	# ordering: cracked > baseline.
	var baseline := _make_target()
	var cracked := _make_target()
	cracked.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	var d_base: int = baseline.take_damage(100)
	var d_cracked: int = cracked.take_damage(100)
	assert_gt(d_cracked, d_base,
		"cracked target must take MORE damage from the same raw amount")


func test_take_damage_amplification_scales_with_stack_count() -> void:
	# More stacks → more damage. Monotone with stack count, no plateau.
	var one_stack := _make_target()
	var three_stacks := _make_target()
	one_stack.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	three_stacks.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	three_stacks.add_stacking_vulnerability("Vault Crack", 0.25, 99)
	three_stacks.add_stacking_vulnerability("Vault Crack", 0.25, 99)
	var d_one: int = one_stack.take_damage(100)
	var d_three: int = three_stacks.take_damage(100)
	assert_gt(d_three, d_one,
		"three vulnerability stacks (1.0+0.5+0.25+0.25 = 2.0x) must exceed one stack (1.5x) — no plateau")


## ── BattleManager _apply_steal_response uses vulnerability ─────────────

func test_apply_steal_response_installs_vault_crack_vulnerability() -> void:
	# The rewrite: _apply_steal_response's vulnerability branch applies
	# add_stacking_vulnerability, NOT add_debuff on defense. If a future
	# refactor reverts, all crescendo damage math breaks.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var t := _make_target()
	bm._apply_steal_response(t)
	var found: bool = false
	for d in t.active_debuffs:
		if str(d.get("effect", "")) == "Vault Crack":
			found = true
			assert_eq(str(d.get("stat", "")), "incoming_damage",
				"must be a vulnerability debuff, not a defense debuff")
			assert_almost_eq(float(d.get("modifier", 0.0)), 0.5, 0.001,
				"rogue_lockward.steal_response.modifier is 0.5 = +50% initial crack")
	assert_true(found, "Vault Crack vulnerability must be installed on successful steal_response")
	assert_true(t.has_meta("_steal_response_consumed") and bool(t.get_meta("_steal_response_consumed")),
		"one-shot guard meta must still be set")


func test_apply_steal_response_is_one_shot_per_fight() -> void:
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var t := _make_target()
	bm._apply_steal_response(t)
	bm._apply_steal_response(t)  # second call
	# Modifier should be 0.5, not 1.0 — second call was blocked by the meta guard.
	for d in t.active_debuffs:
		if str(d.get("effect", "")) == "Vault Crack":
			assert_almost_eq(float(d["modifier"]), 0.5, 0.001,
				"second _apply_steal_response must be a no-op via the meta guard")


## ── Crescendo: Backstab / Mug stack additively ─────────────────────────

func test_backstab_stacks_25_percent() -> void:
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	# Pre-condition: Warden's Key already stolen (Steal fired first).
	target.set_meta("_steal_response_consumed", true)
	target.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	bm._maybe_deepen_warden_crack(caster, target, "backstab")
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Vault Crack":
			assert_almost_eq(float(d["modifier"]), 0.75, 0.001,
				"0.5 + 0.25 stack delta = 0.75 = +75% incoming damage after Backstab 1")


func test_mug_stacks_same_25_percent() -> void:
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	target.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	bm._maybe_deepen_warden_crack(caster, target, "mug")
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Vault Crack":
			assert_almost_eq(float(d["modifier"]), 0.75, 0.001,
				"Mug must stack the same way as Backstab — msg 2483 design call")


func test_crescendo_never_plateaus_no_engine_floor() -> void:
	# Whole point of Option 3: no plateau. Ten Backstabs = ten stacks.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	target.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	for i in range(10):
		bm._maybe_deepen_warden_crack(caster, target, "backstab")
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Vault Crack":
			assert_almost_eq(float(d["modifier"]), 0.5 + 10 * 0.25, 0.001,
				"10 stacks = 0.5 base + 2.5 delta = 3.0 = +300% incoming damage. No plateau, no cap.")


## ── Guards preserved from msg 2481/2483 ────────────────────────────────

func test_deepen_no_op_when_steal_response_not_consumed() -> void:
	# Scope: normal Backstabs against non-Warden targets don't cheese mobs.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	# _steal_response_consumed NOT set.
	bm._maybe_deepen_warden_crack(caster, target, "backstab")
	assert_eq(target.active_debuffs.size(), 0,
		"gate on _steal_response_consumed must hold — no debuff applied without the Key opener")


func test_deepen_no_op_for_non_deepener_ability() -> void:
	# Only Backstab/Mug in WARDEN_CRACK_DEEPENERS.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	target.add_stacking_vulnerability("Vault Crack", 0.5, 99)
	bm._maybe_deepen_warden_crack(caster, target, "attack")
	# Modifier should be 0.5 still (unchanged), not 0.75.
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Vault Crack":
			assert_almost_eq(float(d["modifier"]), 0.5, 0.001,
				"plain attack must not deepen — kit-scoped to Rogue's signature")


func test_deepen_no_op_when_vault_crack_missing() -> void:
	# Future non-vulnerability steal_response types stay unaffected.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	# no Vault Crack — target was cracked with a hypothetical future response type
	bm._maybe_deepen_warden_crack(caster, target, "backstab")
	assert_eq(target.active_debuffs.size(), 0,
		"no debuff to deepen = no debuff created — never invents a Vault Crack out of nothing")


## ── Wiring pins ────────────────────────────────────────────────────────

func test_hit_loop_calls_deepen_after_damage_lands() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("_maybe_deepen_warden_crack(caster, target, str(ability.get(\"id\", \"\")))")
	assert_gt(idx, -1, "call site must exist in the physical damage path")
	var back: String = src.substr(maxi(0, idx - 200), 200)
	assert_string_contains(back, "if actual_damage > 0:",
		"crescendo must be gated on damage actually landing — absorbs / immunes shouldn't deepen the crack")


func test_mug_steal_success_calls_apply_steal_response() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("mugs %d gold from %s")
	assert_gt(idx, -1, "Mug success log line must exist as anchor")
	var window: String = src.substr(idx, 400)
	assert_string_contains(window, "_apply_steal_response(_st)",
		"Mug's steal-success branch must fire the response — Mug is also a Warden's Key opener")


func test_warden_crack_deepeners_const_declared() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "const WARDEN_CRACK_DEEPENERS",
		"deepener list must be a named const so extension doesn't require touching the helper")
	assert_string_contains(src, "[\"backstab\", \"mug\"]",
		"tier-1 scope: Backstab (specialized) + Mug (opener also counts)")


func test_warden_crack_stack_delta_declared() -> void:
	# The +25% per hit is the tuning knob — struktured may want to shift.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "const WARDEN_CRACK_STACK_DELTA: float = 0.25",
		"per-hit stack delta must be a named const for tuning")


func test_lockward_response_type_is_vulnerability() -> void:
	# Data-side pin: rogue_lockward switched from "defense_break" to
	# "vulnerability". If someone reverts, _apply_steal_response's match
	# branch silently misses (falls through to unknown-type push_warning).
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var r: Dictionary = data["rogue_lockward"]["steal_response"]
	assert_eq(str(r.get("type", "")), "vulnerability",
		"Option 3 rewrite: type moved from defense_break to vulnerability. Old string breaks silently.")


func test_boss_dialogue_getter_for_widens_crack_line_declared() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/llm/BossDialogue.gd")
	assert_string_contains(src, "func get_backstab_widens_crack_line(boss_id: String) -> String:",
		"getter for backstab_widens_crack_lines must exist")
	assert_string_contains(src, "_random_pool_line(boss_id, \"backstab_widens_crack_lines\")",
		"getter keys on 'backstab_widens_crack_lines'")


## ── Balance pass (msg 2486) ────────────────────────────────────────────

func test_lockward_hp_tuned_for_crescendo() -> void:
	# msg 2486 balance: Lockward HP 260 → 200 to hit the 6-8 round win-tempo
	# spec with the vulnerability-shape crescendo. Math at Rogue level 4-5
	# (attack 14-18 base 12 × 1.16 level growth + gear): Backstab base
	# 28-36, post-Steal weighted expected 29-42 per hit blend with 30%
	# crit. 4 Backstabs kill 200 HP at middle-attack (~150-170 damage +
	# variance), 5 at low-attack. Total rounds = Steal + 4-5 Backstabs +
	# 1-2 Defer-for-Counter-Stance = 6-8 rounds. If someone accidentally
	# reverts to 260 during a data pass, the fight becomes grindy again.
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var stats: Dictionary = data["rogue_lockward"]["stats"]
	assert_eq(int(stats.get("max_hp", -1)), 200,
		"Lockward HP must be 200 per msg 2486 balance pass — tighter tempo for the crescendo shape")
