extends GutTest

## struktured 2026-09-07, on .228: "cant exit autogrind again! got stuck after it stopped".
## His party was already under the 20% HP stop threshold, so start_grind stopped SYNCHRONOUSLY:
## grind_complete freed the controller and restored exploration INSIDE the start call, and
## _start_autogrind then went on to switch to the autogrind bed and deref the freed controller
## ("Invalid access to property or key 'headless_mode' on a base object of type 'Nil'",
## GameLoop:5342 — four times in his log). The abort skipped every line after it, and the
## console had been told "not grinding" while its own start path was still unwinding.

const GL_SRC := "res://src/GameLoop.gd"
const UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"

var _gl: Node = null
var _ui: Control = null


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test reset")
	_gl = load(GL_SRC).new()
	add_child_autofree(_gl)
	var explore := Node.new()
	explore.name = "FakeExploration"
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	var layer := CanvasLayer.new()
	_ui = load(UI_SRC).new()
	layer.add_child(_ui)
	add_child_autofree(layer)
	_gl._autogrind_ui_layer = layer
	_gl._autogrind_ui = _ui
	var c := Combatant.new()
	c.combatant_name = "Wounded"
	c.max_hp = 100
	c.current_hp = 5  # 5% — under the default 20% stop threshold before the first battle
	c.is_alive = true
	_gl.party = [c] as Array[Combatant]


func after_each() -> void:
	InputLockManager.pop_all()
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	Engine.time_scale = 1.0


func test_the_fixture_actually_stops_on_start() -> void:
	# ARM+: if the threshold did not fire, every assertion below would pass for the wrong reason.
	_gl._start_autogrind({})
	assert_false(_gl._is_autogrinding, "CONTROL: a 5%-HP party must stop the grind before its first battle")
	assert_true(_gl._autogrind_controller == null or not is_instance_valid(_gl._autogrind_controller),
		"CONTROL: grind_complete frees the controller")


func test_a_start_that_stops_immediately_leaves_exploration_intact() -> void:
	_gl._start_autogrind({})
	assert_eq(_gl.current_state, _gl.LoopState.EXPLORATION,
		"the state grind_complete restored must survive the rest of the start call")
	assert_ne(SoundManager._current_music, "autogrind",
		"the autogrind bed must NOT start over the area music once the session is already over")
	assert_false(_ui._is_grinding, "the console must know the grind is over")
	assert_true(_ui.visible, "and be back on screen so Cancel closes it")


func test_the_stop_summary_is_shown_once_and_its_lock_is_released_on_dismiss() -> void:
	_gl._start_autogrind({})
	assert_true(_gl._autogrind_summary != null and is_instance_valid(_gl._autogrind_summary),
		"the player must be told WHY it stopped (HP threshold) instead of a silent bounce")
	assert_true(InputLockManager.has_lock("autogrind_summary"), "the summary holds the input lock while up")
	_gl._autogrind_summary.dismissed.emit()
	assert_false(InputLockManager.has_lock("autogrind_summary"),
		"dismissing the summary must release the lock — a leaked lock is the input-dead state he hit")
