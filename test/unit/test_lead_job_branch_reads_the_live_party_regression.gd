extends GutTest

## A lead_job cutscene branch picks a reward from whoever is leading.
## world1_orrery gives the Bard the Unwritten Chord and everyone else a
## luck charm. The branch was reading GameState.get_party_leader(), and
## that dictionary is the save snapshot: it is rewritten only when the
## pause menu opens and when the game saves. Change the lead to Bard,
## close the menu, turn the quest in — the scene still sees Fighter and
## grants the charm.
##
## party_for_queries() already prefers GameLoop.party and falls back to
## the snapshot when no live roster is in the tree. The branch must do
## the same, or a headless test that only fills the snapshot goes blank.

const PROBE_BARD := "lead_job_probe_bard"
const PROBE_FIGHTER := "lead_job_probe_fighter"
const PROBE_DEFAULT := "lead_job_probe_default"


class RosterHost:
	extends Node
	var party: Array = []


var _host: Node = null
var _director: Node = null
var _prior_party: Array = []
var _prior_leader: int = 0
var _prior_constants: Dictionary = {}
var _prior_flags: Dictionary = {}


func before_each() -> void:
	_prior_party = GameState.player_party.duplicate(true)
	_prior_leader = int(GameState.party_leader_index)
	_prior_constants = GameState.game_constants.duplicate(true)
	_prior_flags = GameState.story_flags.duplicate(true)
	_director = CutsceneDirector.new()
	add_child_autofree(_director)


func after_each() -> void:
	if _host != null and is_instance_valid(_host):
		_host.free()
		_host = null
	var restore: Array[Dictionary] = []
	for entry in _prior_party:
		if entry is Dictionary:
			restore.append(entry)
	GameState.player_party = restore
	GameState.party_leader_index = _prior_leader
	GameState.game_constants = _prior_constants
	GameState.story_flags = _prior_flags


func _branch() -> Dictionary:
	return {
		"type": "branch",
		"condition": "lead_job",
		"cases": {
			"bard": [{"type": "set_flag", "flag": PROBE_BARD, "value": true}],
			"fighter": [{"type": "set_flag", "flag": PROBE_FIGHTER, "value": true}],
			"default": [{"type": "set_flag", "flag": PROBE_DEFAULT, "value": true}],
		},
	}


func _flag_set(flag: String) -> bool:
	return bool(GameState.game_constants.get("cutscene_flag_" + flag, false))


func _clear_probes() -> void:
	for flag in [PROBE_BARD, PROBE_FIGHTER, PROBE_DEFAULT]:
		GameState.game_constants.erase("cutscene_flag_" + flag)
		GameState.story_flags.erase(flag)


func test_a_live_bard_beats_a_stale_fighter_snapshot() -> void:
	if JobSystem == null or JobSystem.get_job("bard").is_empty():
		pending("bard job required")
		return
	# The snapshot is what a menu-open from BEFORE the job change would have written.
	var stale: Array[Dictionary] = []
	stale.append({"name": "Fighter", "job_id": "fighter", "job_level": 1})
	GameState.player_party = stale
	GameState.party_leader_index = 0

	var bard := Combatant.new()
	bard.combatant_name = "Fighter"
	bard.job = JobSystem.get_job("bard")
	_host = RosterHost.new()
	_host.name = "GameLoop"
	_host.party = [bard]
	_host.add_child(bard)
	get_tree().root.add_child(_host)
	var found := get_tree().root.get_node_or_null("GameLoop")
	assert_eq(found, _host, "party_for_queries reads /root/GameLoop — this host must be that node")

	_clear_probes()
	await _director._step_branch(_branch())
	assert_true(_flag_set(PROBE_BARD),
		"the Orrery bard reward must follow the live lead, not the Fighter frozen at the last menu open")
	assert_false(_flag_set(PROBE_FIGHTER),
		"the stale snapshot's fighter case must not also run")
	assert_false(_flag_set(PROBE_DEFAULT),
		"a live bard is an authored case — the branch must not fall through to default")

	# CONTROL: with no live roster, the snapshot is still the answer.
	_host.free()
	_host = null
	_clear_probes()
	await _director._step_branch(_branch())
	assert_true(_flag_set(PROBE_FIGHTER),
		"without a live party the snapshot remains the source — a headless Fighter must still take the fighter case")
	assert_false(_flag_set(PROBE_BARD),
		"removing the live Bard must not leave the branch on the bard case")
