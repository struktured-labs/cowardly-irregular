extends GutTest

## LLMService caches complete() replies for 5 minutes and clears that cache only on an AREA change
## (GameLoop._on_area_transition). A spotlight duel that is lost retries on the same map, and a duel loss writes no
## EventLog entry to vary the prompt, so the second identical gloat prompt was served the FIRST reply from the cache:
## the boss repeated its last words word for word. A gloat is one-shot narration; a cache hit can only be a repeat.
## The gloat now asks complete() for an uncached reply ({"cache": false}, the opt-out choose() already honoured).
## Fixture copied from test_a_model_gloat_is_not_wrapped_in_its_own_quotes, cache clear included.

const TEST_BOSS_ID := "test_gloat_boss_repeat"
const POOL := ["The Construct hums, untouched. 'Again.'"]

var _bm: Node
var _dlg: Node
var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _orig_turbo: bool = false


class CountingModel extends LLMBackend:
	var submitted: int = 0
	func backend_id() -> String: return "counting_model"
	func is_ready() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		var n: int = submitted
		get_tree().create_timer(0.05, true, false, true).timeout.connect(func(): request_finished.emit(id, true, "Reply number %d." % n, ""))


func before_each() -> void:
	_bm = get_tree().root.get_node("BattleManager")
	_dlg = get_tree().root.get_node("BossDialogue")
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_orig_turbo = _bm.turbo_mode
	_bm.turbo_mode = false
	_llm.llm_enabled = true
	_llm.cancel_all("repeat fixture isolation")
	_llm.clear_cache()
	_be = CountingModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be
	## ONE pool line, so the voice sample cannot vary the prompt: the two gloats below build the SAME prompt.
	_dlg._data[TEST_BOSS_ID] = {"display_name": "The Repeat Boss", "victory_lines": POOL.duplicate(), "defeat_lines": POOL.duplicate()}
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "The Repeat Boss"
	boss.max_hp = 300
	boss.current_hp = 0
	boss.is_alive = false
	boss.set_meta("is_boss", true)
	boss.set_meta("llm_persona_id", TEST_BOSS_ID)
	_bm.enemy_party.clear()
	_bm.enemy_party.append(boss)


func after_each() -> void:
	_bm.turbo_mode = _orig_turbo
	_bm.enemy_party.clear()
	_dlg._data.erase(TEST_BOSS_ID)
	_llm.cancel_all("repeat fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


func _gloat(victory: bool) -> String:
	var heard: Array = []
	var cb := func(text: String, _v: bool): heard.append(text)
	_bm.boss_gloat_line.connect(cb)
	_bm._dispatch_boss_gloat(victory)
	var t0 := Time.get_ticks_msec()
	while heard.is_empty() and Time.get_ticks_msec() - t0 < int(_bm.GLOAT_WAIT_SEC * 1000.0) + 500:
		await get_tree().process_frame
	_bm.boss_gloat_line.disconnect(cb)
	return str(heard[0]) if not heard.is_empty() else "<nothing emitted>"


func test_two_identical_duel_losses_get_two_fresh_gloats() -> void:
	## THE DEFECT: lose, retry on the same map, lose again. Same boss, same fight shape, same prompt.
	var first: String = await _gloat(false)
	var second: String = await _gloat(false)
	assert_eq(_be.submitted, 2, "the second gloat must ASK the model again, not be served from the cache")
	assert_ne(second, first, "the boss repeated its last words word for word: '%s'" % first)


func test_the_same_holds_for_a_win() -> void:
	var first: String = await _gloat(true)
	var second: String = await _gloat(true)
	assert_eq(_be.submitted, 2, "a second identical win must ask the model again too")
	assert_ne(second, first, "a win's concession repeated from the cache")


func test_control_complete_still_caches_by_default() -> void:
	## CONTROL: the opt-out is per call. Every other complete() caller keeps its cache, or this fix
	## silently doubled the model traffic of the whole lane.
	var a: Variant = await _llm.complete("the same prompt", "fb")
	var b: Variant = await _llm.complete("the same prompt", "fb")
	assert_eq(_be.submitted, 1, "a default complete() must still be served from the cache the second time")
	assert_eq(str(b), str(a), "and return the cached text")


func test_an_uncached_complete_asks_every_time() -> void:
	var a: Variant = await _llm.complete("the same prompt", "fb", {"cache": false})
	var b: Variant = await _llm.complete("the same prompt", "fb", {"cache": false})
	assert_eq(_be.submitted, 2, "cache: false must reach the model on every call")
	assert_ne(str(b), str(a), "and get each fresh reply")
