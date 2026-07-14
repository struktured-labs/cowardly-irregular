extends GutTest

## tick 57: Reset All Modifiers — one-click revert of every
## ALLOWED_CONSTANTS the daemon has nudged. Without this, the player
## has no way to roll back daemon changes short of editing the save
## file by hand or hitting dismiss on every NEEDS_REVIEW proposal
## (which doesn't help if they've already auto-applied).

const DAEMON := "res://src/llm/RebalanceDaemon.gd"
const PANEL := "res://src/ui/RebalanceHistoryPanel.gd"


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


func test_reset_to_defaults_method_exists() -> void:
	var src := _read(DAEMON)
	assert_true(src.contains("func reset_to_defaults() -> Dictionary"),
		"daemon must declare reset_to_defaults() returning Dictionary — caller wants to know what changed for the Toast")


func test_reset_iterates_allowed_constants_only() -> void:
	# Critical: reset must only touch ALLOWED_CONSTANTS. Touching
	# anything else would let the panel rewrite arbitrary game_constants
	# the daemon never owned.
	var body := _body_of(DAEMON, "reset_to_defaults")
	assert_true(body.contains("for c in ALLOWED_CONSTANTS"),
		"reset must iterate ALLOWED_CONSTANTS only — no other keys")


func test_reset_skips_values_already_at_default() -> void:
	# Avoid spurious applied[] entries on no-op resets — pin the
	# skip-default check.
	var body := _body_of(DAEMON, "reset_to_defaults")
	assert_true(body.contains("abs(before - 1.0) < 0.001"),
		"reset must skip values already at default (1.0) — no spurious applied[] entries")


func test_reset_records_to_applied_history() -> void:
	# The reset must show up in the audit trail. Without this entry
	# the user wouldn't see "you reset modifiers X minutes ago" in
	# the history panel.
	var body := _body_of(DAEMON, "reset_to_defaults")
	assert_true(body.contains("applied.append"),
		"reset must record an applied[] entry — audit trail integrity")
	assert_true(body.contains("\"status\": \"reset\""),
		"reset entry must carry status='reset' for the history panel to render the [RESET] tag")
	assert_true(body.contains("\"trigger\": \"manual_reset\""),
		"reset entry must carry trigger='manual_reset' so it's distinguishable from LLM proposals")


func test_reset_returns_dict_of_what_changed() -> void:
	# Caller (Toast / panel) uses this to say 'Reset N modifiers'.
	# Empty dict for the no-op case.
	var body := _body_of(DAEMON, "reset_to_defaults")
	assert_true(body.contains("return {}"),
		"reset must return empty dict on no-op (all already default)")
	assert_true(body.contains("return changed"),
		"reset must return the dict of changed constants for the caller's Toast")


func test_history_panel_has_reset_button() -> void:
	var src := _read(PANEL)
	assert_true(src.contains("\"Reset All Modifiers\""),
		"panel must have a 'Reset All Modifiers' button")
	assert_true(src.contains("var _reset_btn"),
		"panel must declare _reset_btn")


func test_panel_reset_handler_calls_daemon_method() -> void:
	var body := _body_of(PANEL, "_on_reset_pressed")
	assert_true(body.contains("daemon.reset_to_defaults"),
		"panel handler must call daemon.reset_to_defaults()")
	assert_true(body.contains("_render_history"),
		"panel must re-render after reset so the active-modifiers header AND history list reflect the new state")


func test_panel_renders_reset_status_tag() -> void:
	# The history panel must distinguish RESET entries from APPLIED
	# entries — otherwise the player can't tell "AI nudged" from
	# "player rolled back".
	var src := _read(PANEL)
	assert_true(src.contains("[RESET]"),
		"panel must render '[RESET]' tag for status='reset' entries")
	assert_true(src.contains("RESET_COLOR"),
		"panel must use a distinct color for reset entries — not the same as APPLIED")


func test_summarize_applied_formats_reset_separately() -> void:
	# The Toast / panel summary must show "Player reset:" not
	# "Auto-rebalance:" for reset entries.
	var body := _body_of(DAEMON, "summarize_applied")
	assert_true(body.contains("status == \"reset\""),
		"summarize_applied must distinguish reset entries — they're not LLM proposals")
	assert_true(body.contains("Player reset"),
		"reset entries must surface as 'Player reset:' so the framing is correct")
