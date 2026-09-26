extends GutTest

## Quit to Title and New Game replace game_constants, which is where a seen
## tutorial hint is stamped (tutorial_<id>). TutorialHint._shown_hints is a
## process cache of those stamps. It used to win on its own, so the overworld
## load that shows Movement and then Quest Log stayed silent on the second
## run of the same session — the new file had never been taught.

const GS := preload("res://src/meta/GameState.gd")

const OPENING := ["movement", "quest_log"]

var _saved_static: Dictionary = {}
var _saved_stamps: Dictionary = {}


func before_each() -> void:
	TutorialHints._pending.clear()
	TutorialHint._active_count = 0
	for id in OPENING:
		_saved_static[id] = bool(TutorialHint._shown_hints.get(id, false))
		_saved_stamps[id] = GameState != null and bool(GameState.game_constants.get("tutorial_" + id, false))
		TutorialHint._shown_hints[id] = true
		if GameState:
			GameState.game_constants["tutorial_" + id] = true


func after_each() -> void:
	TutorialHints._pending.clear()
	TutorialHint._active_count = 0
	for id in OPENING:
		if _saved_static.get(id, false):
			TutorialHint._shown_hints[id] = true
		else:
			TutorialHint._shown_hints.erase(id)
		if GameState == null:
			continue
		if _saved_stamps.get(id, false):
			GameState.game_constants["tutorial_" + id] = true
		else:
			GameState.game_constants.erase("tutorial_" + id)


func test_new_game_drops_the_opening_hint_stamps() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.game_constants["tutorial_movement"] = true
	gs.game_constants["tutorial_quest_log"] = true
	gs.reset_game_state()
	assert_false(bool(gs.game_constants.get("tutorial_movement", false)),
		"New Game must drop the movement stamp or the next overworld treats the player as already taught")
	assert_false(bool(gs.game_constants.get("tutorial_quest_log", false)),
		"New Game must drop the quest-log stamp too — both fire on the first overworld load")


func test_a_fresh_run_sees_movement_then_the_quest_log() -> void:
	if GameState == null:
		pending("GameState autoload missing")
		return
	var parent := Node.new()
	add_child_autofree(parent)
	TutorialHints.show(parent, "movement")
	assert_eq(_visible(parent).size(), 0,
		"CONTROL: a save that already stamped Movement must stay quiet, or a later green cannot mean the fresh run actually showed it")
	# reset_game_state replaces the dict. These two keys are what that drops; the session cache stays.
	GameState.game_constants.erase("tutorial_movement")
	GameState.game_constants.erase("tutorial_quest_log")
	TutorialHints.show(parent, "movement")
	TutorialHints.show(parent, "quest_log")
	var live := _visible(parent)
	assert_eq(live.size(), 1,
		"New Game left Movement buried — the session cache still said seen after the save stamp was cleared")
	assert_eq(str(live[0]._current_hint_id), "movement",
		"the panel on screen must be Movement, the first hint the overworld asks for")
	live[0]._dismiss()
	var queued := _visible(parent)
	assert_eq(queued.size(), 1,
		"Quest Log is asked for in the same load, behind Movement, and must appear once Movement is dismissed")
	assert_eq(str(queued[0]._current_hint_id), "quest_log",
		"the deferred panel must be Quest Log, not a second copy of Movement")


func _visible(parent: Node) -> Array:
	var out: Array = []
	for c in parent.get_children():
		if c is TutorialHint and c.visible and not c.is_queued_for_deletion():
			out.append(c)
	return out
