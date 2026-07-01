extends GutTest

## Live-path tests for RuleComposer.compose_async against a FakeBackend.
##
## FakeBackend is the nested class inside test_llm_fake_backend.gd (that
## file itself extends GutTest — the class is NOT top-level), so it must be
## accessed as FakeBackendScript.FakeBackend, matching the pattern already
## established in test_llm_service_live_path.gd.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend: FakeBackendScript.FakeBackend
var _orig_backends: Array = []
var _orig_active = null

func before_each() -> void:
	rc = get_node_or_null("/root/RuleComposer")
	svc = get_node_or_null("/root/LLMService")
	assert_not_null(rc)
	assert_not_null(svc)
	fake_backend = FakeBackendScript.FakeBackend.new()
	fake_backend.name = "FakeBE"
	_orig_backends = svc._backends.duplicate()
	_orig_active = svc._active_backend
	svc.add_child(fake_backend)
	# Array[LLMBackend] is strictly typed — clear+append avoids a SCRIPT ERROR.
	svc._backends.clear()
	svc._backends.append(fake_backend)
	# _build_backends() only wires request_finished at _ready(); redo it here.
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

func test_llm_path_returns_valid_composition() -> void:
	var payload := {
		"name": "Fire-heavy strategy",
		"description": "Lead with fire on ice.",
		"rules_json": "[{\"conditions\":[{\"type\":\"enemy_hp_percent\",\"op\":\">\",\"value\":50}],\"actions\":[{\"type\":\"ability\",\"id\":\"fire\",\"target\":\"lowest_hp_enemy\"}],\"enabled\":true}]"
	}
	fake_backend.prime_next(JSON.stringify(payload))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "always open with fire", "mage", [])
	assert_eq(result.get("source", ""), "llm")
	assert_eq(result.get("name", ""), "Fire-heavy strategy")
	var rules: Array = result.get("rules", [])
	assert_eq(rules.size(), 1, "must parse the one rule")
	assert_eq(result.get("errors", []).size(), 0)
	assert_eq(result.get("domain", ""), rc.DOMAIN_AUTOBATTLE)
	assert_eq(result.get("character_id", ""), "mage")

func test_autogrind_domain_disallows_character_id() -> void:
	fake_backend.prime_next("{}")
	# In the autogrind domain character_id must be empty
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOGRIND, "heal when hurt", "cleric", [])
	assert_ne(result.get("source", ""), "llm",
			  "autogrind domain with a character_id must NOT proceed to LLM")
	assert_gt(result.get("errors", []).size(), 0)

func test_autobattle_requires_character_id() -> void:
	fake_backend.prime_next("{}")
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "heal on low HP", "", [])
	assert_ne(result.get("source", ""), "llm",
			  "autobattle domain without character_id must NOT proceed to LLM")
	assert_gt(result.get("errors", []).size(), 0)

func test_llm_ready_signal_fires() -> void:
	watch_signals(rc)
	fake_backend.prime_next(JSON.stringify({
		"name": "Ok",
		"description": "Ok.",
		"rules_json": "[]"
	}))
	var _r = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "mage", [])
	assert_signal_emitted(rc, "composition_ready")
