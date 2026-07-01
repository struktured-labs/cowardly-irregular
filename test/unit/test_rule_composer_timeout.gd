extends GutTest

## Timeout test for RuleComposer.compose_async: a hung FakeBackend must
## resolve via LLMService's 6s CLIENT_TIMEOUT_SEC guard, not hang forever.
##
## See test_rule_composer_live_path.gd for why FakeBackend is accessed via
## FakeBackendScript.FakeBackend (nested class) rather than a bare preload.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend: FakeBackendScript.FakeBackend
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true

func before_each() -> void:
	var root := get_tree().root
	rc = root.get_node_or_null("RuleComposer")
	if rc == null:  # survives a freed autoload from an earlier contaminating test
		rc = preload("res://src/llm/RuleComposer.gd").new()
		rc.name = "RuleComposer"
		root.add_child(rc)
	svc = root.get_node_or_null("LLMService")
	if svc == null:  # compose_async() looks this up by absolute path
		svc = preload("res://src/llm/LLMService.gd").new()
		svc.name = "LLMService"
		root.add_child(svc)
	assert_not_null(rc)
	assert_not_null(svc)
	_orig_enabled = svc.llm_enabled
	svc.llm_enabled = true
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
	if svc != null:
		svc.llm_enabled = _orig_enabled  # never free svc — leaving it heals later tests too

func test_hang_triggers_client_timeout_fallback() -> void:
	watch_signals(rc)
	fake_backend.hang()   # never emit
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "mage", [])
	assert_eq(result.get("source", ""), "fallback",
			  "6s client timeout in LLMService must resolve to fallback content")
	assert_signal_emitted(rc, "composition_failed")
