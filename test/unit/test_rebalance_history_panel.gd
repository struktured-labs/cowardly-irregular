extends GutTest

## tick 54: rebalance applied-history panel. Read-only diegetic
## surface — the "what did the AI change for me" view the directive
## memo explicitly called for.
##
## Pins:
##   - Panel exists with class_name + closed signal
##   - Iterates daemon.applied[] (most recent first)
##   - Uses daemon.summarize_applied for per-entry summary line
##   - Distinguishes APPLIED / DISMISSED / NO-CHANGE / REJECTED /
##     APPLIED-MANUAL by colored tag
##   - SettingsMenu surfaces action row when count > 0
##   - Open helper guards missing autoload

const PANEL := "res://src/ui/RebalanceHistoryPanel.gd"
const SETTINGS := "res://src/ui/SettingsMenu.gd"
const DAEMON := "res://src/llm/RebalanceDaemon.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(file_path: String, func_name: String) -> String:
	var src := _read(file_path)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist in " + file_path)
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_panel_declares_class_and_signal() -> void:
	var src := _read(PANEL)
	assert_true(src.contains("class_name RebalanceHistoryPanel"),
		"panel must declare class_name for SettingsMenu's loader")
	assert_true(src.contains("signal closed()"),
		"panel must emit closed so SettingsMenu clears _rebalance_history_open")


func test_panel_reads_applied_log() -> void:
	# This is the audit trail surface — has to actually read applied[].
	var src := _read(PANEL)
	assert_true(src.contains("daemon.applied"),
		"panel must read daemon.applied[] — that's the log being surfaced")


func test_panel_uses_daemon_summary_formatter() -> void:
	# Same formatter as the toast — single source of truth.
	var src := _read(PANEL)
	assert_true(src.contains("summarize_applied"),
		"panel must use daemon.summarize_applied for the per-entry summary line")


func test_panel_distinguishes_status_tags() -> void:
	# The audit trail must distinguish auto-applied from dismissed
	# from no-change. Without distinct tags, it's just a wall of
	# 'something happened' that the player can't act on.
	var src := _read(PANEL)
	for tag in ["[APPLIED]", "[DISMISSED]", "[NO-CHANGE]", "[REJECTED]", "[APPLIED-MANUAL]"]:
		assert_true(src.contains(tag),
			"panel must use a distinct tag for the %s status — colored audit trail beats homogenous 'something happened'" % tag)


func test_panel_iterates_most_recent_first() -> void:
	# Recent entries are what the player wants to see. Reverse
	# iteration of applied[] is the contract.
	var src := _read(PANEL)
	assert_true(src.contains("applied.size() - 1, -1, -1"),
		"panel must iterate applied[] from end-to-start (most recent first)")


func test_panel_uses_relative_when_formatter() -> void:
	# 'X min ago' reads more diegetically than a unix timestamp. Pin
	# the relative-time formatter so a future refactor doesn't switch
	# to raw timestamps.
	var src := _read(PANEL)
	assert_true(src.contains("min ago") or src.contains("sec ago") or src.contains("hr ago"),
		"panel must format timestamps as relative ('X min ago') — diegetic surface, not log file")


func test_settings_menu_adds_action_only_when_count_gt_zero() -> void:
	# Don't pollute the menu for users who never use the daemon.
	var src := _read(SETTINGS)
	assert_true(src.contains("history_count > 0"),
		"action row must be gated on count > 0 — don't show 'history' when there is none")
	assert_true(src.contains("\"Rebalance History\""),
		"action label must be 'Rebalance History'")
	assert_true(src.contains("\"rebalance_history\""),
		"action id must be 'rebalance_history'")


func test_dispatcher_routes_history_id() -> void:
	var src := _read(SETTINGS)
	assert_true(src.contains("item[\"id\"] == \"rebalance_history\""),
		"dispatcher must handle the rebalance_history action id")
	assert_true(src.contains("_open_rebalance_history()"),
		"dispatcher must call _open_rebalance_history")


func test_settings_menu_has_history_open_state() -> void:
	var src := _read(SETTINGS)
	assert_true(src.contains("_rebalance_history_open"),
		"SettingsMenu must declare _rebalance_history_open and include it in the submenu gate")


func test_count_helper_guards_missing_autoload() -> void:
	var body := _body_of(SETTINGS, "_get_rebalance_applied_count")
	assert_true(body.contains("not GameState"),
		"count helper must guard missing GameState — returns 0 for boot edge")
	assert_true(body.contains("rebalance_daemon"),
		"count helper must guard missing daemon field")
