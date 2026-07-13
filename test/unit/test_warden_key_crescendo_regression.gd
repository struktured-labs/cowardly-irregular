extends GutTest

## Warden's Key crescendo (cowir-main msg 2481/2483): after Steal (or Mug's
## steal half) opens the vault, each successful Backstab or Mug hit further
## halves Vault-Cracked's defense modifier — "the crack widens." Engine
## caps at Combatant._get_effective_stat's base×0.25 floor, so the mechanic
## plateaus after Backstab 1 (Steal 0.5 → Backstab 1 0.25 → floor). Silent
## no-op past that.
##
## Design calls:
## - Mug (attack+steal in one action) fires both _apply_steal_response AND
##   counts for the crescendo — otherwise Mug is opener-only.
## - Scope tied to _steal_response_consumed meta so Rogue-in-party doesn't
##   cheese normal mobs with 3 Backstabs.
## - BossDialogue.get_backstab_widens_crack_line optional; log line fires
##   unconditionally when the deepen actually applies.

const CombatantScript = preload("res://src/battle/Combatant.gd")


func _make_target() -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = "TestTarget"
	c.max_hp = 260
	c.current_hp = 260
	c.defense = 30
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


## ── Guard: does nothing without steal_response consumed ────────────────

func test_deepen_no_op_when_steal_response_not_consumed() -> void:
	# The whole point of scoping to the Key path: normal Backstabs vs a
	# non-Warden target should NOT stack a defense break. If this guard
	# regresses, Rogue trivializes every fight.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	# Note: _steal_response_consumed NOT set. And no Vault-Cracked debuff exists.
	bm._maybe_deepen_warden_crack(caster, target, "backstab")
	assert_eq(target.active_debuffs.size(), 0,
		"Backstab against un-mugged target must not apply the debuff — mechanic is gated to key-stolen targets")


## ── Guard: ability id must be in WARDEN_CRACK_DEEPENERS ────────────────

func test_deepen_no_op_for_non_deepener_abilities() -> void:
	# Only Backstab/Mug count. Attack, Steal itself, or other abilities
	# don't trigger the crescendo. Otherwise Steal itself would deepen its
	# own effect on the same turn.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	target.add_debuff("Vault-Cracked", "defense", 0.5, 99)
	bm._maybe_deepen_warden_crack(caster, target, "attack")
	var d = target.active_debuffs[0]
	assert_almost_eq(float(d["modifier"]), 0.5, 0.001,
		"Attack must not deepen — WARDEN_CRACK_DEEPENERS gates to Backstab/Mug only")


## ── Backstab deepens 0.5 → 0.25 ────────────────────────────────────────

func test_backstab_halves_vault_cracked_modifier() -> void:
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	target.add_debuff("Vault-Cracked", "defense", 0.5, 99)
	bm._maybe_deepen_warden_crack(caster, target, "backstab")
	# Find the debuff again — refresh keeps it in place.
	var found: bool = false
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Vault-Cracked":
			assert_almost_eq(float(d["modifier"]), 0.25, 0.001,
				"Vault-Cracked must halve from 0.5 to 0.25 after first Backstab hit")
			assert_eq(int(d["remaining_turns"]), 99,
				"duration refreshes to 99 so the debuff can't tick out mid-fight while stacking")
			found = true
	assert_true(found, "Vault-Cracked debuff still exists after deepen")


func test_mug_also_deepens() -> void:
	# Mug counts for the crescendo — otherwise it becomes opener-only.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	target.add_debuff("Vault-Cracked", "defense", 0.5, 99)
	bm._maybe_deepen_warden_crack(caster, target, "mug")
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Vault-Cracked":
			assert_almost_eq(float(d["modifier"]), 0.25, 0.001,
				"Mug must halve just like Backstab — same mechanical role after key is stolen")


## ── Engine 25% floor: no further stacks past 0.25 ──────────────────────

