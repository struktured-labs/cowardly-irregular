extends GutTest

## The autobattle grid editor derives every legend token at BUILD time and watched nothing. Plug a
## pad in mid-edit and the keyboard legend stays up; unplug one and it keeps naming buttons for a
## device that is gone.
##
## ⛔ ITS SIBLING ALREADY HAD THIS FIX, AND THE CODEBASE SAYS THE TWO MUST NOT DRIFT.
## `AutogrindGridEditor:109` connects `Input.joy_connection_changed`, with a comment reading
## "Legends here are derived at BUILD time, and this is the screen a player sits on longest" — and
## the autobattle editor's own `_pad_only_token` carries "Same helper name and shape as the
## autogrind editor's, so the two legends cannot drift apart". The helpers matched; the wiring did
## not. This is the sibling the fix was not applied to.
##
## ⚠️ THE SIBLING'S HANDLER DOES NOT TRANSFER VERBATIM, WHICH IS WHY THE GRID ARM BELOW EXISTS.
## The grind editor's handler calls `_build_ui()` alone. Here `_build_ui()` frees every child and
## does NOT repopulate the grid — only `setup()` and the composer-install path pair it with
## `_refresh_grid()`. Copying the sibling would hand the player an EMPTY GRID where their rules
## were, which is worse than the stale legend and invisible to any legend-only assertion.

const EDITOR := preload("res://src/ui/autobattle/AutobattleGridEditor.gd")
const Profiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const SENTINEL := "ZZZ_STALE_SENTINEL"

var _profiles_snapshot: Dictionary = {}


## Instantiating the editor registers a profile on the AutobattleSystem autoload, three calls down,
## keyed by whatever character_id it holds — so restore the whole container, not the keys I wrote.
func before_all() -> void:
	_profiles_snapshot = Profiles.snapshot(AutobattleSystem)


func after_all() -> void:
	Profiles.restore(AutobattleSystem, _profiles_snapshot)


func _editor() -> Node:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	add_child_autofree(sv)
	var ed = EDITOR.new()
	sv.add_child(ed)
	await get_tree().process_frame
	ed.setup("test_fighter", "Test Fighter")
	await get_tree().process_frame
	return ed


func _labels(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append(c)
		_labels(c, out)


func _legend_texts(ed: Node) -> Array:
	var found: Array = []
	_labels(ed, found)
	var out: Array = []
	for l in found:
		out.append((l as Label).text)
	return out


## ⛔ THE CONTROL, first: the editor must actually build labels and rows, or every arm below is
## comparing two empty lists and passing for the wrong reason.
func test_the_editor_builds_a_legend_and_a_grid() -> void:
	var ed = await _editor()
	assert_gt(_legend_texts(ed).size(), 3,
		"CONTROL: the editor must build labels, got %d" % _legend_texts(ed).size())
	assert_gt(ed.rules.size(), 0, "CONTROL: it must hold at least one rule row to display")
	assert_not_null(ed._grid_container, "CONTROL: the grid container must exist after setup")


## ⛔ THE DELIVERY, not the function. An editor that has the handler and never hears the signal
## passes any arm that calls the handler directly, and fails every player.
func test_the_editor_listens_for_a_pad_change() -> void:
	var ed = await _editor()
	var mine: int = 0
	for c in Input.get_signal_connection_list("joy_connection_changed"):
		if c["callable"].get_object() == ed:
			mine += 1
	assert_eq(mine, 1,
		"every legend token here is derived at build time, so the editor must hear "
		+ "joy_connection_changed — %d connection(s) from it. Its sibling AutogrindGridEditor has "
			% mine
		+ "had this since the same defect was fixed there.")


## ⛔ THE DEFECT — AND IT IS SENTINEL-DRIVEN BECAUSE "THE LEGEND IS STILL THERE" IS TRUE WHETHER
## OR NOT ANYTHING REBUILT. Asserting a label count is satisfied by the ORIGINAL build, so it
## measures nothing; the arm has to fail when no rebuild happens. `_build_ui()` frees every child,
## so a sentinel written into a live label cannot survive one.
func test_a_pad_change_rebuilds_the_legend() -> void:
	var ed = await _editor()
	var found: Array = []
	_labels(ed, found)
	assert_gt(found.size(), 3, "CONTROL: there must be a legend to go stale")
	(found[0] as Label).text = SENTINEL
	assert_true(SENTINEL in _legend_texts(ed), "CONTROL: the sentinel must be on screen to begin with")

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame

	assert_false(SENTINEL in _legend_texts(ed),
		"a pad changed and this legend was not re-derived — every token here is resolved at BUILD "
		+ "time, so the keyboard legend stays up for a pad that just arrived, and pad names stay "
		+ "up for one that just left")
	assert_gt(_legend_texts(ed).size(), 3, "…and the rebuild must leave a real legend behind")


## ⛔ THE WRONG FIX, AND NOTHING ELSE HERE CATCHES IT. `_build_ui()` alone — which is exactly what
## the sibling's handler does — frees every child and leaves the grid unpopulated, so the player's
## rules vanish from the screen on a pad change. A legend-only assertion is green through it.
func test_a_pad_change_does_not_empty_the_grid() -> void:
	var ed = await _editor()
	var rows: int = ed.rules.size()
	var was = ed._grid_container
	assert_gt(rows, 0, "CONTROL: there must be rules on screen to lose")

	Input.joy_connection_changed.emit(0, false)
	await get_tree().process_frame

	assert_not_null(ed._grid_container,
		"the grid container must survive a pad change — rebuilding without refreshing leaves the "
		+ "player looking at an empty editor where their rules were")
	assert_ne(ed._grid_container, was,
		"CONTROL: the editor must actually have REBUILT — this arm is about what the rebuild "
		+ "leaves behind, so it means nothing if no rebuild happened")
	assert_eq(ed.rules.size(), rows, "…and the rules themselves must be untouched")
	assert_gt(ed._grid_container.get_child_count(), 0,
		"…and the grid must be REPOPULATED: _build_ui() frees every child and only setup() and the "
		+ "composer-install path pair it with _refresh_grid()")


## ⛔ THE COMPOSER IS A CHILD, so rebuilding under it destroys an in-progress composition. A pad
## change while it is open must DEFER, and the cancel path must then apply it — cancelling performs
## no other action, so nothing else would ever rebuild and the legend would stay stale all session.
func test_a_pad_change_under_the_composer_defers_and_then_lands() -> void:
	var ed = await _editor()
	var stand_in := Control.new()
	ed.add_child(stand_in)
	ed._rule_composer_overlay = stand_in

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame

	assert_true(is_instance_valid(stand_in),
		"a pad change must NOT rebuild under the composer — _build_ui() frees every child and the "
		+ "composer is one, so the player's in-progress composition would be destroyed")
	assert_true(ed._pad_change_pending, "…and the rebuild must be remembered rather than dropped")

	ed._on_composer_cancelled()
	await get_tree().process_frame

	assert_false(ed._pad_change_pending,
		"cancelling the composer must apply the deferred rebuild — cancelling performs no other "
		+ "action, so nothing else would rebuild and the legend stays stale for the session")
	assert_gt(_legend_texts(ed).size(), 3, "…and the legend must be back")
