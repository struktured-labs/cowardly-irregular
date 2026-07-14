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
	# Flake fix 2026-07-02: drain stale in-flight/queued requests first —
	# see test_rule_composer_grammar_lint fixture note.
	svc.cancel_all("composer fixture isolation")
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
	if svc != null:
		svc.llm_enabled = _orig_enabled  # never free svc — leaving it heals later tests too

func test_llm_path_returns_valid_composition() -> void:
	var payload := {
		"name": "Fire-heavy strategy",
		"description": "Lead with fire on ice.",
		"rules_json": "[{\"conditions\":[{\"type\":\"enemy_hp_percent\",\"op\":\">\",\"value\":50},{\"type\":\"mp_percent\",\"op\":\">=\",\"value\":15}],\"actions\":[{\"type\":\"ability\",\"id\":\"fire\",\"target\":\"lowest_hp_enemy\"}],\"enabled\":true}]"
	}
	fake_backend.prime_next(JSON.stringify(payload))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "always open with fire", "vex", [])
	assert_eq(result.get("source", ""), "llm")
	assert_eq(result.get("name", ""), "Fire-heavy strategy")
	var rules: Array = result.get("rules", [])
	assert_eq(rules.size(), 1, "must parse the one rule")
	assert_eq(result.get("errors", []).size(), 0)
	assert_eq(result.get("domain", ""), rc.DOMAIN_AUTOBATTLE)
	assert_eq(result.get("character_id", ""), "vex")

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
