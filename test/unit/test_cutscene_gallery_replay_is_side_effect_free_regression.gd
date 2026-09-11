extends GutTest

## The cutscene gallery spun up its own Director and replayed a scene FOR REAL: every replay
## re-ran give_item / grant_item (a free-item dupe through a menu), rewrote set_flag and the W6
## choice answer, and a spotlight-unlock replay would have launched the duel from inside the
## gallery. Staged scenes replayed their puppets at coordinates authored for another map.
## play_cutscene(id, replay = true) now plays the scene while leaving the world alone, and a
## replayed staged scene falls back to overlay.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")
const FLAG := "test_gallery_replay_flag"
const CHOICE_FLAG := "test_gallery_replay_choice"

var _d: Node
var _stub: Node = null


class StubLeader extends RefCounted:
	var combatant_name := "stub"
	var adds: Array = []
	var removes: Array = []
	func add_item(id: String, qty: int) -> void:
		adds.append([id, qty])
	func get_item_count(_id: String) -> int:
		return 1
	func remove_item(id: String, qty: int) -> bool:
		removes.append([id, qty])
		return true


class StubLoop extends Node:
	var party: Array = []
	var battles: int = 0
	func start_solo_battle(_who: String, _enemy: String, _opts: Dictionary) -> String:
		battles += 1
		await get_tree().process_frame
		return "victory"


func before_each() -> void:
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_clear_flags()


func after_each() -> void:
	_clear_flags()
	if _d and is_instance_valid(_d):
		_d._active = false
	if _stub and is_instance_valid(_stub):
		_stub.get_parent().remove_child(_stub)
		_stub.free()
	_stub = null


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


func _clear_flags() -> void:
	var gs := _gs()
	if gs == null:
		return
	for f in [FLAG, CHOICE_FLAG]:
		gs.game_constants.erase("cutscene_flag_" + f)
		if gs.has_method("set_story_flag"):
			gs.set_story_flag(f, false)


func _flag_set(f: String) -> bool:
	var gs := _gs()
	return gs != null and gs.game_constants.get("cutscene_flag_" + f, false) == true


func _install_stub() -> StubLoop:
	assert_null(get_tree().root.get_node_or_null("GameLoop"), "control: no real GameLoop in the test tree")
	var stub := StubLoop.new()
	stub.name = "GameLoop"
	stub.party = [StubLeader.new()]
	get_tree().root.add_child(stub)
	_stub = stub
	return stub


func _scene(staged: bool = false) -> Dictionary:
	var data := {"id": "t", "world": 1, "steps": [
		{"type": "give_item", "item": "fool_card"},
		{"type": "set_flag", "flag": FLAG},
		{"type": "battle", "combatants": ["fighter"], "enemies": ["slime"]},
		{"type": "update_item", "item": "fool_card", "new_id": "wild_card"},
	]}
	if staged:
		data["presentation"] = "staged"
	return data


func _play(data: Dictionary, replay: bool) -> void:
	var runner := func() -> void:
		await _d.play_cutscene_from_data("t", data, replay)
	runner.call()
	var frames := 0
	while _d._active and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_false(_d._active, "control: the scene finished within budget")


func test_a_replay_leaves_items_flags_and_duels_alone() -> void:
	var stub := _install_stub()
	var leader: StubLeader = stub.party[0]
	await _play(_scene(), true)
	assert_eq(leader.adds, [], "a replay grants nothing — give_item and update_item were a free-item dupe")
	assert_eq(leader.removes, [], "and takes nothing")
	assert_false(_flag_set(FLAG), "a replay writes no flags")
	assert_eq(stub.battles, 0, "a replay launches no duel")
	assert_false(_d._replay, "the replay flag clears at the end of the scene")


func test_a_real_play_of_the_same_scene_still_changes_the_world() -> void:
	# ARM+: a Director that ignored every mutating step would pass the test above.
	var stub := _install_stub()
	var leader: StubLeader = stub.party[0]
	await _play(_scene(), false)
	assert_eq(leader.adds.size(), 2, "give_item and update_item both add on a real play: %s" % [leader.adds])
	assert_eq(leader.removes.size(), 1, "update_item removes the old card on a real play")
	assert_true(_flag_set(FLAG), "set_flag writes on a real play")
	assert_eq(stub.battles, 1, "the duel runs on a real play")


func test_a_skipped_replay_writes_no_flags_either() -> void:
	# The skip path re-applies set_flag steps so scenes never loop — a replay must not use that door.
	_install_stub()
	var runner := func() -> void:
		await _d.play_cutscene_from_data("t", _scene(), true)
	runner.call()
	await get_tree().process_frame
	_d._trigger_skip()
	var frames := 0
	while _d._active and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_false(_flag_set(FLAG), "skip + replay writes no flags")


func test_grant_item_replay_shows_no_grant() -> void:
	var stub := _install_stub()
	var leader: StubLeader = stub.party[0]
	_d._skipping = true  # skip the popup; the grant is the subject
	_d._replay = true
	await _d._step_grant_item({"type": "grant_item", "item": "fool_card", "name": "X"})
	assert_eq(leader.adds, [], "a replayed grant_item does not re-grant the key item")
	_d._replay = false
	await _d._step_grant_item({"type": "grant_item", "item": "fool_card", "name": "X"})
	assert_eq(leader.adds.size(), 1, "control: a real grant_item grants")


func test_a_replayed_choice_does_not_overwrite_the_players_answer() -> void:
	_d._replay = true
	_d._set_choice_flag({"text": "Yes", "flag": CHOICE_FLAG})
	assert_false(_flag_set(CHOICE_FLAG), "a replayed choice writes nothing")
	_d._replay = false
	_d._set_choice_flag({"text": "Yes", "flag": CHOICE_FLAG})
	assert_true(_flag_set(CHOICE_FLAG), "control: a real choice writes")


func test_a_replayed_staged_scene_plays_as_overlay() -> void:
	_install_stub()
	# _staged is decided synchronously at entry, before the first await — and with a stub duel and no map the whole scene can finish inside one frame, so read it right after the call.
	var runner := func() -> void:
		await _d.play_cutscene_from_data("t", _scene(true), true)
	runner.call()
	assert_false(_d._staged, "a replay has no authored stage under it — overlay, not puppets at foreign coordinates")
	var frames := 0
	while _d._active and frames < 240:
		await get_tree().process_frame
		frames += 1
	var runner2 := func() -> void:
		await _d.play_cutscene_from_data("t", _scene(true), false)
	runner2.call()
	assert_true(_d._staged, "control: a real play of a staged scene stages")
	frames = 0
	while _d._active and frames < 240:
		await get_tree().process_frame
		frames += 1


class RecorderDirector extends CanvasLayer:
	signal cutscene_finished(id: String)
	var last_id := ""
	var last_replay := false
	var calls := 0
	func play_cutscene(id: String, replay: bool = false) -> void:
		calls += 1
		last_id = id
		last_replay = replay
		cutscene_finished.emit(id)


func test_the_gallery_asks_for_a_replay() -> void:
	var gallery := CutsceneGallery.new()
	add_child_autofree(gallery)
	var rec := RecorderDirector.new()
	gallery.add_child(rec)
	gallery._cutscene_director = rec
	gallery._items_by_world = {1: [{"id": "world1_prologue", "title": "t", "unlocked": true}]}
	gallery._world_order = [1]
	gallery._selected_world_idx = 0
	gallery._selected_item_idx = 0
	gallery._try_replay_selected()
	assert_eq(rec.calls, 1, "control: the gallery played the selected entry")
	assert_true(rec.last_replay, "the gallery must ask the Director for a REPLAY, never a real play")
