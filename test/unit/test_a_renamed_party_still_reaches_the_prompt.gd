extends GutTest

## A player who names their party in character creation must still get a prompt that
## names them. _party_kit_context SKIPS a member whose kit will not resolve, so one
## unresolvable member costs that member and five cost the whole roster - the prompt
## renders, the composition succeeds, and the model is simply told about nobody.
##
## Every other arm in this corpus seeds JOB names ("Fighter", "Cleric"), which resolve
## through _resolve_job_for_character's THIRD arm - the id is already a job id. A custom
## name reaches none of that: it is in neither CHARACTER_JOB_IDS nor the job list, so the
## live-party lookup is the only thing that can answer, and its failure is silent.
##
## Measured 2026-09-17 against live llama3 with a renamed party (Bran/Sable/Quill/
## Thorne/Lyric): 29/30 compositions delivered, 18/18 member-slot values were real ids,
## 0 phantom members, and the CONTROL intent naming nobody invented nobody 5/5.

const STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

## Deliberately names no job word and nothing in CHARACTER_JOB_IDS.
const RENAMED := {"fighter": "Bran", "cleric": "Sable", "mage": "Quill",
	"rogue": "Thorne", "bard": "Lyric"}

var _stub: Node = null
var _saved_party: Array = []
var _orig_persistence: bool = false


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"CONTROL: no real GameLoop may be in the tree when this file runs")
	_orig_persistence = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _orig_persistence
	GameState.player_party.clear()
	for e in _saved_party:
		GameState.player_party.append(e)
	if _stub != null and is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()
		_stub = null


## FLOOR: every symbol this file reaches on these receivers, named from one place so a
## rename reds here instead of aborting an arm into a silent pass.
func test_floor_the_symbols_this_file_drives() -> void:
	for m in ["_party_kit_context"]:
		assert_true(RuleComposer.has_method(m), "RuleComposer must still have %s" % m)
	for m in ["_resolve_member"]:
		assert_true(AutogrindSystem.has_method(m), "AutogrindSystem must still have %s" % m)
	for m in ["get_deep_check_kit", "_resolve_job_for_character"]:
		assert_true(AutobattleSystem.has_method(m), "AutobattleSystem must still have %s" % m)
	assert_true(GameState.get("player_party") != null, "GameState must still carry player_party")


func _renamed_party(custom: bool) -> void:
	var script := GDScript.new()
	script.source_code = STUB_GAMELOOP
	script.reload()
	_stub = Node.new()
	_stub.set_script(script)
	_stub.name = "GameLoop"
	var members: Array = []
	for job_id in RENAMED.keys():
		var c: Combatant = Combatant.new()
		add_child_autofree(c)
		c.combatant_name = str(RENAMED[job_id]) if custom else str(job_id).capitalize()
		c.job = JobSystem.get_job(str(job_id))
		c.job_level = 1
		members.append(c)
	_stub.party = members
	get_tree().root.add_child(_stub)
	## Typed Array[Dictionary]: a whole-array assignment is a script error that aborts
	## this function, leaving the party unset and every arm below measuring nothing.
	GameState.player_party.clear()
	for c in members:
		GameState.player_party.append((c as Combatant).to_dict())


func _members_of(kit_context: Dictionary) -> Array:
	var out: Array = []
	for m in (kit_context.get("party", []) as Array):
		if m is Dictionary:
			out.append(str((m as Dictionary).get("member", "")))
	out.sort()
	return out


func test_a_renamed_party_reaches_the_kit_context() -> void:
	_renamed_party(true)
	var kc: Dictionary = RuleComposer._party_kit_context()
	assert_true(bool(kc.get("resolved", false)),
		"a renamed party must still resolve, or the prompt names nobody")
	assert_eq(_members_of(kc), ["bran", "lyric", "quill", "sable", "thorne"],
		"and every renamed member must be in it, by their derived id")


func test_each_renamed_member_keeps_their_own_job() -> void:
	_renamed_party(true)
	var by_member: Dictionary = {}
	for m in (RuleComposer._party_kit_context().get("party", []) as Array):
		by_member[str((m as Dictionary).get("member", ""))] = \
			str((m as Dictionary).get("job_id", ""))
	assert_eq(by_member.get("sable", ""), "cleric",
		"the renamed cleric must still read as a cleric")
	assert_eq(by_member.get("bran", ""), "fighter",
		"and the renamed fighter as a fighter")


func test_a_renamed_member_carries_a_real_kit() -> void:
	_renamed_party(true)
	var roster: Array = RuleComposer._party_kit_context().get("party", []) as Array
	## Without this the loop below runs zero times on an empty roster and the arm
	## passes while reporting on nobody - the failure it exists to catch.
	assert_eq(roster.size(), 5, "all five renamed members must be in the roster")
	for m in roster:
		assert_gt(((m as Dictionary).get("kit", []) as Array).size(), 0,
			"%s must reach the prompt with abilities, not an empty roster line" \
				% str((m as Dictionary).get("member", "?")))


## The grammar tells the model "member (a job id such as cleric, or a character name)".
## For a renamed party those are different strings, so both must reach the same person
## or that sentence is a trap.
func test_both_the_job_word_and_the_new_name_reach_her() -> void:
	_renamed_party(true)
	var party: Array = []
	for c in _stub.party:
		party.append(c)
	var by_job = AutogrindSystem._resolve_member(party, "cleric")
	var by_name = AutogrindSystem._resolve_member(party, "sable")
	assert_not_null(by_job, "the job word must reach the renamed cleric")
	assert_eq(str(by_job.combatant_name), "Sable", "and reach the RIGHT member")
	assert_not_null(by_name, "her new name must reach her too")
	assert_eq(str(by_name.combatant_name), "Sable", "and reach the same member")


func test_control_a_name_nobody_has_reaches_nobody() -> void:
	_renamed_party(true)
	var party: Array = []
	for c in _stub.party:
		party.append(c)
	assert_null(AutogrindSystem._resolve_member(party, "gorthax"),
		"CONTROL: an invented member must resolve to nobody, or every arm above is vacuous")


## The job-named party is how every other file in this corpus seeds itself. It resolves
## through a DIFFERENT arm, so a green there says nothing about a renamed party - this
## arm exists to keep that distinction from being re-collapsed.
func test_control_the_job_named_party_still_resolves() -> void:
	_renamed_party(false)
	var kc: Dictionary = RuleComposer._party_kit_context()
	assert_true(bool(kc.get("resolved", false)),
		"CONTROL: the job-named party must still resolve")
	assert_eq(_members_of(kc), ["bard", "cleric", "fighter", "mage", "rogue"],
		"CONTROL: and by their job ids")
