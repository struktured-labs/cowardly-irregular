extends GutTest

## GameState.player_party is a snapshot. The only writers are the pause menu
## opening and a save. Encounter rate, field-elite level, and overworld move
## speed were reading that snapshot, so a Ninja you just switched to — or a
## level you just earned — did nothing until the next menu open or save.
##
## The live roster is GameLoop.party. These queries must prefer it, and fall
## back to the snapshot only when no live party is in the tree (a save load
## before rehydrate, a headless test that only fills the snapshot).

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


class RosterHost:
	extends Node
	var party: Array = []
	var _spotlight_duel_active: bool = false
	var _spotlight_saved_party: Array = []


var _host: Node = null
var _prior_party: Array = []


func before_each() -> void:
	_prior_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	if _host != null and is_instance_valid(_host):
		_host.free()
		_host = null
	var restore: Array[Dictionary] = []
	for entry in _prior_party:
		if entry is Dictionary:
			restore.append(entry)
	GameState.player_party = restore


func test_a_live_ninja_beats_a_stale_fighter_snapshot() -> void:
	if JobSystem == null or not JobSystem.jobs.has("ninja"):
		pending("ninja job required")
		return
	var es := get_tree().root.get_node_or_null("EncounterSystem")
	if es == null:
		pending("EncounterSystem autoload required")
		return

	# The snapshot is what a menu-open from BEFORE the job change would have written.
	var stale: Array[Dictionary] = []
	stale.append({"name": "Fighter", "job_id": "fighter", "secondary_job_id": "", "job_level": 1})
	GameState.player_party = stale

	var ninja := Combatant.new()
	ninja.combatant_name = "Fighter"
	ninja.job = JobSystem.get_job("ninja")
	ninja.job_level = 12
	ninja.secondary_job_id = ""
	_host = RosterHost.new()
	_host.name = "GameLoop"
	_host.party = [ninja]
	_host.add_child(ninja)
	get_tree().root.add_child(_host)

	assert_almost_eq(es._party_encounter_rate_reduction(), 0.5, 0.001,
		"a live Ninja must halve encounters even while the save snapshot still says Fighter")
	assert_almost_eq(es._party_average_level(), 12.0, 0.001,
		"field elites scale off the live job level, not the level frozen at the last menu open")

	var walker: Node = load(PLAYER_PATH).new()
	add_child_autofree(walker)
	assert_almost_eq(walker._party_movement_speed_bonus(), 1.5, 0.001,
		"overworld speed must follow the live Ninja, not the stale Fighter snapshot")

	# CONTROL: with no live roster, the snapshot is still the answer. A headless
	# test that only fills player_party must not start reading an empty live party.
	_host.free()
	_host = null
	assert_almost_eq(es._party_encounter_rate_reduction(), 1.0, 0.001,
		"without a live party the snapshot remains the source — a Fighter does not halve encounters")
	assert_almost_eq(es._party_average_level(), 1.0, 0.001,
		"without a live party the snapshot's level is what elites scale from")
