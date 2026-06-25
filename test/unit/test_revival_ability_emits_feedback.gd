extends GutTest

## tick 169 regression: _execute_revival_ability must emit
## healing_done + battle_log_message after a revive lands.
##
## Pre-fix the revive path only called target.revive() (which
## updates HP via hp_changed) and print()'d to the debug console.
## Player feedback:
##   - HP bar pops up (good, via hp_changed)
##   - NO green floating popup (BattleScene._on_healing_done not
##     fired, so spawn_damage_number with is_heal=true never runs)
##   - NO battle log line (battle_log_message not emitted)
##   - print() goes only to stdout, invisible to the player
##
## So Phoenix Down and similar revival abilities looked silent
## even though they worked mechanically. Now matches the healing
## ability emit shape.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _revival_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _execute_revival_ability")
	assert_gt(idx, -1, "_execute_revival_ability must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Source pins ─────────────────────────────────────────────────────────

func test_revival_emits_healing_done() -> void:
	# Pin: healing_done emit follows target.revive() call.
	var body := _revival_body()
	assert_true(body.contains("healing_done.emit(target, target.current_hp)"),
		"_execute_revival_ability must emit healing_done with target + actual current_hp — drives the green popup")


func test_revival_emits_battle_log_message() -> void:
	var body := _revival_body()
	assert_true(body.contains("battle_log_message.emit(revive_log)"),
		"_execute_revival_ability must emit battle_log_message after revive")
	# Pin the log format includes the revive context.
	assert_true(body.contains("is revived with"),
		"battle log line must include 'is revived with' phrasing for clarity")
	# Pin color codes match the healing family (lime for heal).
	assert_true(body.contains("[color=lime]"),
		"revive log must use lime color (matches heal-family palette)")


func test_revival_emit_order_revive_before_emit() -> void:
	# Critical ordering: target.revive() must run BEFORE the emits
	# so target.current_hp reflects the post-revive value.
	var body := _revival_body()
	var revive_call_idx: int = body.find("target.revive(revive_hp)")
	var emit_idx: int = body.find("healing_done.emit")
	assert_gt(revive_call_idx, -1, "target.revive must exist")
	assert_gt(emit_idx, -1, "healing_done.emit must exist")
	assert_lt(revive_call_idx, emit_idx,
		"target.revive() must run BEFORE healing_done.emit — else we emit pre-revive current_hp (was 0)")


func test_revival_emit_uses_actual_current_hp_not_revive_hp() -> void:
	# Pin: the emit uses target.current_hp (post-revive actual)
	# NOT revive_hp (the requested value). target.revive() clamps
	# to max_hp, so revive_hp could exceed actual HP after the
	# call. The popup must match the bar.
	var body := _revival_body()
	assert_true(body.contains("healing_done.emit(target, target.current_hp)"),
		"healing_done arg must be target.current_hp (post-revive actual), not revive_hp")
	assert_false(body.contains("healing_done.emit(target, revive_hp)"),
		"pre-fix would have been healing_done.emit(target, revive_hp) — but revive_hp may exceed max_hp; the bar would mismatch the popup")


func test_revival_guards_dead_target_only() -> void:
	# Sanity / non-regression: the loop still skips ALIVE targets
	# (revive only works on dead). Don't accidentally invert the
	# guard while wiring the emits.
	var body := _revival_body()
	assert_true(body.contains("or target.is_alive:") and body.contains("continue"),
		"loop must skip ALIVE targets (revive only applies to dead)")


# ── Cross-pin: healing_done flow is intact in _execute_healing_ability ──

func test_healing_ability_still_emits_healing_done() -> void:
	# Negative regression: the source for the matching emit
	# pattern must still exist in _execute_healing_ability.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _execute_healing_ability")
	assert_gt(idx, -1, "_execute_healing_ability must exist (was the model for revive fix)")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("healing_done.emit(target, healed)"),
		"_execute_healing_ability must keep its healing_done emit — was the reference pattern for the revive fix")
