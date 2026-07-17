extends GutTest

## Cycle 14 (msg 2754) — cycle 12's deferred item.
##
## Before this cycle, EffectSystem._play_effect_sound read
## BattleManager.current_combatant to derive a weapon_type for
## PHYSICAL-effect SFX. That field is stale/null mid-execution
## (cowir-main's showcase gate fix 57269663 documented the class), so
## the deferred read attributed the wrong weapon to some hits or dropped
## the per-weapon SFX to the generic attack_hit fallback.
##
## Option (b) shipped: weapon_type is caller-provided on spawn_effect.
## EffectSystem is now stateless — never reaches into BM. Callers derive
## weapon_type from their known attacker (participant in group attacks,
## _last_acting_combatant in solo melee via _delayed_play_hit_fx).
##
## Empty weapon_type (default arg) → SoundManager.play_attack_hit("")
## → generic attack_hit — same graceful fallback as pre-fix when
## BM.current_combatant was null.

const ES_PATH: String = "res://src/battle/EffectSystem.gd"
const BS_PATH: String = "res://src/battle/BattleScene.gd"


## ── (1) EffectSystem.spawn_effect signature has weapon_type ───────────

func test_spawn_effect_signature_includes_weapon_type() -> void:
	# The seam for callers. Position is unchanged so old callers keep
	# working (default is empty string).
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	assert_string_contains(src,
		"func spawn_effect(effect_type: EffectType, position: Vector2, on_complete: Callable = Callable(), power: float = 1.0, weapon_type: String = \"\") -> void:",
		"spawn_effect must expose weapon_type as a defaulted trailing param")


func test_spawn_effect_on_target_signature_includes_weapon_type() -> void:
	# spawn_effect_on_target is the common convenience wrapper; if it
	# drops the arg silently, callers using it lose weapon attribution.
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	assert_string_contains(src,
		"func spawn_effect_on_target(effect_type: EffectType, target_sprite: Node2D, on_complete: Callable = Callable(), power: float = 1.0, weapon_type: String = \"\") -> void:",
		"spawn_effect_on_target must forward weapon_type")


func test_spawn_effect_on_target_forwards_weapon_type_to_spawn_effect() -> void:
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	assert_string_contains(src,
		"spawn_effect(effect_type, target_sprite.global_position, on_complete, power, weapon_type)",
		"spawn_effect_on_target's internal call must forward the weapon_type param")


## ── (2) _play_effect_sound uses the caller-provided value directly ────

func test_play_effect_sound_signature_takes_weapon_type() -> void:
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	assert_string_contains(src,
		"func _play_effect_sound(effect_type: EffectType, power: float = 1.0, weapon_type: String = \"\") -> void:",
		"_play_effect_sound must take weapon_type as a param — this is the deferred-read fix landing point")


func test_play_effect_sound_calls_play_attack_hit_with_caller_weapon() -> void:
	# The PHYSICAL branch consumes the caller value. Empty string still
	# falls through to SoundManager's generic attack_hit — the safe
	# default matches pre-fix behavior when BM.current_combatant was null.
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	var idx: int = src.find("func _play_effect_sound(")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1500)
	assert_string_contains(body, "SoundManager.play_attack_hit(weapon_type, false)",
		"the PHYSICAL branch must forward the caller-provided weapon_type verbatim")


func test_spawn_effect_forwards_weapon_type_to_play_effect_sound() -> void:
	# Regression: forgetting the thread in the outer spawn_effect body
	# would leave callers passing the arg but _play_effect_sound seeing
	# empty. Silent failure class.
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	assert_string_contains(src,
		"_play_effect_sound(effect_type, power, weapon_type)",
		"spawn_effect body must forward weapon_type into _play_effect_sound")


## ── (3) The deferred BM read is truly gone ───────────────────────────

func test_effect_system_no_bm_current_combatant_read() -> void:
	# The whole point. Delete this test the day EffectSystem is allowed
	# to reach back into BM state (which shouldn't happen).
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	assert_false(src.find("battle_mgr.current_combatant") > -1,
		"EffectSystem must not read battle_mgr.current_combatant — weapon_type is caller-provided since cycle 14")
	assert_false(src.find("/root/BattleManager") > -1,
		"EffectSystem must not lookup /root/BattleManager at all — the get_node_or_null was the escape valve")


func test_effect_system_no_equipment_lookup_inside() -> void:
	# Same discipline for EquipmentSystem — the caller derives weapon_type
	# from their attacker before spawning. EffectSystem staying stateless
	# is the point of option (b).
	var src: String = FileAccess.get_file_as_string(ES_PATH)
	# Allow it in comments (msg trail), not in code. Simple heuristic:
	# a `.get_weapon_type(` call is code; a comment mentioning it is fine.
	assert_false(src.find(".get_weapon_type(") > -1,
		"EffectSystem must not call get_weapon_type — the caller derives weapon_type themselves")


## ── (4) BattleScene weapon_type helper ────────────────────────────────

func test_bs_weapon_type_helper_present() -> void:
	# The seam BS callers use. Handles null attacker + missing autoload
	# gracefully so callers stay a one-liner.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _weapon_type_for(pc: Combatant) -> String:",
		"BS must expose _weapon_type_for helper")
	assert_string_contains(src, "if pc == null:\n\t\treturn \"\"",
		"_weapon_type_for must null-guard the attacker")


## ── (5) All PHYSICAL spawn_effect callers in BS pass weapon_type ──────

func test_all_bs_physical_spawns_pass_weapon_type() -> void:
	# Ratchet: a new PHYSICAL spawn_effect that forgets the trailing
	# weapon_type param would silently drop weapon SFX to the generic
	# fallback — same UX regression the cycle-14 fix closed.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	# Every EffectSystem.spawn_effect(...) call with EffectType.PHYSICAL
	# as the first arg should thread _weapon_type_for(...) through.
	var pattern: String = "EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL"
	var cursor: int = 0
	var offending: Array = []
	while true:
		var idx: int = src.find(pattern, cursor)
		if idx == -1:
			break
		# Find the end of this call (unbalanced paren scan — the call may
		# span multiple lines if a future refactor reformats). For today
		# they're all one line; look up to the next newline.
		var eol: int = src.find("\n", idx)
		if eol == -1:
			eol = src.length()
		var call: String = src.substr(idx, eol - idx)
		if call.find("_weapon_type_for(") < 0:
			# Also allow explicit ""` for the never-had-attacker case;
			# but PHYSICAL calls in execution are the target class — flag.
			# Annotate with a rough line number so a diff is easy.
			var line_num: int = src.substr(0, idx).count("\n") + 1
			offending.append("line %d: %s" % [line_num, call.substr(0, 120)])
		cursor = eol
	assert_eq(offending.size(), 0,
		"every PHYSICAL EffectSystem.spawn_effect must pass _weapon_type_for(...) — missing at: %s" % str(offending))


## ── (6) _delayed_play_hit_fx uses the cycle-12 cache for weapon_type ──

func test_delayed_play_hit_fx_uses_last_acting_combatant() -> void:
	# _delayed_play_hit_fx is called from a timer callback inside
	# _animate_melee_attack — no participant scope. The cycle-12 cache
	# _last_acting_combatant IS the attacker in solo melee, so reading
	# it there is correct + threads exactly the same attribution the
	# rest of the execution-phase handlers use.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _delayed_play_hit_fx(target_anim, target_sprite) -> void:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 500)
	assert_string_contains(body, "_weapon_type_for(_last_acting_combatant)",
		"_delayed_play_hit_fx must derive weapon_type from the cycle-12 cache — no attacker in local scope, cache is authoritative during execution")
