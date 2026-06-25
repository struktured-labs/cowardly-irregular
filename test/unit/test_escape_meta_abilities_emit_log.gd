extends GutTest

## tick 172 regression: _execute_escape_ability and
## _execute_meta_ability branches now emit battle_log_message.
##
## Pre-fix every branch in both functions used print() only — the
## visible log showed nothing for escape attempts or for meta
## ability use. Meta abilities are reality-manipulation
## (Scriptweaver / Time Mage / Necromancer / Bossbinder) — they
## should feel DRAMATIC in the log, not silent.
##
## Escape result is one of the most important per-turn outcomes
## (it ENDS the battle); player needs immediate log feedback.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _fn_body(name: String) -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func " + name)
	assert_gt(idx, -1, "%s must exist" % name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── _execute_escape_ability — 3 outcomes ────────────────────────────────

func test_escape_disabled_emits_log() -> void:
	var body := _fn_body("_execute_escape_ability")
	assert_true(body.contains("[color=gray]Cannot escape from this battle![/color]"),
		"escape-disabled path must emit 'Cannot escape from this battle!' battle_log")


func test_escape_success_emits_log() -> void:
	var body := _fn_body("_execute_escape_ability")
	assert_true(body.contains("[color=lime]%s escaped successfully![/color]"),
		"escape-success path must emit lime-colored success log")


func test_escape_failure_emits_log() -> void:
	var body := _fn_body("_execute_escape_ability")
	assert_true(body.contains("[color=gray]%s failed to escape.[/color]"),
		"escape-failure path must emit gray-colored failure log (deferred turn outcome)")


# ── _execute_meta_ability — 6 branches ──────────────────────────────────

func test_formula_modification_emits_log() -> void:
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("[color=magenta]✦ %s opens the formula editor"),
		"formula_modification must emit a magenta + ✦ log")


func test_constant_modification_emits_log() -> void:
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("[color=magenta]✦ %s accesses the game constants"),
		"constant_modification must emit a magenta + ✦ log")


func test_code_inspection_emits_log() -> void:
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("analyzes the battle code — execution order revealed"),
		"code_inspection must emit a log line surfacing the execution-order reveal")


func test_time_rewind_success_emits_log() -> void:
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("[color=magenta]✦ %s rewinds time![/color]"),
		"time_rewind success must emit a dramatic magenta + ✦ log")


func test_time_rewind_failure_emits_log() -> void:
	# Failure is less-dramatic — gray + lore-y phrasing ("reaches
	# for the timeline... but no rewind point exists").
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("reaches for the timeline... but no rewind point exists"),
		"time_rewind failure must emit a gray log explaining why")


func test_add_corruption_emits_log() -> void:
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("[color=magenta]✦ %s channels corrupted power!"),
		"add_corruption must emit a magenta + ✦ log")


func test_permanent_death_emits_cast_log() -> void:
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("[color=magenta]✦ %s casts PERMAKILL![/color]"),
		"permanent_death cast must emit a magenta + ✦ log")


func test_permanent_death_per_target_emits_log() -> void:
	# Pin: each victim gets a per-target log line (☠ marker + red).
	var body := _fn_body("_execute_meta_ability")
	assert_true(body.contains("[color=red]☠ %s has been PERMANENTLY KILLED![/color]"),
		"permanent_death must emit a per-target ☠ red log for each kill")


# ── Color-palette family ────────────────────────────────────────────────

func test_meta_branches_use_magenta_consistently() -> void:
	# Magenta matches the META category color used in AbilitiesMenu
	# (META_COLOR from tick 137) and ItemsMenu (META_COLOR from tick
	# 138). Visual coherence with the META category.
	var body := _fn_body("_execute_meta_ability")
	# Count magenta + ✦ pairs (formula/constant/code/rewind/add_corruption/permakill)
	var count: int = 0
	var cursor: int = 0
	while true:
		var idx: int = body.find("[color=magenta]✦", cursor)
		if idx < 0:
			break
		count += 1
		cursor = idx + 1
	assert_gte(count, 5,
		"meta branches must use magenta+✦ consistently — count ≥ 5 across the 6 effect types")


# ── Pre-existing emits preserved ────────────────────────────────────────

func test_print_statements_still_present() -> void:
	# Non-regression: print() statements stay (debug-overlay still
	# uses them). Battle_log_message is purely additive.
	var body := _fn_body("_execute_escape_ability")
	assert_true(body.contains("print(\"  → %s escaped successfully!\""),
		"escape success print preserved for debug overlay")
