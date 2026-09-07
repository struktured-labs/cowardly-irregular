extends GutTest

## tick 173 regression: action-fizzle paths in BattleManager now
## emit battle_log_message. Pre-fix three paths were silent:
##
##   1. Ability "cannot use" (insufficient MP / missing
##      prerequisite). _execute_ability returned early after
##      print() only — player saw their character try to use
##      an ability and silently fail.
##
##   2. Ability fizzle (no valid targets after retargeting).
##      Common: queued attack, target dies first via another
##      action, retargeter can't find a survivor. AP was spent
##      with no log explanation.
##
##   3. Basic attack fizzle (same scenario but on basic attack).
##      Pre-fix the AP was spent silently.
##
## Status auto-removal logs audited clean — stun/cannot_act/
## sleep/confuse all emit battle_log_message at their wake/snap
## points (BattleManager.gd:1798/1815/1824/1835).
## _execute_ability's "X uses Y!" announce (line 2629) also
## emits — covers both player AND enemy ability use, since the
## function is shared.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Ability "cannot use" path ───────────────────────────────────────────

func test_ability_cannot_use_emits_log() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=gray]%s can't use %s right now.[/color]"),
		"_execute_ability 'cannot use' path must emit battle_log — pre-fix only print")


# ── Ability fizzle path ─────────────────────────────────────────────────

func test_ability_fizzle_emits_log() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=gray]%s's %s fizzles — no valid targets.[/color]"),
		"_execute_ability fizzle path must emit battle_log — common scenario when queued action's target dies first")


# ── Basic attack fizzle path ────────────────────────────────────────────

func test_basic_attack_fizzle_emits_log() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=gray]%s's attack fizzles — no valid targets.[/color]"),
		"_execute_attack fizzle path must emit battle_log (symmetric with ability fizzle)")


# ── Palette consistency ─────────────────────────────────────────────────

func test_fizzle_paths_use_gray_color() -> void:
	# Gray matches existing 'no-op' lines (e.g., support steal failure
	# "couldn't steal anything", cleanse "no ailments to cleanse").
	# Color-family consistency with other neutral/null-outcome log
	# lines.
	var src := _read(BATTLE_MANAGER)
	# Count gray fizzle/can't lines added in tick 173.
	for fragment in [
		"[color=gray]%s can't use %s right now.[/color]",
		"[color=gray]%s's %s fizzles — no valid targets.[/color]",
		"[color=gray]%s's attack fizzles — no valid targets.[/color]",
	]:
		assert_true(src.contains(fragment),
			"gray-color fizzle fragment must exist: %s" % fragment)


# ── Pre-existing print() preserved for debug overlay ────────────────────

func test_existing_print_statements_preserved() -> void:
	# Non-regression: print() statements stay alongside the new
	# battle_log_message emits. Debug overlay still uses them.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("print(\"%s cannot use %s\""),
		"cannot-use print() preserved for debug overlay")
	assert_true(src.contains("print(\"%s's %s fizzles - no valid targets!\""),
		"ability fizzle print() preserved")
	assert_true(src.contains("print(\"%s's attack fizzles - no valid targets!\""),
		"basic attack fizzle print() preserved")


# ── Status auto-removal audit (clean — pinned to prevent regression) ────

func test_status_auto_removal_logs_preserved() -> void:
	# Audit cross-check from tick 173 wakeup: stun/cannot_act/
	# sleep/confuse auto-removal already emit battle_log_message
	# at their wake/snap points. Pin all 4 to catch any future
	# refactor that removes them.
	var src := _read(BATTLE_MANAGER)
	for fragment in [
		"is [color=orange]stunned[/color] and cannot act!",
		"[color=yellow]%s[/color] cannot act!",
		"[color=yellow]%s[/color] woke up!",
		"[color=yellow]%s[/color] snapped out of confusion!",
	]:
		assert_true(src.contains(fragment),
			"existing status-removal log must remain: %s" % fragment)


# ── Enemy AI ability use audit (clean — covered by shared path) ─────────

func test_ability_use_announcement_log_preserved() -> void:
	# Wakeup question: enemy AI ability use shows "X uses Y!" in
	# log? Yes — both player and enemy go through _execute_ability,
	# and line 2629 emits the announcement unconditionally.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=white]%s[/color] uses [color=aqua]%s[/color]!"),
		"_execute_ability 'X uses Y!' announce must remain — covers both player AND enemy uses (shared codepath)")
