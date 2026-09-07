extends GutTest

## tick 221: BattleManager silent-fail surfaces.
##
## Two paths in BattleManager were print-only (invisible to the
## player in production builds where stdout isn't shown):
##
##   _execute_ability MP shortfall (line ~2694):
##     `if not caster.spend_mp(mp_cost): print(...); return`
##     If we reach here, can_use_ability already returned true but
##     spend_mp returned false — that's a real divergence. Player's
##     ability turn evaporates with no in-game signal.
##
##   _execute_item no-valid-targets fizzle (line ~3363):
##     `if retargeted.size() == 0 and targets.size() > 0:
##        print(...); return`
##     Item targets all died between selection and execution. Same
##     scenario _execute_ability handles with a battle_log_message
##     (line ~2690) — but _execute_item only printed.
##
## Fix: both now emit battle_log_message AND push_warning where
## the failure represents a divergence (MP case). Surfaces in both
## the in-game log (player) and editor logs / CI (dev).
##
## Continues the silent-failure audit theme across battle systems
## (ticks 216-217 autobattle, 220 cutscene flag mirror).

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── _execute_ability MP shortfall ─────────────────────────────────────

func test_ability_mp_shortfall_emits_battle_log() -> void:
	var src := _read(BATTLE_MANAGER)
	var fn_idx: int = src.find("func _execute_ability(caster: Combatant, ability_id: String, targets: Array) -> void:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("battle_log_message.emit(\"[color=gray]%s lacks MP for %s.[/color]\""),
		"MP shortfall must emit battle_log_message")


func test_ability_mp_shortfall_pushes_warning_on_divergence() -> void:
	# Reaching this branch means can_use_ability(line ~2653) returned
	# true but spend_mp returned false. That's a divergence worth
	# pushing as a warning.
	var src := _read(BATTLE_MANAGER)
	var fn_idx: int = src.find("func _execute_ability(caster: Combatant, ability_id: String, targets: Array) -> void:")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("[BattleManager] _execute_ability: '%s' insufficient MP after can_use_ability check passed"),
		"MP shortfall must push_warning naming the divergence (can_use_ability said yes, spend_mp said no)")
	assert_true(body.contains("can_use_ability / spend_mp divergence"),
		"warning must explicitly name 'can_use_ability / spend_mp divergence'")


# ── _execute_item fizzle ──────────────────────────────────────────────

func test_item_fizzle_emits_battle_log() -> void:
	var src := _read(BATTLE_MANAGER)
	var fn_idx: int = src.find("func _execute_item(user: Combatant, item_id: String, targets: Array) -> void:")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("fizzles — no valid targets"),
		"item fizzle must emit a fizzle message to battle_log")


func test_item_fizzle_uses_prettified_item_name() -> void:
	# Pin: the fizzle message uses replace("_", " ").capitalize() so
	# "hi_potion" reads as "Hi potion" not "hi_potion". Same pattern
	# as the existing tick 184 "has no X left" branch nearby.
	var src := _read(BATTLE_MANAGER)
	var fn_idx: int = src.find("func _execute_item(user: Combatant, item_id: String, targets: Array) -> void:")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Find the fizzle branch.
	var fizzle_idx: int = body.find("fizzles — no valid targets")
	assert_gt(fizzle_idx, -1)
	# Walk backward to confirm item_display variable is computed.
	var pre: String = body.substr(max(0, fizzle_idx - 300), 300)
	assert_true(pre.contains("var item_display: String = item_id.replace(\"_\", \" \").capitalize()"),
		"item fizzle must compute prettified item_display before emitting")


# ── Pre-existing print preserved for dev console ──────────────────────

func test_print_statements_still_present() -> void:
	# Pin: the print() calls are kept as the dev-console surface.
	# Removing them would make headless test runs harder to read.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("print(\"%s doesn't have enough MP!\" % caster.combatant_name)"),
		"MP shortfall print preserved")
	assert_true(src.contains("print(\"%s's item fizzles - no valid targets!\" % user.combatant_name)"),
		"item fizzle print preserved")


# ── Symmetry: _execute_ability fizzle still has battle_log ────────────

func test_existing_ability_fizzle_battle_log_preserved() -> void:
	# Cross-pin: don't regress the tick 173 ability fizzle log that
	# motivated this tick's item fizzle parity.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("%s's %s fizzles — no valid targets."),
		"tick 173 ability fizzle battle_log message preserved")


# ── Cross-pin: prior silent-fail audits preserved ─────────────────────

func test_tick_220_cutscene_helper_present() -> void:
	var gl: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(gl.contains("func _set_cutscene_flag_and_mirror(flag: String) -> void:"),
		"tick 220 _set_cutscene_flag_and_mirror helper preserved")


func test_tick_216_autobattle_warnings_present() -> void:
	var ab: String = FileAccess.get_file_as_string("res://src/autobattle/AutobattleSystem.gd")
	assert_true(ab.contains("[AutobattleSystem] _evaluate_condition: unknown ConditionType"),
		"tick 216 autobattle warning preserved")
