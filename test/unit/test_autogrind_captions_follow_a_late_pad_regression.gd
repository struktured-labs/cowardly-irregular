extends GutTest

## Every caption in this lane is derived at BUILD time and nothing re-derived it. Measured before
## this fix: 6 lane surfaces call InputProfileManager and ZERO handled joy_connection_changed, while
## ControlsMenu — one lane over — already did. So a player who opened the autogrind console and THEN
## plugged in a pad read "[+] START GRINDING" with a pad in hand, and a player who unplugged kept
## reading "Plus / [+]" for a device that was gone. The derivation was right; it just never re-ran.
##
## ⛔ HEADLESS HAS NO JOYPADS, so the signal never fires on its own and a test that waits for it
## passes vacuously forever. These arms EMIT Input.joy_connection_changed and observe what the
## handler does — the signal is the seam, not the pad.

var _ui
var _editor


## ⚠️ THE AWAIT IS LOAD-BEARING AND IT COST ME TWO FALSE REDS AND ONE FALSE GREEN.
## AutogrindUI._ready does `call_deferred("_build_ui")`. Without draining that here it lands during
## an ARM's await, freeing and rebuilding every child — so the "did it rebuild?" arms measured the
## CONSTRUCTOR and not the handler. It read as: the ring vanished (it was the deferred build, not my
## code), a hidden console rebuilt (same), and — worse — the rebuild arm PASSED, because ids really
## had changed. A false green in the arm that defines the feature.
func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_editor = preload("res://src/ui/autogrind/AutogrindGridEditor.gd").new()
	add_child_autofree(_editor)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


## Arm 1: both surfaces must actually be listening. This is the arm that would have caught the
## original defect, and it is keyed on the CONNECTION, not on a function existing.
func test_both_live_surfaces_listen_for_a_pad_arriving() -> void:
	for pair in [["AutogrindUI", _ui], ["AutogrindGridEditor", _editor]]:
		assert_true(Input.joy_connection_changed.is_connected(pair[1]._on_joy_connection_changed),
			"%s does not listen for joy_connection_changed — its captions freeze at build time" % pair[0])


## Arm 2: the console REBUILDS when a pad arrives. Observed through the tree, not through a flag:
## the children are freed and replaced, so a rebuild changes the instance ids under the node.
## ⚠️ Do NOT build again inside an arm. before_each already built and drained; a second build leaves
## the old children QUEUED BUT ALIVE, so ids then differ because the frees FLUSHED — measured
## 22 before / 11 after, which reads as a rebuild and is not one.
func test_a_pad_arriving_rebuilds_the_console() -> void:
	_ui.visible = true
	var before: Array = []
	for c in _ui.get_children():
		before.append(c.get_instance_id())
	assert_gt(before.size(), 0, "CONTROL: the console must have built something to rebuild")

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame
	await get_tree().process_frame

	var after: Array = []
	for c in _ui.get_children():
		after.append(c.get_instance_id())
	gut.p("  console children: %d before, %d after" % [before.size(), after.size()])
	assert_ne(before, after,
		"a pad connected and the console did not rebuild — every caption still says what it said with no pad")


## Arm 3: THE ONE THAT PROTECTS THE PLAYER FROM THE FIX. _build_ui frees every child and the options
## ring IS one, so a naive handler yanks the ring out from under someone mid-selection.
func test_a_pad_arriving_does_not_vanish_an_open_options_ring() -> void:
	_ui.visible = true
	_ui._open_options_ring()
	assert_true(is_instance_valid(_ui._options_ring), "CONTROL: the ring must be open for this arm to mean anything")

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(is_instance_valid(_ui._options_ring),
		"a pad connected and the open options ring was freed — the player lost their selection mid-choice")
	assert_true(_ui._pad_change_pending,
		"the rebuild was skipped but not REMEMBERED — backing out of the ring performs no action, so the captions would stay stale for the rest of the session")


## Arm 4: and the deferred rebuild actually lands when the ring closes. A pending flag nothing
## consumes is the same bug with an extra variable.
func test_the_deferred_rebuild_lands_when_the_ring_closes() -> void:
	_ui.visible = true
	_ui._open_options_ring()
	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame
	await get_tree().process_frame

	## ⚠️ EXCLUDE THE RING from the before-snapshot. _close_options_ring queue_frees it, so the child
	## list changes by ONE on its own — "ids differ" is then satisfied with no rebuild at all, and
	## this arm passes on a console that never reconnected. Found by predicting Failing 4 for the
	## no-connect mutation and measuring 3.
	var before: Array = []
	for c in _ui.get_children():
		if c != _ui._options_ring:
			before.append(c.get_instance_id())

	_ui._close_options_ring()
	await get_tree().process_frame
	await get_tree().process_frame

	var after: Array = []
	for c in _ui.get_children():
		after.append(c.get_instance_id())
	assert_false(_ui._pad_change_pending, "the pending flag was not cleared — the next ring close would rebuild again")
	assert_ne(before, after,
		"closing the ring did not apply the deferred rebuild, so the captions stayed stale")


## Arm 5: a pad arriving while the console is HIDDEN must not rebuild. Both paths that make it
## visible again already end in _build_ui, so rebuilding here is wasted work on a screen nobody
## is looking at — and it would run during a grind, when this node is hidden behind the monitor.
func test_a_hidden_console_does_not_rebuild() -> void:
	_ui.visible = false
	var before: Array = []
	for c in _ui.get_children():
		before.append(c.get_instance_id())

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame
	await get_tree().process_frame

	var after: Array = []
	for c in _ui.get_children():
		after.append(c.get_instance_id())
	assert_eq(before, after,
		"a hidden console rebuilt on a pad change — the paths that re-show it already rebuild")


## Arm 6: the editor rebuilds too, and defers under its own modal for the same reason.
func test_the_editor_rebuilds_and_defers_under_the_composer() -> void:
	var before: Array = []
	for c in _editor.get_children():
		before.append(c.get_instance_id())
	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var after: Array = []
	for c in _editor.get_children():
		after.append(c.get_instance_id())
	assert_ne(before, after, "a pad connected and the grid editor kept its build-time legend")

	## Stand in for the composer being open — the guard is `is_instance_valid`, so any live child
	## node exercises the same branch without instantiating the whole overlay scene.
	var stand_in := Control.new()
	_editor.add_child(stand_in)
	_editor._rule_composer_overlay = stand_in
	var mid: Array = []
	for c in _editor.get_children():
		mid.append(c.get_instance_id())
	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var post: Array = []
	for c in _editor.get_children():
		post.append(c.get_instance_id())
	assert_eq(mid, post,
		"the editor rebuilt under an open composer — that destroys the composition the player is writing")
	assert_true(_editor._pad_change_pending, "the skipped rebuild was not remembered")
	_editor._rule_composer_overlay = null
