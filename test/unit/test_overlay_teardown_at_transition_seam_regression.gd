extends GutTest

## struktured's open item, 2026-09-06: the autogrind console outlives a scene swap.
##
## THE SHAPE, which is why this fix is at a seam and not at a symptom: four sites had each
## patched one consequence of ONE missing teardown —
##   2026-08-17  editor outlived a battle          -> guard at the encounter site
##   2026-08-23  editor outlived the victory screen -> teardown in _on_battle_ended
##   2026-09-06  hidden console blocked encounters  -> heal inside the encounter guard
##   2026-09-06  console outlives a map swap        -> nothing at all
## MEASURED before the fix: 8 _area_*_transition_* functions, 0 mentioning either overlay.
##
## The teardown must SAVE, not free: rules reach AutogrindSystem only on grind start, so a
## naive free would turn a rare annoyance into losing rule edits on every transition.

const GL_SRC := "res://src/GameLoop.gd"
const UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"

var _gl: Node = null
var _saved_rules: Array = []


func before_each() -> void:
	_gl = load(GL_SRC).new()
	if AutogrindSystem:
		AutogrindSystem._test_disable_persistence = true
	_saved_rules = AutogrindSystem.get_autogrind_rules().duplicate(true) if AutogrindSystem else []


func after_each() -> void:
	if _gl != null:
		_gl.free()
		_gl = null
	if AutogrindSystem:
		AutogrindSystem.set_autogrind_rules(_saved_rules)


func _attach_console() -> Node:
	var layer := CanvasLayer.new()
	var ui: Control = load(UI_SRC).new()
	_gl._autogrind_ui_layer = layer
	_gl._autogrind_ui = ui
	layer.add_child(ui)
	add_child_autofree(layer)
	return ui


## Behavioural: an open console must not survive the seam.
func test_the_console_does_not_survive_a_scene_change() -> void:
	var ui := _attach_console()
	_gl._is_autogrinding = false
	assert_not_null(_gl._autogrind_ui, "precondition: a console is open")
	_gl._free_overlays_for_scene_change()
	assert_true(_gl._autogrind_ui == null or not is_instance_valid(_gl._autogrind_ui),
		"the console must be gone after a scene change — it used to ride into the new map")
	assert_true(ui == null or not is_instance_valid(ui) or ui.is_queued_for_deletion(),
		"and the node itself must be torn down, not merely unreferenced")


## THE DATA-LOSS ARM. _close_ui does NOT persist; rules reach AutogrindSystem only on grind
## start. A teardown the player did not ask for must not eat their edits.
func test_an_involuntary_teardown_keeps_the_players_rules() -> void:
	var ui := _attach_console()
	_gl._is_autogrinding = false
	# A rule the validator ACCEPTS — set_autogrind_rules refuses invalid input with no mutation,
	# so a malformed fixture would test the rejection path and read as a teardown bug
	var marker := [{"conditions": [{"type": "party_hp_avg", "op": "<", "value": 42}],
			"actions": [{"type": "heal_party"}]}]
	ui.rules = marker.duplicate(true)
	_gl._free_overlays_for_scene_change()
	var kept: Array = AutogrindSystem.get_autogrind_rules()
	assert_eq(kept.size(), 1, "the rule the player authored must survive the teardown")
	assert_eq(int(kept[0]["conditions"][0]["value"]), 42,
		"and must be THEIR rule, not a default — a bare free would have discarded it")


## cowir-autogrind's warning: freeing mid-grind strands GameLoop's controller. Auto-advance
## crosses regions, so this seam fires DURING a grind routinely.
func test_a_live_grind_keeps_its_console() -> void:
	_attach_console()
	_gl._is_autogrinding = true
	_gl._free_overlays_for_scene_change()
	assert_not_null(_gl._autogrind_ui,
		"a running grind owns the console — tearing it down here strands the controller")


## CONTROL: with nothing open the seam must be a no-op, not a crash.
func test_the_seam_is_safe_with_no_overlay_open() -> void:
	_gl._autogrind_ui = null
	_gl._autogrind_ui_layer = null
	_gl._autobattle_editor = null
	_gl._free_overlays_for_scene_change()
	assert_null(_gl._autogrind_ui, "no overlay, nothing to do, no error")


## The seam must be WIRED, and wired EARLY — after the reentrancy guards so a suppressed
## transition tears nothing down, but before the fade so the overlay does not linger on screen.
func test_the_teardown_is_called_at_the_transition_seam() -> void:
	var src := FileAccess.get_file_as_string(GL_SRC)
	var fn := src.find("func _on_area_transition")
	assert_gt(fn, -1, "the seam function exists")
	var body := src.substr(fn, src.find("\nfunc ", fn + 10) - fn)
	var call_at := body.find("_free_overlays_for_scene_change()")
	var guard_at := body.find("_transition_in_progress = true")
	var fade_at := body.find("match transition_type:")
	assert_gt(call_at, -1, "the seam must call the teardown — otherwise this is four patches again")
	assert_gt(guard_at, -1, "CONTROL: the reentrancy guard is in this function")
	assert_gt(fade_at, -1, "CONTROL: the fade dispatch is in this function")
	assert_lt(guard_at, call_at, "tear down AFTER the reentrancy guard, or a suppressed transition eats an overlay")
	assert_lt(call_at, fade_at, "and BEFORE the fade, or the overlay is visible over the transition")


## The editor gets the same rule — it is the overlay the first two patches were about.
func test_the_editor_is_torn_down_by_the_same_seam() -> void:
	var src := FileAccess.get_file_as_string(GL_SRC)
	var fn := src.find("func _free_overlays_for_scene_change")
	assert_gt(fn, -1, "the helper exists")
	var body := src.substr(fn, src.find("\nfunc ", fn + 10) - fn)
	assert_true(body.contains("_autobattle_editor"),
		"the editor must ride the same rule — it is what the 2026-08-17 and 08-23 patches were for")
	assert_true(body.contains("save_and_close"),
		"and both must SAVE, not free — an involuntary teardown must not discard player edits")
