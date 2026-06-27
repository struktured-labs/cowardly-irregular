extends GutTest

## tick 177 regression: _execute_summon emits a battle log line
## when an enemy summons a new monster. Pre-fix the new enemy
## sprite appeared (via the monster_summoned signal handler that
## drives spawn FX) but no log line said "X summons a Goblin!"
## Players got confused mid-battle when a new enemy suddenly
## appeared with no explanation.
##
## In-game summoners (per BattleManager._can_monster_summon):
## goblin / imp / skeleton / wolf / bat. Common in W1 dungeons.
##
## Audit cross-checks for tick 177 wakeup:
##   - Limit Break cleanse loop: already emits per-participant
##     log line at line 2097. Status icons disappear visually
##     too. No popup needed (would be 0-amount healing).
##   - Boss gloat lines (victory/defeat): _on_boss_gloat_line in
##     BattleScene already emits to log with crimson/gold colors.
##   - Enemy ability use: announces via _execute_ability's
##     shared "X uses Y!" emit (line 2629).
##   - Damage emits: physical + magic + drain all emit both
##     battle_log_message AND damage_dealt/healing_done.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _summon_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _execute_summon")
	assert_gt(idx, -1, "_execute_summon must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Summon emit ─────────────────────────────────────────────────────────

func test_summon_emits_battle_log() -> void:
	var body := _summon_body()
	assert_true(body.contains("[color=purple]%s summons a %s![/color]"),
		"_execute_summon must emit '<X> summons a <Y>!' battle_log — purple matches the 'spawn/conjure' family")


func test_summon_log_emit_precedes_monster_summoned_signal() -> void:
	# Ordering: the log line must be emitted BEFORE
	# monster_summoned fires. Otherwise the spawn FX (driven by
	# the signal handler) runs first and the log line appears
	# AFTER the new enemy sprite is visible — feels backwards.
	var body := _summon_body()
	var log_idx: int = body.find("battle_log_message.emit")
	var sig_idx: int = body.find("monster_summoned.emit")
	assert_gt(log_idx, -1, "battle_log emit must exist")
	assert_gt(sig_idx, -1, "monster_summoned signal must still fire")
	assert_lt(log_idx, sig_idx,
		"log emit must precede monster_summoned signal — announce before the spawn FX runs")


func test_summon_uses_prettified_monster_type() -> void:
	# Pin: snake_case → Title Case via the standard prettifier.
	var body := _summon_body()
	assert_true(body.contains("monster_type.replace(\"_\", \" \").capitalize()"),
		"summon must use the standard replace+capitalize prettifier on monster_type")


# ── Cross-pins: audited-clean paths must remain ─────────────────────────

func test_limit_break_cleanse_per_participant_log_preserved() -> void:
	# Tick 238: accept either legacy [color=lime] OR the palette helper shape.
	var src := _read(BATTLE_MANAGER)
	var has_legacy: bool = src.contains("[color=lime]%s is cleansed by the Limit Break![/color]")
	var has_palette: bool = src.contains("[color=%s]%s is cleansed by the Limit Break![/color]\" % [AccessibilityPalette.bonus_bbcode(), p.combatant_name]")
	assert_true(has_legacy or has_palette,
		"Limit Break cleanse per-participant log preserved (audited clean for tick 177; legacy OR tick 238 shape)")


func test_ability_use_announce_preserved() -> void:
	# Cross-pin: _execute_ability's "X uses Y!" announce covers
	# enemy ability use too (shared codepath).
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=white]%s[/color] uses [color=aqua]%s[/color]!"),
		"_execute_ability 'X uses Y!' announce preserved (shared player+enemy codepath)")


func test_physical_damage_log_preserved() -> void:
	# Cross-pin: physical ability per-target damage log.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=red]%s[/color] takes [color=yellow]%d[/color] damage!"),
		"physical damage log preserved")


func test_magic_damage_log_preserved() -> void:
	# Cross-pin: magic ability per-target damage log (with element).
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=red]%s[/color] takes [color=cyan]%d[/color] %s damage!"),
		"magic damage log preserved")


# ── Defensive: monster_summoned signal must still fire ─────────────────

func test_monster_summoned_signal_still_emitted() -> void:
	# Non-regression: the signal that drives spawn FX must still
	# fire. Without it the log says "X summons a Y!" but no Y
	# actually appears.
	var body := _summon_body()
	assert_true(body.contains("monster_summoned.emit(monster_type, combatant)"),
		"monster_summoned signal must still fire — drives the actual spawn FX")
