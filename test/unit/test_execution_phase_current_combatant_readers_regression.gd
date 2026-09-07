extends GutTest

## msg 2749 cycle 12 — cowir-main's showcase gate fix (57269663) proved
## BattleManager.current_combatant is stale/null during the execution
## phase. That fix covered ONE reader; this cycle audits every other
## execution-phase reader and either:
##   (a) routes it through the action_executing signal args, or
##   (b) caches those args on scene entry and consults the cache.
##
## Selection-phase readers are SAFE — the field IS the selecting PC and
## it's stable until selection_turn_ended. Every read on a menu handler
## (_on_win98_actions_submitted, _on_ability_pressed, etc.) is fine.
##
## Execution-phase readers found in this audit:
##   BattleScene._on_damage_dealt line ~4139  crit-quip attribution
##   BattleScene._on_damage_dealt line ~4177  weapon-hit SFX
##   BattleScene._get_current_combatant_animator (via _play_ability_animation)
##
## FIX: cache signal-arg combatant in _last_acting_combatant, set in
## _on_action_executing, cleared in _on_action_executed. Handlers read
## the cache instead of the manager field. Status-tick damage_dealt emits
## (poison at round end, reactive counter outside the action window)
## now attribute to null — which correctly no-ops weapon SFX and skips
## crit quips, matching the "no acting combatant" fact.
##
## FOLLOW-UP (not this cycle): EffectSystem._play_effect_sound reads
## BattleManager.current_combatant at lines 192/195 for the weapon-type
## SFX in PHYSICAL effects. Same class but EffectSystem is an autoload
## with no easy access to BS state; the fix wants a public property on
## BattleManager (auto-managed by the same signal) or a caller-provided
## weapon_type. Deferred.

const BS_PATH: String = "res://src/battle/BattleScene.gd"


## ── The cache surface ─────────────────────────────────────────────────

func test_cache_field_declared() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "var _last_acting_combatant: Combatant = null",
		"the cache field must exist so signal-arg attribution is stable across handlers")


func test_cache_set_on_action_executing() -> void:
	# The signal-arg combatant must land in the cache — otherwise every
	# damage_dealt handler sees stale/null and falls through to the
	# BattleManager field the fix was meant to avoid.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _on_action_executing(combatant: Combatant, action: Dictionary) -> void:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1500)
	assert_string_contains(body, "_last_acting_combatant = combatant",
		"_on_action_executing must cache the signal-arg combatant")


func test_cache_cleared_on_action_executed() -> void:
	# Clearing MATTERS: without it, a status-tick damage_dealt emit that
	# fires OUTSIDE an action window (poison at round-end, reactive
	# counter) would attribute to the LAST completed action's combatant.
	# Crit quips would fire on wrong PC, weapon SFX would play for wrong
	# weapon type.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _on_action_executed(combatant: Combatant, action: Dictionary, targets: Array) -> void:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2000)
	assert_string_contains(body, "_last_acting_combatant = null",
		"_on_action_executed must clear the cache so out-of-action damage_dealt emits attribute to null")


## ── The three swapped reads ───────────────────────────────────────────

func test_on_damage_dealt_no_manager_field_read() -> void:
	# The whole point: _on_damage_dealt fires from a signal during
	# execution, and the field it USED to read is stale during that
	# window. A textual pin catches a future refactor that reverts.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _on_damage_dealt(target: Combatant, amount: int, is_crit: bool")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_false(body.find("BattleManager.current_combatant") > -1,
		"_on_damage_dealt must not read BattleManager.current_combatant — use _last_acting_combatant (msg 2749 cycle 12)")


func test_on_damage_dealt_reads_cache_for_crit_quip() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("# Crit quip from the attacker")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 500)
	assert_string_contains(window, "var attacker = _last_acting_combatant",
		"crit-quip attribution must read the signal-arg cache")


func test_on_damage_dealt_reads_cache_for_weapon_sfx() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("# Skip hit sounds for abilities — ability sound already played at cast time")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 500)
	assert_string_contains(window, "var attacker = _last_acting_combatant",
		"weapon-hit SFX must read the signal-arg cache")
	# Also gate the SFX call on non-null attacker — status-tick emits arrive with cache=null and shouldn't play a phantom weapon SFX.
	assert_string_contains(window, "if attacker == null:",
		"null-attacker guard must skip the weapon SFX (poison ticks aren't attacks)")


func test_get_current_combatant_animator_prefers_cache() -> void:
	# The animator lookup runs from _play_ability_animation during
	# execution — must not depend on the stale field.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _get_current_combatant_animator() -> BattleAnimatorClass:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 800)
	assert_string_contains(body, "var current = _last_acting_combatant",
		"animator lookup must prefer the cache over BattleManager.current_combatant during execution")
	# But it MAY fall back to the field when the cache is empty (selection phase — the field IS the current selector).
	assert_string_contains(body, "current = BattleManager.current_combatant",
		"selection-phase fallback preserved — the field is authoritative when no action is executing")


## ── Ratchet: no NEW execution-phase readers slip in ───────────────────

func test_execution_only_signal_handlers_do_not_read_manager_field() -> void:
	# Guard against a future refactor adding a new BattleManager.current_
	# combatant read inside a signal-driven handler that runs ONLY during
	# execution. _on_damage_dealt is the canonical case — the field is
	# always stale/null there because damage_dealt emits from inside an
	# action's execution.
	#
	# NOT in this list: _get_current_combatant_animator (dual-purpose,
	# has a documented selection-phase fallback pinned separately by
	# test_get_current_combatant_animator_prefers_cache above);
	# _play_ability_animation (calls _get_current_combatant_animator
	# indirectly).
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var execution_only_functions: Array = [
		"func _on_damage_dealt(",
	]
	for signature in execution_only_functions:
		var idx: int = src.find(signature)
		if idx == -1:
			continue
		var next: int = src.find("\nfunc ", idx + 1)
		var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
		assert_false(body.find("BattleManager.current_combatant") > -1,
			"execution-only handler `%s` must not read BattleManager.current_combatant (msg 2749 cycle 12)" % signature)


## ── EffectSystem follow-up: fixed in msg 2754 cycle 14 (option b) ─────

func test_effect_system_no_longer_reads_battle_manager_current_combatant() -> void:
	# Cycle 12 flagged EffectSystem._play_effect_sound reading
	# BattleManager.current_combatant for PHYSICAL-effect weapon SFX as
	# a deferred follow-up. Cycle 14 (msg 2754) shipped option (b):
	# weapon_type is now a caller-provided param on spawn_effect. This
	# pin ensures the deferred read is truly gone — EffectSystem has no
	# excuse to reach into BM state anymore.
	var src: String = FileAccess.get_file_as_string("res://src/battle/EffectSystem.gd")
	assert_false(src.find("battle_mgr.current_combatant") > -1,
		"EffectSystem must not read BattleManager.current_combatant — weapon_type is caller-provided since cycle 14")
	assert_false(src.find("/root/BattleManager") > -1,
		"EffectSystem must not reach into BattleManager at all — the get_node_or_null(\"/root/BattleManager\") lookup was the escape valve the read used")
