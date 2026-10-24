extends GutTest

## cowir-deploy, .265 web: the render smoke failed twice with "a live battle owns the screen" on a
## DIFFERENT map leg each attempt — the signature of a flake rather than a deterministic red (the
## three real reds today each failed identically twice).
##
## Cause: there are TWO battle-start paths and the smoke gated one. EncounterSystem.encounters_enabled
## stops random encounters, and its comment says exactly why ("one firing during the walk legs made
## EVERY later map leg bail"). A roamer walking into the player is a separate path —
## MonsterSpawner -> monster_touched -> _on_roaming_monster_touched — and nothing suppressed it.
## It got worse today because several dead-lookup repairs turned monster moods and elite spawning on.

const GL_SRC := "res://src/GameLoop.gd"
const GameLoopScript := preload("res://src/GameLoop.gd")


func test_the_smoke_gates_both_battle_start_paths() -> void:
	var src := FileAccess.get_file_as_string(GL_SRC)
	assert_true(src.contains("EncounterSystem.encounters_enabled = false"),
		"CONTROL: the random-encounter path is still gated")
	assert_true(src.contains("func _smoke_quiet_the_roamers"),
		"the roaming-monster path must be gated too — it is the one that reached the store")


func test_the_roamer_gate_runs_on_every_shot_not_once_at_startup() -> void:
	## Each map leg builds a fresh scene with a fresh spawner, so a one-time call at smoke start
	## would gate the overworld's spawner and none of the village ones — which is precisely the set
	## of legs that failed (eldertree_village, sandrift_village).
	var src := FileAccess.get_file_as_string(GL_SRC)
	var shot_at: int = src.find("func _smoke_shot")
	assert_gt(shot_at, -1, "CONTROL: the shot helper exists")
	var body := src.substr(shot_at, 400)
	assert_true(body.contains("_smoke_quiet_the_roamers()"),
		"the suppression must run per shot, not once at startup")


func test_the_roamer_gate_runs_at_MAP_ENTRY_not_only_at_the_next_shot() -> void:
	## ⛔ .443 web RED. The arm above says "per shot, not once at startup" and its docstring gives
	## the right reason -- "each map leg builds a fresh scene with a fresh spawner" -- then pins
	## _smoke_shot. PER-SHOT IS NOT PER-MAP-ENTRY, and the gap between them is where the spawner is
	## alive and enabled:
	##     _smoke_enter_map("overworld") -> 1.5s -> action_press(dir) -> 0.7s -> _smoke_shot()
	## ~2.2s of live roamers with the player deliberately walked into them. Measured on the failing
	## log: encounters_enabled was FALSE the whole run (the random path was shut, and the only writer
	## that sets it true ran 30 log lines AFTER the first bail), yet a battle started between the walk
	## shots and the village shot and all 13 later legs bailed. The other arm was green throughout.
	var src := FileAccess.get_file_as_string(GL_SRC)
	var at: int = src.find("func _smoke_enter_map")
	assert_gt(at, -1, "CONTROL: the map-entry helper exists")
	var next: int = src.find("\nfunc ", at + 1)
	var body := src.substr(at, next - at)
	assert_true(body.contains("_smoke_quiet_the_roamers()"),
		"a freshly built map must have its spawner quieted AT ENTRY -- waiting for the next shot " +
		"leaves a live-roamer window that no flag closes")


func test_the_gate_uses_the_spawners_own_api_and_survives_its_absence() -> void:
	var src := FileAccess.get_file_as_string(GL_SRC)
	var i: int = src.find("func _smoke_quiet_the_roamers")
	var body := src.substr(i, 600)
	assert_true(body.contains('has_method("set_enabled")'),
		"call the spawner's own API rather than reaching into its state")
	assert_true(body.contains("is_instance_valid"),
		"a scene between loads has no spawner — the helper must not throw during a transition")


func test_the_spawner_really_has_that_api_and_despawns() -> void:
	# The pin above asserts we CALL set_enabled; this asserts the method exists and does the thing,
	# so the gate cannot be certified by a call to a method that stopped clearing roamers.
	var src := FileAccess.get_file_as_string("res://src/exploration/MonsterSpawner.gd")
	var i: int = src.find("func set_enabled")
	assert_gt(i, -1, "MonsterSpawner.set_enabled must exist")
	var body := src.substr(i, 200)
	assert_true(body.contains("_despawn_all()"),
		"disabling must also clear roamers already on the map, or the ones already spawned still collide")


## .669 pre-gate: the roamer leg re-arms the spawner, fights, and comes back to a fresh ENABLED one.
## A second roamer started a battle before the next map leg and five legs bailed.
func test_the_roamer_leg_quiets_the_map_it_comes_back_to() -> void:
	var code: String = load("res://test/unit/helpers/gd_source.gd").code_of(GL_SRC)
	var at: int = code.find("func _smoke_player_path_battle")
	var end: int = code.find("\nfunc ", at + 1)
	assert_gt(at, -1, "CONTROL: the roamer leg exists")
	assert_gt(end, at, "CONTROL: the roamer leg ends at a next function")
	var body: String = code.substr(at, end - at)
	var rearm: int = body.find("set_enabled(true)")
	assert_gt(rearm, -1, "CONTROL: the leg re-arms the spawner, which is why it must quiet again")
	var back: int = body.find("\"monster_spawner\" in current_scene", rearm)
	assert_gt(back, rearm, "CONTROL: the leg waits for an exploration scene to come back")
	assert_gt(body.find("_smoke_quiet_the_roamers()", back), back,
		"the map the fight returns to has a live spawner — quiet it before the leg hands back")


