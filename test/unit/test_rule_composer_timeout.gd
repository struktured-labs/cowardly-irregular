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

func before_each() -> void:
	rc = get_node_or_null("/root/RuleComposer")
	svc = get_node_or_null("/root/LLMService")
	fake_backend = FakeBackendScript.FakeBackend.new()
	fake_backend.name = "FakeBE"
	svc._backends.clear()
	svc._backends.append(fake_backend)
	fake_backend.request_finished.connect(svc._on_backend_finished)
	svc._active_backend = fake_backend

func after_each() -> void:
	if fake_backend and is_instance_valid(fake_backend):
		fake_backend.queue_free()

func test_hang_triggers_client_timeout_fallback() -> void:
	watch_signals(rc)
	fake_backend.hang()   # never emit
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "mage", [])
	assert_eq(result.get("source", ""), "fallback",
			  "6s client timeout in LLMService must resolve to fallback content")
	assert_signal_emitted(rc, "composition_failed")
