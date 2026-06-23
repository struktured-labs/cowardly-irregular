extends GutTest

## tick 58: closes the long-standing TODO in Combatant.gain_job_exp
## ("Unlock new abilities/passives at certain levels"). Adds a
## data-driven level-up ability unlock system:
##
##   1. Jobs may declare "abilities_at_level": {"N": ["ability_id"]}
##   2. JobSystem.learn_abilities_for_level grants every ability
##      whose threshold has been crossed (handles multi-level gains)
##   3. Combatant.learn_ability returns bool now (was void) so the
##      grant path can dedupe
##   4. Combatant emits ability_learned(ability_id) per grant
##   5. GameLoop wires the signal and Toasts the unlock

const COMBATANT := "res://src/battle/Combatant.gd"
const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"
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


func test_combatant_declares_ability_learned_signal() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("signal ability_learned(ability_id: String)"),
		"Combatant must declare ability_learned(ability_id) signal")


func test_learn_ability_returns_bool() -> void:
	# Pre-tick the signature was void — JobSystem can't dedupe without
	# the return value.
	var src := _read(COMBATANT)
	assert_true(src.contains("func learn_ability(ability_id: String) -> bool"),
		"learn_ability must return bool — JobSystem uses the return value to track granted abilities")


func test_learn_ability_dedupes() -> void:
	var body := _body_of(COMBATANT, "learn_ability")
	assert_true(body.contains("ability_id in learned_abilities"),
		"learn_ability must check existing knowledge before granting")
	# Returns false on duplicate, true on new.
	assert_true(body.contains("return false") and body.contains("return true"),
		"learn_ability must return true on new grant AND false on duplicate so callers can branch")


func test_gain_job_exp_calls_learn_abilities_for_level() -> void:
	# The TODO ("Unlock new abilities/passives at certain levels") is
	# closed — gain_job_exp now calls into JobSystem after leveling.
	var body := _body_of(COMBATANT, "gain_job_exp")
	assert_true(body.contains("learn_abilities_for_level"),
		"gain_job_exp must call JobSystem.learn_abilities_for_level after leveling — closes the long-standing TODO")
	# Negative assertion: the OLD TODO comment must be gone.
	assert_false(body.contains("TODO: Unlock new abilities"),
		"the stale TODO comment must be gone — its body has been implemented")


func test_job_system_has_learn_abilities_for_level() -> void:
	var src := _read(JOB_SYSTEM)
	assert_true(src.contains("func learn_abilities_for_level(combatant: Combatant, new_level: int) -> Array"),
		"JobSystem must declare learn_abilities_for_level returning the granted IDs")


func test_job_system_reads_abilities_at_level_field() -> void:
	var body := _body_of(JOB_SYSTEM, "learn_abilities_for_level")
	assert_true(body.contains("abilities_at_level"),
		"must read the data-driven 'abilities_at_level' field on the job dict")


func test_job_system_handles_multi_level_jumps() -> void:
	# Critical: EXP overflow can cross multiple thresholds in one
	# gain_job_exp call. learn_abilities_for_level must grant every
	# crossed threshold, not just the current level.
	var body := _body_of(JOB_SYSTEM, "learn_abilities_for_level")
	assert_true(body.contains("threshold > new_level"),
		"loop must skip thresholds NOT YET crossed (threshold > new_level) — which means it processes ALL crossed thresholds in one pass")


func test_job_system_emits_ability_learned_signal() -> void:
	var body := _body_of(JOB_SYSTEM, "learn_abilities_for_level")
	assert_true(body.contains("ability_learned.emit(ability_id)"),
		"granting an ability must emit ability_learned so listeners (GameLoop Toast) react")


func test_game_loop_wires_ability_learned_listener() -> void:
	# Without this wiring, the signal fires but nothing happens.
	var body := _body_of(GAME_LOOP, "_wire_party_level_up_listeners")
	assert_true(body.contains("ability_learned"),
		"_wire_party_level_up_listeners must also connect ability_learned — tick 58 extension")
	assert_true(body.contains("is_connected"),
		"connection must guard against duplicate-connect (idempotent for save-load reuse)")


func test_game_loop_toasts_on_ability_learned() -> void:
	var body := _body_of(GAME_LOOP, "_on_party_ability_learned")
	assert_true(body.contains("Toast.show"),
		"handler must Toast the unlock — without it the player has no idea they got something new")
	assert_true(body.contains("learned"),
		"Toast message must include 'learned' so it reads as an unlock")