func test_deepen_plateaus_at_engine_floor() -> void:
	# The engine caps effective stat at base×0.25 (Combatant._get_effective_stat).
	# Additional stacks past that no-op silently — don't spam Vault-Cracked
	# debuff writes that would show nothing to the player.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	target.add_debuff("Vault-Cracked", "defense", 0.25, 99)
	bm._maybe_deepen_warden_crack(caster, target, "backstab")
	for d in target.active_debuffs:
		if str(d.get("effect", "")) == "Vault-Cracked":
			assert_almost_eq(float(d["modifier"]), 0.25, 0.001,
				"modifier at floor must stay at 0.25 — further halving is engine-clamped anyway, don't fake progress")


## ── No Vault-Cracked debuff = no-op ────────────────────────────────────

func test_deepen_no_op_when_vault_cracked_missing() -> void:
	# If the steal_response was of a non-defense_break type (future
	# response_type variants), there's no Vault-Cracked to deepen. Skip
	# gracefully, don't add a random debuff.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var caster := _make_caster()
	var target := _make_target()
	target.set_meta("_steal_response_consumed", true)
	# no Vault-Cracked debuff added
	bm._maybe_deepen_warden_crack(caster, target, "backstab")
	assert_eq(target.active_debuffs.size(), 0,
		"no debuff to deepen = no debuff created — non-defense_break steal_response types stay safe")


## ── Source-pin: post-hit-loop call site + damage gate ──────────────────

func test_hit_loop_calls_deepen_after_damage_lands() -> void:
	# The call must live in the physical damage path AFTER the hit loop
	# closes and be gated on actual_damage > 0. Placing it inside the
	# hit loop would fire per internal hit (only matters for multi-hit
	# abilities, but future-proof); firing when 0 damage lands would
	# deepen the crack on absorbs/immunes which is wrong.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("_maybe_deepen_warden_crack(caster, target, str(ability.get(\"id\", \"\")))")
	assert_gt(idx, -1, "call site must exist in the physical damage path")
	var back: String = src.substr(maxi(0, idx - 200), 200)
	assert_string_contains(back, "if actual_damage > 0:",
		"crescendo must be gated on damage actually landing — absorbs / immunes shouldn't deepen the crack")


func test_mug_steal_success_calls_apply_steal_response() -> void:
	# Mug's steal success branch must fire _apply_steal_response — otherwise
	# a Mug that opens the fight never triggers the Warden's Key mechanic
	# and the crescendo never gets to start.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("mugs %d gold from %s")
	assert_gt(idx, -1, "Mug success log line must exist as anchor")
	var window: String = src.substr(idx, 400)
	assert_string_contains(window, "_apply_steal_response(_st)",
		"Mug's steal-success branch must fire the response — Steal and Mug are equally valid Key openers")


## ── Constant + helper surface ──────────────────────────────────────────

func test_warden_crack_deepeners_constant_declared() -> void:
	# Extensibility: shadow_strike, other Rogue tools could be added by
	# extending this const — no code change to _maybe_deepen_warden_crack
	# itself.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "const WARDEN_CRACK_DEEPENERS",
		"deepener list must be a named const so extension doesn't require touching the helper")
	assert_string_contains(src, "[\"backstab\", \"mug\"]",
		"tier-1 scope: Backstab (specialized) + Mug (opener also counts)")


func test_boss_dialogue_getter_for_widens_crack_line_declared() -> void:
	# Optional cowir-story pool. If the getter goes missing, the flavor
	# emit in _maybe_deepen_warden_crack silently no-ops (has_method guard).
	# Pin the getter so a future refactor doesn't drop it silently.
	var src: String = FileAccess.get_file_as_string("res://src/llm/BossDialogue.gd")
	assert_string_contains(src, "func get_backstab_widens_crack_line(boss_id: String) -> String:",
		"getter for backstab_widens_crack_lines must exist")
	assert_string_contains(src, "_random_pool_line(boss_id, \"backstab_widens_crack_lines\")",
		"getter keys on 'backstab_widens_crack_lines' — the pool cowir-story will author")
