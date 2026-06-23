extends GutTest

## tick 55: extends the rebalance daemon's trigger surface from
## wipe/defeat (high-stakes events) to include level_up (passive
## progression signal). The directive memo asked for "constantly
## attempting to rebalance" — level_up gives the daemon a steady
## pulse during normal play.
##
## Test surface:
##   - Combatant emits leveled_up(int) once per level threshold
##   - RebalanceDaemon has TRIGGER_LEVEL_UP constant
##   - GameLoop wires _on_party_leveled_up listener
##   - Handler records to EventLog AND (if enabled) fires consider
##   - Handler is idempotent / save-load safe

const COMBATANT := "res://src/battle/Combatant.gd"
const DAEMON := "res://src/llm/RebalanceDaemon.gd"
const GAME_LOOP := "res://src/GameLoop.gd"


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


func test_combatant_declares_leveled_up_signal() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("signal leveled_up(new_level: int)"),
		"Combatant must declare leveled_up(new_level) signal for the daemon to listen to")


func test_gain_job_exp_emits_leveled_up_once_per_threshold() -> void:
	# gain_job_exp loops while excess EXP crosses thresholds. The emit
	# must be INSIDE the loop, not after — otherwise a multi-level
	# gain only triggers one event.
	var body := _body_of(COMBATANT, "gain_job_exp")
	assert_true(body.contains("leveled_up.emit(job_level)"),
		"gain_job_exp must emit leveled_up — passes the new level so listeners can scale response")
	# Verify the emit is inside the while loop, not after — locate the
	# loop's `while` and the emit; emit must be before the loop ends.
	var while_idx := body.find("while job_exp")
	var emit_idx := body.find("leveled_up.emit")
	var rec_idx := body.find("recalculate_stats")
	assert_gt(while_idx, -1, "while loop must exist")
	assert_gt(emit_idx, while_idx,
		"emit must be after the while declaration (inside the loop body)")
	assert_lt(emit_idx, rec_idx,
		"emit must be BEFORE recalculate_stats — otherwise multi-level gains only fire one event")


func test_gain_job_exp_renamed_local_var_to_avoid_signal_shadow() -> void:
	# The original local var was `var leveled_up := false`. After
	# declaring the signal of the same name, the local would shadow
	# the signal AND `leveled_up.emit(...)` would crash trying to
	# call .emit on a bool. Renamed to `did_level`.
	var body := _body_of(COMBATANT, "gain_job_exp")
	assert_true(body.contains("var did_level"),
		"gain_job_exp must use the renamed local var (did_level) — shadowing leveled_up with a bool would crash on .emit()")
	# Negative: the OLD shadowing form must be gone.
	assert_false(body.contains("var leveled_up := false"),
		"the prior shadowing form must be gone — pin the rename so a future revert doesn't reintroduce the crash")


func test_daemon_has_trigger_level_up_constant() -> void:
	var src := _read(DAEMON)
	assert_true(src.contains("TRIGGER_LEVEL_UP"),
		"RebalanceDaemon must declare TRIGGER_LEVEL_UP constant — no magic strings")


func test_game_loop_wires_listeners_in_create_party() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("_wire_party_level_up_listeners()"),
		"_create_party must call _wire_party_level_up_listeners — without this the daemon never sees level events on a fresh game")


func test_game_loop_rewires_after_load() -> void:
	# Save-load constructs fresh Combatants. Without a re-wire the
	# load loses the listeners.
	var body := _body_of(GAME_LOOP, "_restore_party_from_save_data")
	assert_true(body.contains("_wire_party_level_up_listeners()"),
		"_restore_party_from_save_data must re-wire listeners — fresh Combatants don't carry prior connections")


func test_wire_helper_is_idempotent() -> void:
	# Without is_connected check, repeated calls (e.g. after some
	# future hot-reload) would double-connect and the daemon would
	# get duplicate triggers.
	var body := _body_of(GAME_LOOP, "_wire_party_level_up_listeners")
	assert_true(body.contains("is_connected"),
		"wire helper must check is_connected before connecting — idempotent for save-load reuse")


func test_handler_records_to_event_log_unconditionally() -> void:
	# The EventLog record happens regardless of rebalance opt-in.
	# Audit trail integrity comes before LLM features.
	var body := _body_of(GAME_LOOP, "_on_party_leveled_up")
	assert_true(body.contains("EventLog.TYPE_LEVEL_UP"),
		"handler must record TYPE_LEVEL_UP — audit log even if rebalance is OFF")
	assert_true(body.contains("event_log.record"),
		"handler must call event_log.record")


func test_handler_gates_rebalance_on_opt_in_flag() -> void:
	# Same opt-in pattern as wipe + boss-defeat. Daemon-side throttle
	# (60s default) handles burst protection.
	var body := _body_of(GAME_LOOP, "_on_party_leveled_up")
	assert_true(body.contains("GameState.llm_rebalance_enabled"),
		"handler must gate rebalance.consider on the opt-in flag — vanilla play unchanged")
	assert_true(body.contains("TRIGGER_LEVEL_UP"),
		"handler must pass the TRIGGER_LEVEL_UP constant when calling consider")
	assert_true(body.contains("_kick_off_rebalance_fetch.call_deferred"),
		"handler must kick off the LLM fetch when consider() succeeds — same shape as wipe/defeat trigger sites")


## tick 60: level-up Toast (suppressed during battle to avoid noise on
## top of the existing victory screen)


func test_handler_toasts_out_of_battle() -> void:
	var body := _body_of(GAME_LOOP, "_on_party_leveled_up")
	assert_true(body.contains("Toast.show"),
		"handler must Toast — without it leveling out of battle (debug paths, future event-driven exp) silently flickers stats")
	# Must include the member name + level so the toast is informative.
	assert_true(body.contains("reached job level"),
		"toast message must say 'reached job level X' so the player knows what changed")


func test_handler_suppresses_toast_during_battle() -> void:
	# Battle has its own victory screen with per-character level info.
	# A parallel Toast would just spam the UI.
	var body := _body_of(GAME_LOOP, "_on_party_leveled_up")
	assert_true(body.contains("is_battle_active"),
		"handler must check is_battle_active and suppress the Toast during battle — victory screen already surfaces the level-up")
	assert_true(body.contains("not in_battle"),
		"toast must be gated on 'not in_battle' so the suppression actually kicks in")
