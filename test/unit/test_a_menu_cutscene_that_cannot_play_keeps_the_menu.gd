extends GutTest

## Main 27867, cutscenes 27869: the Gallery and Party Chat hid themselves and set _playing (which drops all input) BEFORE
## play_cutscene, then waited on cutscene_finished. A scene that cannot load (or is refused) never starts, so never finishes:
## the menu stayed invisible and deaf. Both now check can_play first and fall back if the call still did not start.

const MISSING := "no_such_cutscene_for_the_menu_guard"
const CHAT_A := "world1_chapter2"
const CHAT_B := "world1_chapter5"
const GALLERY := preload("res://src/ui/CutsceneGallery.gd")
const PARTY_CHAT := preload("res://src/ui/PartyChatMenu.gd")


## Plays, or passes can_play and then silently does not start (the case only the post-call fallback catches).
class ProbeDirector:
	extends "res://src/cutscene/CutsceneDirector.gd"
	var silent: bool = false
	var playing: bool = false
	var played: Array = []

	func _ready() -> void:
		pass

	func can_play(_cutscene_id: String) -> bool:
		return true

	func play_cutscene(cutscene_id: String, _replay: bool = false) -> void:
		played.append(cutscene_id)
		playing = not silent

	func is_active() -> bool:
		return playing

	func finish(cutscene_id: String) -> void:
		playing = false
		cutscene_finished.emit(cutscene_id)


var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	for id in [CHAT_A, CHAT_B]:
		GameState.game_constants.erase("party_chat_viewed_" + id)


func after_each() -> void:
	GameState.game_constants = _saved_constants


func _gallery(id: String) -> Node:
	var g: Node = GALLERY.new()
	add_child_autofree(g)
	g._items_by_world = {1: [{"id": id, "title": "probe", "unlocked": true}]}
	g._world_order = [1]
	g._selected_world_idx = 0
	g._selected_item_idx = 0
	return g


func _chat(ids: Array) -> Node:
	var m: Node = PARTY_CHAT.new()
	add_child_autofree(m)
	m._chats = []
	for id in ids:
		m._chats.append({"id": id, "title": "probe", "world": 1})
	m._selection = 0
	return m


func test_a_gallery_scene_that_cannot_load_leaves_the_gallery_open() -> void:
	var g := _gallery(MISSING)
	g._try_replay_selected()
	assert_not_null(g._cutscene_director, "CONTROL: the gallery built its own real director")
	assert_false(g._cutscene_director.is_active(), "CONTROL: a scene with no JSON did not start")
	assert_true(g.visible, "the gallery hid itself for a scene that never started: an invisible menu")
	assert_false(g._playing, "the gallery kept _playing for a scene that never started: every press is dropped, it cannot close")


func test_a_gallery_scene_that_plays_hides_then_returns() -> void:
	var g := _gallery(CHAT_A)
	var d := ProbeDirector.new()
	g.add_child(d)
	g._cutscene_director = d
	g._try_replay_selected()
	assert_eq(d.played, [CHAT_A], "CONTROL: the gallery played the selected scene")
	assert_false(g.visible, "the gallery stayed over a scene that is playing")
	assert_true(g._playing, "CONTROL: the gallery is waiting on the scene")
	d.finish(CHAT_A)
	assert_true(g.visible, "the gallery did not come back after its scene finished")
	assert_false(g._playing, "the gallery still drops input after its scene finished")


func test_a_gallery_scene_that_passes_can_play_but_never_starts_returns() -> void:
	var g := _gallery(CHAT_A)
	var d := ProbeDirector.new()
	d.silent = true
	g.add_child(d)
	g._cutscene_director = d
	g._try_replay_selected()
	assert_eq(d.played, [CHAT_A], "CONTROL: the call was made")
	assert_true(g.visible and not g._playing, "a scene that passed can_play and still did not start left the gallery hidden or deaf")
	assert_eq(d.cutscene_finished.get_connections().size(), 0, "the never-started scene left its finish handler connected for the next replay")


func test_a_party_chat_that_cannot_load_leaves_the_menu_open_and_unviewed() -> void:
	var m := _chat([MISSING])
	var closed: Array = []
	m.closed.connect(func(id: String) -> void: closed.append(id))
	m._play_selected()
	assert_not_null(m._cutscene_director, "CONTROL: the menu built its own real director")
	assert_false(m._cutscene_director.is_active(), "CONTROL: a chat with no JSON did not start")
	assert_true(m.visible, "Party Chat hid itself for a chat that never started: an invisible menu")
	assert_false(m._playing, "Party Chat kept _playing for a chat that never started: every press is dropped, it cannot close")
	assert_eq(closed, [], "Party Chat closed itself for a chat that never played")


func test_a_party_chat_that_plays_hides_then_marks_it_viewed_and_closes() -> void:
	var m := _chat([CHAT_A])
	var d := ProbeDirector.new()
	m.add_child(d)
	m._cutscene_director = d
	var closed: Array = []
	m.closed.connect(func(id: String) -> void: closed.append(id))
	m._play_selected()
	assert_false(m.visible, "CONTROL: the menu hid under its playing chat")
	assert_false(PartyChatSystem._is_viewed(CHAT_A), "CONTROL: the chat is not viewed before it finishes")
	d.finish(CHAT_A)
	assert_true(PartyChatSystem._is_viewed(CHAT_A), "a chat that played to the end was not marked viewed")
	assert_eq(closed, [CHAT_A], "the menu did not close with the chat that played")


func test_a_chat_that_never_started_is_not_marked_viewed_by_the_next() -> void:
	## Cutscenes 27869: a handler left connected would mark the REFUSED chat viewed when a later chat finished.
	var m := _chat([CHAT_A, CHAT_B])
	var d := ProbeDirector.new()
	d.silent = true
	m.add_child(d)
	m._cutscene_director = d
	var closed: Array = []
	m.closed.connect(func(id: String) -> void: closed.append(id))
	m._play_selected()
	assert_true(m.visible and not m._playing, "CONTROL: the menu came back from the chat that never started")
	d.silent = false
	m._selection = 1
	m._play_selected()
	d.finish(CHAT_B)
	assert_true(PartyChatSystem._is_viewed(CHAT_B), "CONTROL: the chat that played was marked viewed")
	assert_false(PartyChatSystem._is_viewed(CHAT_A), "a chat that never started was marked viewed when the next one finished")
	assert_eq(closed, [CHAT_B], "the menu closed under the wrong chat, or twice")