## .705 pre-gate: the guard tested `current_state != INACTIVE` while the battle was still in
## TRANSITION -- trigger, then "Starting battle transition", then `Battle started` lines later --
## so it read INACTIVE, passed, and the battle began behind it. .443 and .669 each narrowed the
## spawner window instead of fixing the guard behind it. Static and pure because no test can
## instantiate GameLoop; reached by preloaded const, so a rename gives EC=3, not a vacuous arm.
func test_an_idle_screen_is_the_only_state_with_no_owner() -> void:
	assert_eq(GameLoopScript.smoke_screen_owner(true, false), "",
		"nothing owns the screen when the battle state is inactive and no transition is starting")


func test_a_live_battle_owns_the_screen() -> void:
	assert_eq(GameLoopScript.smoke_screen_owner(false, false), "a live battle owns the screen",
		"the state the old two-state guard could already see")


func test_a_STARTING_transition_owns_the_screen_too() -> void:
	# THE DEFECT ARM: inactive state, trigger already fired. The old guard called this idle.
	assert_eq(GameLoopScript.smoke_screen_owner(true, true), "a battle transition is starting",
		"a battle whose transition has started owns the screen before current_state says so")


func test_a_live_battle_outranks_a_starting_transition_in_the_message() -> void:
	# Both mean busy, so only the message can be wrong -- and a leg reports the state it is in.
	assert_eq(GameLoopScript.smoke_screen_owner(false, true), "a live battle owns the screen",
		"when both hold, name the battle that is already running")


## Source-text arms. These certify SPELLING, not behaviour -- the arms above are what judge the
## decision -- but a call site that quietly reverts to testing the state alone is exactly how this
## defect survived two repairs, and nothing else can see a call site from here.
func test_both_smoke_guards_ask_the_predicate_rather_than_the_state_alone() -> void:
	var code: String = load("res://test/unit/helpers/gd_source.gd").code_of(GL_SRC)
	for fn in ["func _smoke_enter_map", "func _smoke_player_path_battle"]:
		var at: int = code.find(fn)
		assert_gt(at, -1, "CONTROL: %s exists" % fn)
		var end: int = code.find("\nfunc ", at + 1)
		var body: String = code.substr(at, end - at)
		assert_true(body.contains("_smoke_screen_owner()"),
			"%s must ask the predicate: a bare current_state test is blind to a starting transition" % fn)


func test_the_predicate_reads_the_transition_flag_the_engine_actually_sets() -> void:
	var code: String = load("res://test/unit/helpers/gd_source.gd").code_of(GL_SRC)
	var at: int = code.find("func _smoke_screen_owner")
	assert_gt(at, -1, "CONTROL: the live-engine reader exists")
	var body: String = code.substr(at, 400)
	assert_true(body.contains("_battle_transition_starting"),
		"the second fact must come from the flag _on_exploration_battle_triggered sets")
	assert_true(code.contains("_battle_transition_starting = true"),
		"CONTROL: the engine still sets that flag, so reading it is not reading a dead name")


## The half that stops a leak reding the fold: naming it better would still have been a red.
func test_the_roamer_leg_absorbs_a_leaked_battle_under_a_bound() -> void:
	var code: String = load("res://test/unit/helpers/gd_source.gd").code_of(GL_SRC)
	var at: int = code.find("func _smoke_player_path_battle")
	var end: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, end - at)
	assert_true(body.contains("_smoke_end_any_battle()"),
		"a second touch is noise, not coverage -- end it rather than failing every later leg")
	assert_true(body.contains("for _attempt in range("),
		"the absorb must be bounded by construction, not by a while-true the engine can sit in")


func test_the_absorber_waits_out_the_transition_before_ending_anything() -> void:
	# end_battle on a battle that has not begun does nothing, and the leg would hand back into it.
	var code: String = load("res://test/unit/helpers/gd_source.gd").code_of(GL_SRC)
	var at: int = code.find("func _smoke_end_any_battle")
	assert_gt(at, -1, "CONTROL: the absorber exists")
	var end: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, end - at)
	var settle: int = body.find("_battle_transition_starting")
	var ends: int = body.find("end_battle(true)")
	assert_gt(settle, -1, "the absorber must wait for the transition to resolve")
	assert_gt(ends, settle, "it must wait BEFORE ending: a battle mid-transition cannot be ended")
	assert_true(body.contains("settling < 12.0") and body.contains("back < 15.0"),
		"both waits bounded in their own conditions, the bounds the deliberate hand-back already uses")
