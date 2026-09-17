extends GutTest

## Character creation lets a player delete a name to nothing: the DEL guard stops AT zero
## (CharacterCreationScreen :897 / :911, `length() > 0`) and `_confirm_creation` :994 emits
## with no validation. That PC reaches the party with combatant_name == "".
##
## The composer derived its member id from that name, so the roster line carried an EMPTY id -
## and an empty id is not merely unresolvable. AutogrindSystem._member_predicate reads a blank
## "member" as ANY party member, so a rule composed FOR this character silently became a rule
## about the whole party. It fires too often rather than never, which is the harder half to
## notice: _resolve_member("") returning null would at least be inert.

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
	assert_true(RuleComposer.has_method("_job_id_of"),
		"RuleComposer must still have _job_id_of")
	assert_true(AutogrindSystem.has_method("_resolve_member"),
		"AutogrindSystem must still have _resolve_member")


func _party(pairs: Array) -> void:
	if _stub != null and is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()
		_stub = null
	var sc := GDScript.new()
	sc.source_code = STUB_GAMELOOP
	sc.reload()
	_stub = Node.new()
	_stub.set_script(sc)
	_stub.name = "GameLoop"
	var members: Array = []
	for p in pairs:
		var c: Combatant = Combatant.new()
		add_child_autofree(c)
		c.combatant_name = str(p[0])
		c.job = JobSystem.get_job(str(p[1]))
		c.job_level = 6
		members.append(c)
	_stub.party = members
	get_tree().root.add_child(_stub)
	## Typed Array[Dictionary]: a whole-array assignment aborts this function.
	GameState.player_party.clear()
	for c in members:
		GameState.player_party.append((c as Combatant).to_dict())


func _ids() -> Array:
	var out: Array = []
	for m in (RuleComposer._party_kit_context().get("party", []) as Array):
		out.append(str((m as Dictionary).get("member", "")))
	return out


func _kit_of_job(job_id: String) -> Array:
	for m in (RuleComposer._party_kit_context().get("party", []) as Array):
		if str((m as Dictionary).get("job_id", "")) == job_id:
			return (m as Dictionary).get("kit", []) as Array
	return []


func test_a_nameless_pc_is_never_given_an_empty_id() -> void:
	_party([["Bran", "fighter"], ["", "cleric"]])
	var ids: Array = _ids()
	assert_eq(ids.size(), 2, "both members must reach the prompt")
	assert_false(ids.has(""),
		"no roster line may carry an empty member id - the engine reads it as ANY member")


func test_the_id_it_gets_reaches_that_character() -> void:
	_party([["Bran", "fighter"], ["", "cleric"]])
	var party: Array = []
	for c in _stub.party:
		party.append(c)
	for id in _ids():
		var who = AutogrindSystem._resolve_member(party, id)
		assert_not_null(who, "the id '%s' must reach a real member" % id)


func test_the_nameless_pc_keeps_her_own_kit() -> void:
	_party([["Bran", "fighter"], ["", "cleric"]])
	var kit: Array = _kit_of_job("cleric")
	assert_true(kit.has("cure"), "she must still be offered with her own abilities")


func test_two_nameless_pcs_do_not_collapse() -> void:
	_party([["", "fighter"], ["", "cleric"]])
	var jobs: Array = []
	for m in (RuleComposer._party_kit_context().get("party", []) as Array):
		jobs.append(str((m as Dictionary).get("job_id", "")))
	jobs.sort()
	assert_eq(jobs, ["cleric", "fighter"],
		"each nameless PC must keep their own job, not inherit the first one's")
	assert_true(_kit_of_job("cleric").has("cure"), "and their own kit with it")


## The engine's contract, pinned so the arms above cannot be read as arbitrary.
func test_control_the_engine_refuses_an_empty_key() -> void:
	_party([["Bran", "fighter"], ["", "cleric"]])
	var party: Array = []
	for c in _stub.party:
		party.append(c)
	assert_null(AutogrindSystem._resolve_member(party, ""),
		"CONTROL: an empty key reaches nobody, which is why emitting one is a defect")


func test_control_a_named_party_is_untouched() -> void:
	_party([["Bran", "fighter"], ["Sable", "cleric"]])
	var ids: Array = _ids()
	ids.sort()
	assert_eq(ids, ["bran", "sable"],
		"CONTROL: ordinary names must still derive from the name, not the job")
