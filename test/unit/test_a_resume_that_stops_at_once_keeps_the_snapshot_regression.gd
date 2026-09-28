extends GutTest

## A grind that ends on its own (HP stop) keeps its last every-5-battles snapshot, so the console offers Resume to a
## party that just stopped for low HP. _resume_autogrind called _start_autogrind, the HP check stopped the session
## inside that call, and the resume then restored the saved stats onto a stopped session and DELETED the snapshot.
## The paused session's battles, EXP and efficiency growth were gone for good.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _ag_state: Dictionary
var _bm_guard = BattleStateGuard.new()
var _saved_rules: Dictionary
var _prior_snapshot: Variant = null
var _gl: Node
var _ui: Control
var _resumes := 0


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_bm_guard.snapshot()
	if FileAccess.file_exists(AutogrindSystem.SNAPSHOT_PATH):
		_prior_snapshot = FileAccess.get_file_as_string(AutogrindSystem.SNAPSHOT_PATH)
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test reset")
	_saved_rules = AutogrindSystem.interrupt_rules.duplicate(true)
	AutogrindSystem.interrupt_rules["hp_threshold"] = 20.0
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	_write_snapshot()
	AutogrindSystem._test_disable_persistence = true
	_resumes = 0
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	_gl.current_state = _gl.LoopState.EXPLORATION
	var layer := CanvasLayer.new()
	_ui = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	layer.add_child(_ui)
	_gl.add_child(layer)
	_gl._autogrind_ui_layer = layer
	_gl._autogrind_ui = _ui


func after_each() -> void:
	InputLockManager.pop_all()
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindSystem.interrupt_rules = _saved_rules
	Engine.time_scale = 1.0
	if _prior_snapshot == null:
		if FileAccess.file_exists(AutogrindSystem.SNAPSHOT_PATH):
			DirAccess.remove_absolute(AutogrindSystem.SNAPSHOT_PATH)
	else:
		var f := FileAccess.open(AutogrindSystem.SNAPSHOT_PATH, FileAccess.WRITE)
		f.store_string(_prior_snapshot)
		f.close()
	_prior_snapshot = null
	AutogrindState.restore(_ag_state)
	_bm_guard.restore()
	SoundManager.stop_music()


## Writes a real snapshot through the production writer: a 10-battle session at 1.5x efficiency.
func _write_snapshot() -> void:
	AutogrindSystem._test_disable_persistence = false
	AutogrindSystem.is_grinding = true
	AutogrindSystem.battles_completed = 10
	AutogrindSystem.efficiency_multiplier = 1.5
	AutogrindSystem.save_grind_snapshot({"config": {"ludicrous_speed": true, "auto_advance": false}, "headless_mode": true})
	AutogrindSystem.is_grinding = false
	AutogrindSystem.battles_completed = 0
	AutogrindSystem.efficiency_multiplier = 1.0


func _wounded_party() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Hurt", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = 5
	var party: Array[Combatant] = [c]
	_gl.party = party
	_ui.setup(party, "Test Plains")
	_ui.grind_resume_requested.connect(func(): _resumes += 1)
	_ui.grind_resume_requested.connect(_gl._resume_autogrind)
	await wait_frames(2)


func test_the_fixture_writes_a_loadable_snapshot() -> void:
	assert_true(AutogrindSystem.is_snapshot_loadable(), "CONTROL: without a loadable snapshot there is nothing to lose")
	assert_eq(int(AutogrindSystem.load_grind_snapshot().get("system", {}).get("battles_completed", -1)), 10,
		"CONTROL: and it must carry the paused session's 10 battles")


func test_a_resume_that_stops_at_once_keeps_the_snapshot() -> void:
	await _wounded_party()
	_gl._resume_autogrind()
	await wait_frames(2)
	assert_false(_gl._is_autogrinding, "CONTROL: a 5%% party under a 20%% stop must not be grinding")
	assert_true(AutogrindSystem.is_snapshot_loadable(), "a resume that stopped before its first battle deleted the saved session")


func test_the_console_refuses_the_resume_and_says_why() -> void:
	await _wounded_party()
	assert_true(_ui._request_resume(), "CONTROL: with a loadable snapshot and no grind running, the press must be used")
	await wait_frames(2)
	assert_eq(_resumes, 0, "a resume that would stop at once must not reach GameLoop")
	assert_true(_ui.visible, "the console must stay on screen")
	assert_true(AutogrindSystem.is_snapshot_loadable(), "and the saved session must still be there")
	assert_string_contains(_ui._battle_log.get_parsed_text(), "Heal first", "the player must be told why, and what to do")


func test_a_healthy_party_still_resumes() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Fine", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	var party: Array[Combatant] = [c]
	_ui.setup(party, "Test Plains")
	_ui.grind_resume_requested.connect(func(): _resumes += 1)
	await wait_frames(2)
	assert_true(_ui._request_resume(), "CONTROL: the press must be used")
	assert_eq(_resumes, 1, "CONTROL: a healthy party must still resume, or the refusal arms prove nothing")
	assert_false(_ui.visible, "and the console hides for the resumed grind")
