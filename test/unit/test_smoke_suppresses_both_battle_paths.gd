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
