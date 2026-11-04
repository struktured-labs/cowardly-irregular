extends GutTest

## struktured's .760 preview log: entering the item shop started a rebalance request (:3953), the scene change cancelled
## it (:3956 "[LLMService] cancel_all: scene_change"), and the daemon then logged "area_entered produced no proposal —
## the model's reply was not usable" (:3957), blaming a reply the model never sent. complete_json now reports THIS call's
## fallback reason through opts.report, and the daemon's outcome line names it.

const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")

var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


## Never answers, like a model still thinking when the player walks through a door.
class SilentModel extends LLMBackend:
	func backend_id() -> String: return "silent_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(_id: String, _p: String, _o: Dictionary = {}) -> void:
		pass


func before_each() -> void:
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_llm.llm_enabled = true
	_llm.cancel_all("dropped proposal fixture isolation")
	_be = SilentModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be


func after_each() -> void:
	_llm.cancel_all("dropped proposal fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled


func test_a_scene_change_is_named_as_the_cause() -> void:
	var d = DAEMON.new()
	d.pending.append({"trigger": "area_entered", "ts": 0, "context_summary": "map_id=shop_interior_item", "status": "pending"})
	var done := {"ok": null}
	var run := func() -> void: done["ok"] = await d.request_llm_proposal(0)
	run.call()
	for i in 3:
		await get_tree().process_frame
	_llm.cancel_all("scene_change")
	for i in 3:
		await get_tree().process_frame
	assert_eq(done["ok"], false, "FIXTURE: the cancelled request produced no proposal")
	var line: String = DAEMON.outcome_line("area_entered", str(d.pending[0].get("status", "")), d.pending[0])
	assert_string_contains(line, "cancelled", "THE DEFECT: a cancelled request was reported as the model's unusable reply")
	assert_false(line.contains("the model's reply was not usable"), "and the reply it never sent is not blamed")


func test_each_cause_has_its_own_words() -> void:
	assert_string_contains(DAEMON.fallback_cause("request failed or cancelled"), "cancelled")
	assert_string_contains(DAEMON.fallback_cause("no ready backend"), "no backend")
	assert_string_contains(DAEMON.fallback_cause("deltas not a list"), "list of changes")
	assert_eq(DAEMON.fallback_cause("guard rejected response"), "the model's reply was not usable",
		"a reply the guard rejected IS the model's reply not being usable")
	assert_eq(DAEMON.fallback_cause(""), "the model's reply was not usable", "an unknown cause keeps the old wording")
