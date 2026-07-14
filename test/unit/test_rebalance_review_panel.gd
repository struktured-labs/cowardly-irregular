extends GutTest

## tick 49: RebalanceReviewPanel UI. Bound to the tick-48 data layer
## (force_apply / dismiss / needs_review_count / format_for_review).
##
## Tests pin:
##   - Panel script exists with the right shape
##   - Apply button calls daemon.force_apply
##   - Dismiss button calls daemon.dismiss
##   - SettingsMenu surfaces the action row with the live count
##   - SettingsMenu wires the action to _open_rebalance_review
##   - SettingsMenu adds the open-state flag to the submenu gate

const PANEL := "res://src/ui/RebalanceReviewPanel.gd"
const SETTINGS := "res://src/ui/SettingsMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_panel_script_declares_class_and_signal() -> void:
	var src := _read(PANEL)
	assert_true(src.contains("class_name RebalanceReviewPanel"),
		"panel must declare class_name so SettingsMenu's loader resolves it")
	assert_true(src.contains("signal closed()"),
		"panel must emit closed so SettingsMenu can clear _rebalance_review_open and rebuild")


func test_apply_path_calls_force_apply() -> void:
	# Without this, the Apply button looks active but does nothing.
	var src := _read(PANEL)
	assert_true(src.contains("daemon.force_apply"),
		"_apply_current must call daemon.force_apply — the consent-bypass path from tick 48")


func test_dismiss_path_calls_dismiss() -> void:
	var src := _read(PANEL)
	assert_true(src.contains("daemon.dismiss"),
		"_dismiss_current must call daemon.dismiss — moves the proposal to applied[] with status='dismissed'")


func test_panel_uses_format_for_review() -> void:
	# The display string comes from the daemon, not the panel — keeps
	# the formatting in one place so changing the layout doesn't
	# require touching the UI.
	var src := _read(PANEL)
	assert_true(src.contains("daemon.format_for_review"),
		"panel must render via daemon.format_for_review — single-source-of-truth for proposal display")


func test_panel_filters_pending_by_status_needs_review() -> void:
	# Pending also holds awaiting_llm / stub / proposed entries that
	# aren't actionable yet. Panel must filter to needs_review only.
	var src := _read(PANEL)
	assert_true(src.contains("needs_review"),
		"panel must filter pending[] by status='needs_review'")


func test_settings_menu_adds_action_row_when_count_gt_zero() -> void:
	# Action row only appears when there's something waiting — keeps
	# the menu clean for users who never trigger the daemon.
	var src := _read(SETTINGS)
	assert_true(src.contains("rebalance_count > 0"),
		"action row must be conditional on count > 0 — don't surface an empty review action")
	assert_true(src.contains("\"rebalance_review\""),
		"action id must be 'rebalance_review' so the dispatcher branches to the right open call")


func test_settings_menu_dispatches_action_id() -> void:
	var src := _read(SETTINGS)
	assert_true(src.contains("item[\"id\"] == \"rebalance_review\""),
		"dispatcher must handle the rebalance_review action id")
	assert_true(src.contains("_open_rebalance_review()"),
		"dispatcher must call _open_rebalance_review")


func test_settings_menu_has_open_state_flag() -> void:
	# Without the flag in the submenu gate, OverworldMenu's parent
	# input handling would still fire while the panel is up — same
	# bug pattern other submenus had.
	var src := _read(SETTINGS)
	assert_true(src.contains("_rebalance_review_open"),
		"SettingsMenu must declare _rebalance_review_open and include it in the submenu gate")


func test_open_helper_loads_panel_dynamically() -> void:
	var src := _read(SETTINGS)
	assert_true(src.contains("res://src/ui/RebalanceReviewPanel.gd"),
		"_open_rebalance_review must load the panel script via res:// path")


func test_count_helper_guards_missing_autoload() -> void:
	# Defensive for boot-edge calls before GameState is ready.
	var src := _read(SETTINGS)
	var idx := src.find("func _get_rebalance_needs_review_count")
	assert_gt(idx, -1, "_get_rebalance_needs_review_count must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("not GameState"),
		"count helper must guard against missing GameState (returns 0)")
	assert_true(body.contains("rebalance_daemon"),
		"count helper must guard against missing daemon field")
