extends GutTest

## The autobattle grid editor rebuilds its legend when a pad arrives or leaves, and `_build_ui()`
## frees EVERY child. Four modals are parented to the editor itself, so a rebuild under any one of
## them destroys it:
##     _option_picker :2521   _keyboard :3199   _share_picker :3278   _rule_composer_overlay :3493
##
## ⛔ THE FIRST VERSION OF THAT HANDLER GUARDED `_rule_composer_overlay` ALONE — mine, and this file
## is the repair. Plugging a pad in while the on-screen keyboard was open would have destroyed it
## mid-name-entry, taking whatever the player had typed. The sibling `AutogrindGridEditor` has the
## same single-member guard; that is its lane's to take or leave, and it is reported not edited.
##
## 🔑 THE MEMBER LIST IS DERIVED FROM THE EDITOR'S OWN SOURCE, not restated here. A hand-list is a
## snapshot: the fifth modal somebody adds is exactly the one that gets eaten, and a guard that
## cannot see its own corpus shrink is the shape this lane has spent the day removing.

const EDITOR := preload("res://src/ui/autobattle/AutobattleGridEditor.gd")
const EDITOR_PATH := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const Profiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _profiles_snapshot: Dictionary = {}


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


## Every `Control` member this editor parents to itself as a modal, read off its own source.
func _declared_modals() -> Array:
	var code: String = GdSource.code_of(EDITOR_PATH)
	var out: Array = []
	var re := RegEx.new()
	re.compile("^var (_[A-Za-z0-9_]*(?:modal|keyboard|picker|overlay))\\s*:")
	for line in code.split("\n"):
		var m := re.search(str(line).strip_edges())
		if m:
			out.append(m.get_string(1))
	return out


## ⛔ THE CONTROL, and it is the anti-vacuity floor for the derivation: if the regex stops matching,
## every arm below is checking an empty list and passes perfectly.
func test_the_editor_declares_several_modals() -> void:
	var mods: Array = _declared_modals()
	assert_gt(mods.size(), 3,
		"CONTROL: the editor declares several modal members; derived %s" % [mods])
	assert_true("_keyboard" in mods, "CONTROL: the on-screen keyboard must be among them")
	assert_true("_rule_composer_overlay" in mods, "CONTROL: …and the composer")


## ⛔ THE GUARD MUST CONSULT EVERY ONE OF THEM. This is the arm that reds when somebody adds a fifth
## modal and does not add it here — the case a hand-list cannot see.
func test_the_modal_guard_consults_every_declared_modal() -> void:
	var code: String = GdSource.code_of(EDITOR_PATH)
	var at: int = code.find("func _modal_open")
	assert_gt(at, -1, "the editor must have a _modal_open guard")
	var stop: int = code.find("\nfunc ", at + 10)
	var body: String = code.substr(at, stop - at) if stop > at else code.substr(at)

	var missed: Array = []
	for m in _declared_modals():
		if not body.contains(m):
			missed.append(m)
	assert_true(missed.is_empty(),
		"%s are modals parented to this editor and _modal_open does not consult them — a pad " % [missed]
		+ "change rebuilds, _build_ui frees every child, and the player loses whatever that modal "
		+ "held. The on-screen keyboard is one of them.")


## ⛔ THE DEFECT, driven: a pad change with the keyboard open must not destroy it.
func test_a_pad_change_does_not_destroy_an_open_keyboard() -> void:
	var ed = await _editor()
	var stand_in := Control.new()
	ed.add_child(stand_in)
	ed._keyboard = stand_in

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame

	assert_true(is_instance_valid(stand_in),
		"a pad arrived while the on-screen keyboard was open and the rebuild freed it — the player "
		+ "loses the name they were typing")
	assert_true(ed._pad_change_pending, "…and the rebuild must be remembered, not dropped")


## The same for a picker, so the fix is not keyboard-shaped.
func test_a_pad_change_does_not_destroy_an_open_picker() -> void:
	var ed = await _editor()
	var stand_in := Control.new()
	ed.add_child(stand_in)
	ed._option_picker = stand_in

	Input.joy_connection_changed.emit(0, false)
	await get_tree().process_frame

	assert_true(is_instance_valid(stand_in), "an open option picker must survive a pad change too")
	assert_true(ed._pad_change_pending, "…and the rebuild is still owed")


## ⛔ AND THE DEFERRED REBUILD MUST ACTUALLY LAND. Only the COMPOSER's cancel path applied it
## before, so a pad swapped under the keyboard or either picker left the legend stale for the whole
## session — the defect the defer exists to avoid, arriving through the defer itself.
func test_the_deferred_rebuild_lands_once_the_modal_closes() -> void:
	var ed = await _editor()
	var stand_in := Control.new()
	ed.add_child(stand_in)
	ed._keyboard = stand_in

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame
	assert_true(ed._pad_change_pending, "CONTROL: the rebuild must be pending before we close it")

	stand_in.queue_free()
	ed._keyboard = null
	await get_tree().process_frame

	ed._input(InputEventKey.new())
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(ed._pad_change_pending,
		"once the modal is gone the owed rebuild must be applied at the player's next input — "
		+ "nothing else would ever rebuild, and the legend stays stale for the session")
	assert_not_null(ed._grid_container, "…and the grid must still be there after it")
	assert_gt(ed._grid_container.get_child_count(), 0, "…and repopulated")
