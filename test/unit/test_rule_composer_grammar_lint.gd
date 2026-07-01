extends GutTest

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend: FakeBackendScript.FakeBackend
var _orig_backends: Array = []
var _orig_active = null

func before_each() -> void:
	rc = get_node_or_null("/root/RuleComposer")
	svc = get_node_or_null("/root/LLMService")
	fake_backend = FakeBackendScript.FakeBackend.new()
	fake_backend.name = "FakeBE"
	_orig_backends = svc._backends.duplicate()
	_orig_active = svc._active_backend
	svc.add_child(fake_backend)
	svc._backends.clear()
	svc._backends.append(fake_backend)
	fake_backend.request_finished.connect(svc._on_backend_finished)
	svc._active_backend = fake_backend

func after_each() -> void:
	if fake_backend and is_instance_valid(fake_backend):
		fake_backend.request_finished.disconnect(svc._on_backend_finished)
		svc._backends.clear()
		for b in _orig_backends:
			svc._backends.append(b)
		svc._active_backend = _orig_active
		svc.remove_child(fake_backend)
		fake_backend.free()

func test_unknown_condition_triggers_grammar_errors() -> void:
	watch_signals(rc)
	var payload := {
		"name": "Bad rule",
		"description": "Uses unknown condition.",
		"rules_json": "[{\"conditions\":[{\"type\":\"hp_zorp\",\"op\":\"<\",\"value\":30}],\"actions\":[{\"type\":\"attack\"}],\"enabled\":true}]"
	}
	fake_backend.prime_next(JSON.stringify(payload))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "mage", [])
	assert_eq(result.get("source", ""), "fallback",
			  "grammar-invalid emit must resolve to fallback source")
	assert_gt(result.get("errors", []).size(), 0,
			  "must populate errors list with grammar problems")
	assert_signal_emitted_with_parameters(rc, "composition_failed", [
		"grammar_errors", {"errors": result["errors"]}
	])
