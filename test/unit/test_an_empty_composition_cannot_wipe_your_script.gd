extends GutTest

## `compose_async` returns SUCCESS for a reply carrying zero rules: `"[]"` parses, so
## parse_ok is true, the fallback check does not fire, the per-rule validation loop has
## nothing to reject, and the result comes back `source: "llm"` with an empty rule list.
##
## The thing standing between that and a wiped autobattle script is the overlay, which
## refuses twice — once before showing a preview, once at confirm. RuleComposer's own
## comment calls a zero-rule composition "the save-wiping one", and nothing pinned either
## refusal. The player's existing script is the only copy of work they typed by hand.
##
## Behavioural, and the CONTROL matters as much as the assert: the script has to be
## really installed first, or "unchanged" is satisfied by a character who never had one.
##
## MEASURED OVERLAP, stated so nobody reads a green as a passing mutation: the two
## refusals DEFEND EACH OTHER. Removing the `_last_composition.is_empty()` guard alone
## keeps every arm green, because an empty composition then yields an empty rule list
## and the second refusal catches it. Only removing BOTH reds — two arms, naming the
## script and the no-composition path. That is the same "two guards on one property
## defeat a single mutation" this repo records in _drop_unusable_rules, and the honest
## report of it is a double mutation rather than a claim that either arm pins either
## guard alone.

const OverlayScript := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")
const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")

const CHAR_ID := "hero"

var rc
var svc
var abs_sys
var fake_backend: FakeBackendScript.FakeBackend
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _orig_persist: bool = false


func before_each() -> void:
	var root := get_tree().root
	rc = root.get_node_or_null("RuleComposer")
	svc = root.get_node_or_null("LLMService")
	abs_sys = root.get_node_or_null("AutobattleSystem")
	assert_not_null(rc, "CONTROL: RuleComposer must be reachable")
	assert_not_null(abs_sys, "CONTROL: AutobattleSystem must be reachable")
	if "_test_disable_persistence" in abs_sys:
		_orig_persist = abs_sys._test_disable_persistence
		abs_sys._test_disable_persistence = true
	_orig_enabled = svc.llm_enabled
	svc.llm_enabled = true
	svc.cancel_all("empty-composition fixture isolation")
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
		svc.llm_enabled = _orig_enabled
	if abs_sys != null and "_test_disable_persistence" in abs_sys:
		abs_sys._test_disable_persistence = _orig_persist


func _hand_written_script() -> Dictionary:
	return {
		"character_id": CHAR_ID,
		"name": "What the player typed",
		"description": "Hand-authored, the only copy.",
		"rules": [{
			"conditions": [{"type": "hp_percent", "op": "<", "value": 40}],
			"actions": [{"type": "item", "id": "potion", "target": "self"}],
			"enabled": true,
		}],
	}


func _install_and_verify() -> void:
	abs_sys.set_character_script(CHAR_ID, _hand_written_script())
	var stored: Dictionary = abs_sys.get_character_script(CHAR_ID)
	assert_eq((stored.get("rules", []) as Array).size(), 1,
		"CONTROL: the hand-written script must really be installed, or 'unchanged' proves nothing")


func _compose_empty() -> Dictionary:
	fake_backend.prime_next(JSON.stringify({
		"name": "Empty", "description": "Zero rules.", "rules_json": "[]",
	}))
	return await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "do nothing at all", CHAR_ID, [])


# ── what the composer actually returns ────────────────────────────────────────

func test_a_zero_rule_reply_comes_back_as_a_success() -> void:
	## The premise. If this ever starts returning a fallback, the refusals below are
	## belt-and-braces rather than load-bearing — and this arm says so instead of the
	## guard quietly protecting nothing.
	var result: Dictionary = await _compose_empty()
	assert_eq(str(result.get("source", "")), "llm",
		"'[]' parses, so the composer reports success — this is why the caller must refuse it")
	assert_eq((result.get("rules", []) as Array).size(), 0, "with no rules in it")


# ── the protection ────────────────────────────────────────────────────────────

func test_confirm_does_not_replace_a_script_with_nothing() -> void:
	_install_and_verify()
	var overlay = OverlayScript.new()
	add_child_autofree(overlay)
	overlay._domain = overlay.RC_DOMAIN_AUTOBATTLE
	overlay._character_id = CHAR_ID
	overlay._last_composition = await _compose_empty()
	overlay.confirm(true)
	var after: Dictionary = abs_sys.get_character_script(CHAR_ID)
	assert_eq((after.get("rules", []) as Array).size(), 1,
		"an empty composition must never replace the player's rules")
	assert_eq(str(after.get("name", "")), "What the player typed",
		"and the script must still be theirs, not renamed by the empty one")


func test_a_composition_with_rules_still_installs() -> void:
	## The other direction, so the refusal cannot be "never install anything".
	_install_and_verify()
	fake_backend.prime_next(JSON.stringify({
		"name": "Replacement", "description": "Real rules.",
		"rules_json": "[{\"conditions\":[{\"type\":\"always\"}],\"actions\":[{\"type\":\"attack\"}],\"enabled\":true}]",
	}))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "just attack", CHAR_ID, [])
	assert_eq(str(result.get("source", "")), "llm", "CONTROL: this one must be a real composition")
	var overlay = OverlayScript.new()
	add_child_autofree(overlay)
	overlay._domain = overlay.RC_DOMAIN_AUTOBATTLE
	overlay._character_id = CHAR_ID
	overlay._last_composition = result
	overlay.confirm(true)
	var after: Dictionary = abs_sys.get_character_script(CHAR_ID)
	assert_eq(str(after.get("name", "")), "Replacement",
		"a composition WITH rules must still replace the script when the player confirms")


func test_confirm_before_any_composition_does_nothing() -> void:
	## The third way in: a confirm with nothing composed at all.
	_install_and_verify()
	var overlay = OverlayScript.new()
	add_child_autofree(overlay)
	overlay._domain = overlay.RC_DOMAIN_AUTOBATTLE
	overlay._character_id = CHAR_ID
	overlay.confirm(true)
	var after: Dictionary = abs_sys.get_character_script(CHAR_ID)
	assert_eq((after.get("rules", []) as Array).size(), 1,
		"confirming with no composition must leave the script alone")
