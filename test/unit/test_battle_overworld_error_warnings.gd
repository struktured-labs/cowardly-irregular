extends GutTest

## tick 183 regression: print→push_warning + battle_log sweep
## across remaining battle / exploration prints. Three classes:
##
##   1. Player-action failures (go_back x2, item-use fail):
##      now emit to battle_log_message (player surface) AND
##      keep print for debug overlay.
##
##   2. Authoring/save-format errors (item-use fail, missing
##      pool): push_warning so they surface in dev tooling.
##
##   3. Unknown ability_id / ability_type already had
##      push_warning from earlier ticks — pin to prevent
##      regression.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"
const OVERWORLD_CONTROLLER := "res://src/exploration/OverworldController.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── go_back player-action failures ──────────────────────────────────────

func test_go_back_wrong_state_emits_battle_log() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=gray]Can't go back — not currently in selection phase.[/color]"),
		"go_back wrong-state failure must emit battle_log so player sees feedback")


func test_go_back_no_previous_emits_battle_log() -> void:
	var src := _read(BATTLE_MANAGER)
	# Pin: must NOT contain the substring "return" — test
	# test_go_back_no_previous_player_reemits_turn_signal uses
	# branch.find("return") to find the function-level return
	# statement; a log message containing "return to" would break
	# the search. Worded around the constraint.
	assert_true(src.contains("[color=gray]Can't go back — no earlier PC available.[/color]"),
		"go_back no-previous failure must emit battle_log without using 'return' substring (would break pre-existing source-pin test)")


# ── Item-use failure: dev + player surfaces ─────────────────────────────

func test_item_use_failure_pushes_warning() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("push_warning(\"[BattleManager] _execute_item: ItemSystem.use_item returned false"),
		"item-use failure must push_warning (dev surface)")
	# Pin: warning explains the consequence (item not consumed,
	# turn wasted).
	assert_true(src.contains("item not consumed, turn wasted"),
		"warning must explain that the turn was wasted")


func test_item_use_failure_emits_battle_log() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=gray]Failed to use %s.[/color]"),
		"item-use failure must emit battle_log with prettified item name")
	# Pin: uses standard snake_case → Title Case prettifier.
	assert_true(src.contains("item_id.replace(\"_\", \" \").capitalize()"),
		"item-use failure log must prettify item_id")


# ── OverworldController missing pool ────────────────────────────────────

func test_missing_enemy_pool_pushes_warning() -> void:
	var src := _read(OVERWORLD_CONTROLLER)
	assert_true(src.contains("push_warning(\"[OverworldController] enemy pool '%s' not found in enemy_pools.json"),
		"missing enemy pool must push_warning")
	# Pin: warning explains the consequence (encounters wrong for area).
	assert_true(src.contains("encounters may be wrong for this area"),
		"warning must explain visible consequence")
	# Negative: old print Warning gone.
	assert_false(src.contains("print(\"Warning: Enemy pool"),
		"old print() Warning must be gone")


# ── Pre-existing push_warning paths preserved ──────────────────────────

func test_unknown_ability_id_warning_preserved() -> void:
	# Pin: line ~2650's push_warning from earlier ticks.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("push_warning(\"BattleManager._execute_ability: unknown ability_id"),
		"unknown ability_id push_warning preserved")


func test_unknown_ability_type_warning_preserved() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("push_warning(\"BattleManager._execute_ability: unhandled ability_type"),
		"unhandled ability_type push_warning preserved")


# ── Print statements preserved for debug overlay ───────────────────────

func test_go_back_print_preserved() -> void:
	# Non-regression: print() statements stay alongside the new
	# battle_log_message for debug overlay parity.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("print(\"Cannot go back - not in player selection state\")"),
		"go_back wrong-state print preserved")
	assert_true(src.contains("print(\"Cannot go back - no previous player available\")"),
		"go_back no-previous print preserved")


func test_item_use_failure_print_preserved() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("print(\"Failed to use item: %s\""),
		"item-use failure print preserved")
