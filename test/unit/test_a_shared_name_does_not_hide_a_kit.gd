extends GutTest

## Nothing in character creation stops a player naming two party members the same, and
## the letter grid's NAME_CHARS carries both cases, so "Bob" and "bob" derive one id too.
##
## _party_kit_context keys every lookup on that derived id, and the live-party lookup
## returns the FIRST match. The second member was therefore described to the model with
## the FIRST member's job and kit: name two characters "Bob" and the cleric is announced
## as a second fighter while cure/protect/pray never reach the prompt at all. The model
## cannot write a rule using an ability it was never told the party has.
##
## The engine was never wrong - _resolve_member matches job id BEFORE combatant_name, so
## member "cleric" reaches her correctly. Only the prompt lost her.

const STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

var _stub: Node = null
var _saved: Array = []
var _orig_persistence: bool = false


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"CONTROL: no real GameLoop may be in the tree when this file runs")
	_orig_persistence = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved = GameState.player_party.duplicate(true)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _orig_persistence
	GameState.player_party.clear()
	for e in _saved:
		GameState.player_party.append(e)
	if _stub != null and is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()
		_stub = null


func test_floor_the_symbols_this_file_drives() -> void:
	assert_true(RuleComposer.has_method("_party_kit_context"),
		"RuleComposer must still have _party_kit_context")
	assert_true(AutogrindSystem.has_method("_resolve_member"),
		"AutogrindSystem must still have _resolve_member")
	assert_true(AutobattleSystem.has_method("get_deep_check_kit"),
		"AutobattleSystem must still have get_deep_check_kit")


func _party(pairs: Array) -> void:
	var script := GDScript.new()
	script.source_code = STUB_GAMELOOP
	script.reload()
	_stub = Node.new()
	_stub.set_script(script)
	_stub.name = "GameLoop"
	var members: Array = []
	for p in pairs:
		var c: Combatant = Combatant.new()
		add_child_autofree(c)
		c.combatant_name = str(p[0])
		c.job = JobSystem.get_job(str(p[1]))
		c.job_level = 1
		members.append(c)
	_stub.party = members
	get_tree().root.add_child(_stub)
	## Typed Array[Dictionary]: a whole-array assignment aborts this function.
	GameState.player_party.clear()
	for c in members:
		GameState.player_party.append((c as Combatant).to_dict())


func _roster() -> Array:
	return RuleComposer._party_kit_context().get("party", []) as Array


func _kit_of_job(job_id: String) -> Array:
	for m in _roster():
		if str((m as Dictionary).get("job_id", "")) == job_id:
			return (m as Dictionary).get("kit", []) as Array
	return []


func test_a_shared_name_still_reports_two_jobs() -> void:
	_party([["Bob", "fighter"], ["Bob", "cleric"]])
	var roster: Array = _roster()
	assert_eq(roster.size(), 2, "both members must reach the prompt")
	var jobs: Array = []
	for m in roster:
		jobs.append(str((m as Dictionary).get("job_id", "")))
	jobs.sort()
	assert_eq(jobs, ["cleric", "fighter"],
		"each must be announced with their OWN job, not the first member's")


func test_the_shadowed_members_abilities_reach_the_prompt() -> void:
	_party([["Bob", "fighter"], ["Bob", "cleric"]])
	var cleric_kit: Array = _kit_of_job("cleric")
	assert_true(cleric_kit.has("cure"),
		"the second Bob's cure must reach the model, or no rule can ever use it")
	assert_true(cleric_kit.has("protect"), "and protect with it")


func test_case_alone_is_enough_to_collide() -> void:
	## NAME_CHARS carries both cases, so this is typeable on the letter grid.
	_party([["Bob", "fighter"], ["bob", "cleric"]])
	assert_true(_kit_of_job("cleric").has("cure"),
		"a case-only difference derives one id and must not hide her kit either")


func test_the_engine_still_reaches_her_by_job() -> void:
	## The prompt was the broken half; this pins that the engine's half was not.
	_party([["Bob", "fighter"], ["Bob", "cleric"]])
	var party: Array = []
	for c in _stub.party:
		party.append(c)
	var by_job = AutogrindSystem._resolve_member(party, "cleric")
	assert_not_null(by_job, "the job word must still reach the shadowed member")
	assert_eq(str((by_job.job as Dictionary).get("id", "")), "cleric",
		"and reach the RIGHT one")


func test_control_distinct_names_are_untouched() -> void:
	_party([["Bob", "fighter"], ["Ann", "cleric"]])
	var ids: Array = []
	for m in _roster():
		ids.append(str((m as Dictionary).get("member", "")))
	ids.sort()
	assert_eq(ids, ["ann", "bob"],
		"CONTROL: the ordinary path must be unchanged - ids still come from names")
	assert_true(_kit_of_job("cleric").has("cure"),
		"CONTROL: and a distinctly-named cleric still carries her kit")
