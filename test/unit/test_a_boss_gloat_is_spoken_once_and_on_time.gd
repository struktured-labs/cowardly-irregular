extends GutTest

## With the LLM on, the gloat waited for the model and emitted nothing until then; a slow backend (cloud BYOK, cold start) lost it when the results screen closed first.

const TEST_BOSS_ID := "test_gloat_boss_timing"
const LLM_LINE := "A line the model wrote."
const POOL := ["Scripted concession one.", "Scripted concession two."]

var _bm: Node
var _dlg: Node
var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _orig_turbo: bool = false
var _orig_time_scale: float = 1.0


## Answers every request with LLM_LINE after `delay_ms` of wall-clock time.
class SlowModel extends LLMBackend:
	var delay_ms: int = 0
	var submitted: int = 0
	func backend_id() -> String: return "slow_model"
	func is_ready() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		get_tree().create_timer(delay_ms / 1000.0, true, false, true).timeout.connect(func(): request_finished.emit(id, true, LLM_LINE, ""))


func before_each() -> void:
	_bm = get_tree().root.get_node("BattleManager")
	_dlg = get_tree().root.get_node("BossDialogue")
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_orig_turbo = _bm.turbo_mode
	_orig_time_scale = Engine.time_scale
	_llm.llm_enabled = true
	_llm.cancel_all("gloat timing fixture isolation")
	_be = SlowModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be
	_dlg._data[TEST_BOSS_ID] = {"display_name": "The Timing Boss", "victory_lines": POOL.duplicate(), "defeat_lines": POOL.duplicate()}
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "The Timing Boss"
	boss.max_hp = 300
	boss.current_hp = 0
	boss.is_alive = false
	boss.set_meta("is_boss", true)
	boss.set_meta("llm_persona_id", TEST_BOSS_ID)
	_bm.enemy_party.clear()
	_bm.enemy_party.append(boss)


func after_each() -> void:
	Engine.time_scale = _orig_time_scale
	_bm.turbo_mode = _orig_turbo
	_bm.enemy_party.clear()
	_dlg._data.erase(TEST_BOSS_ID)
	_llm.cancel_all("gloat timing fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


## Every gloat emitted within `watch_ms` of dispatch, as [text, ms_after_dispatch].
func _watch(victory: bool, watch_ms: int) -> Array:
	var heard: Array = []
	var t0 := Time.get_ticks_msec()
	var cb := func(text: String, _v: bool): heard.append([text, Time.get_ticks_msec() - t0])
	_bm.boss_gloat_line.connect(cb)
	_bm._dispatch_boss_gloat(victory)
	while Time.get_ticks_msec() - t0 < watch_ms:
		await get_tree().process_frame
	_bm.boss_gloat_line.disconnect(cb)
	return heard


func test_a_slow_model_still_gloats_on_time_and_only_once() -> void:
	## The default battle pace runs the engine at 0.25: a scaled timer would stretch the wait fourfold.
	Engine.time_scale = 0.25
	_be.delay_ms = 2500
	var budget_ms := int(_bm.GLOAT_WAIT_SEC * 1000.0)
	var heard: Array = await _watch(true, 3200)
	assert_eq(_be.submitted, 1, "VOID unless the model was actually asked")
	assert_eq(heard.size(), 1, "exactly one gloat, or the boss speaks twice: %s" % [heard])
	if heard.size() >= 1:
		assert_true(str(heard[0][0]) in POOL, "the model was too slow, so the scripted line speaks: %s" % heard[0][0])
		assert_true(int(heard[0][1]) <= budget_ms + 300, "spoken at %d ms against a %d ms budget" % [heard[0][1], budget_ms])


func test_a_fast_model_gloats_its_own_line_once() -> void:
	_be.delay_ms = 50
	var heard: Array = await _watch(true, int(_bm.GLOAT_WAIT_SEC * 1000.0) + 500)
	assert_eq(heard.size(), 1, "the deadline must not add a second, scripted gloat: %s" % [heard])
	if heard.size() >= 1:
		assert_eq(heard[0][0], LLM_LINE, "in time, the model's line is the one spoken")


func test_turbo_ships_the_scripted_line_now_and_asks_no_model() -> void:
	_bm.turbo_mode = true
	var heard: Array = []
	var cb := func(text: String, _v: bool): heard.append(text)
	_bm.boss_gloat_line.connect(cb)
	_bm._dispatch_boss_gloat(false)
	_bm.boss_gloat_line.disconnect(cb)
	assert_eq(heard.size(), 1, "turbo shows no results screen, so the line goes out synchronously")
	if heard.size() >= 1:
		assert_true(str(heard[0]) in POOL)
	assert_eq(_be.submitted, 0, "and no model call is spent on a line nobody will read")
