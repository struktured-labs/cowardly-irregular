extends GutTest

## F2 quick-save and F3 quick-load said no only in a toast; every refusal is now heard as menu_error, the "can't do that" cue.
## The REAL handlers run on a bare GameLoop kept off the tree; the refusals tested return before any save is read or written.

const GL := preload("res://src/GameLoop.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const REFUSAL := "menu_error"
const HANDLERS := ["func _quick_save_with_toast(", "func _quick_load_with_toast("]

var _bm_guard = null


func before_each() -> void:
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	BattleManager.current_state = BattleManager.BattleState.INACTIVE
	_clear()


func after_each() -> void:
	if _bm_guard != null:
		_bm_guard.restore()
	_clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _clear() -> void:
	SoundManager._ui_player.stream = null
	SoundManager._sfx_cooldowns.erase(REFUSAL)


func _file() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(REFUSAL, {}) as Dictionary).get("file", ""))


func _heard() -> String:
	var s: AudioStream = SoundManager._ui_player.stream
	return s.resource_path.trim_prefix("res://") if s != null else ""


func _loop(state: int, in_transition: bool) -> Node:
	var gl: Node = autofree(GL.new())
	gl.current_state = state
	gl._transition_in_progress = in_transition
	return gl


func _body(fn: String) -> String:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i: int = src.find(fn)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, j - i) if j > -1 else src.substr(i)


func test_the_refusal_cue_is_authored() -> void:
	assert_ne(_file(), "", "CONTROL: menu_error is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + _file()), "CONTROL: menu_error's file is not on disk")


func test_quick_save_during_autogrind_is_heard() -> void:
	_loop(GL.LoopState.AUTOGRIND, false)._quick_save_with_toast()
	assert_eq(_heard(), _file(), "F2 refused during autogrind and was silent")


func test_quick_save_mid_transition_is_heard() -> void:
	_loop(GL.LoopState.EXPLORATION, true)._quick_save_with_toast()
	assert_eq(_heard(), _file(), "F2 refused mid-transition and was silent")


func test_quick_load_during_autogrind_is_heard() -> void:
	_loop(GL.LoopState.AUTOGRIND, false)._quick_load_with_toast()
	assert_eq(_heard(), _file(), "F3 refused during autogrind and was silent")


func test_quick_load_mid_transition_is_heard() -> void:
	_loop(GL.LoopState.EXPLORATION, true)._quick_load_with_toast()
	assert_eq(_heard(), _file(), "F3 refused mid-transition and was silent")


## Derived from the handlers' own source: ANY toast outside _refuse_quick reds (show_warning, show, show_save...), bar the one load success.
func test_no_quick_refusal_is_a_bare_toast() -> void:
	var allowed := {HANDLERS[0]: 0, HANDLERS[1]: 1}
	for fn in HANDLERS:
		var body := _body(fn)
		assert_ne(body, "", "CONTROL: %s is gone" % fn)
		assert_gt(body.count("_refuse_quick("), 3, "CONTROL: %s routes its refusals through _refuse_quick" % fn)
		assert_eq(body.count("Toast."), allowed[fn],
			"%s shows a toast without the refusal cue: route it through _refuse_quick" % fn)
	assert_eq(_body(HANDLERS[1]).count("Toast.show_success("), 1, "CONTROL: the one allowed toast is F3's success, and it is still there")
