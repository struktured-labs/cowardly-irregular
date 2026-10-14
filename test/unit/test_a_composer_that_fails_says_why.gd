extends GutTest

## A failed composition must say WHICH failure, and the one case the generic line describes
## correctly must keep it.
##
## Measured before the fix. `_fallback_result` returned `errors: []`, so RuleComposerOverlay's
## `if errors.size() > 0` branch was skipped and it fell through to its zero-rules branch:
##
##   model answered with prose, not rules   ->  "Error: No rules were composed."
##   model answered with an empty list      ->  "Error: No rules were composed."
##
## The first is wrong in the way that costs the player time: the natural reading is *my prompt
## was bad*, so they rephrase a prompt that was fine. `composition_failed` carries the kind
## (`invalid_json` vs `no_llm`) and has ZERO consumers in src/ — the overlay awaits the return
## value — so the distinguishing information already existed and reached nobody.
##
## The no-LLM case was NOT unhandled: `open()` already says so upfront, before the player types.
## What it said was "Settings → Configure BYOK" unconditionally, which is the wrong place to send
## someone whose Dynamic Dialogue toggle is simply off, and pressing Compose anyway REPLACED that
## good explanation with the generic line. Both now read from one derivation.
##
## Drives the real composer and the real overlay; the only stub is the backend, through
## tools/replay_backend.gd (fixture shape from test_a_replay_backend_drives_the_real_composer).

const ReplayBackend := preload("res://tools/replay_backend.gd")
const OverlayScene := preload("res://src/ui/autobattle/RuleComposerOverlay.tscn")
const GENERIC := "No rules were composed."

var _svc = null
var _rc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


class UnreadyBackend:
	extends LLMBackend
	func backend_id() -> String: return "unready"
	func is_ready() -> bool: return false
	func supports_json() -> bool: return false
	func submit(_id: String, _prompt: String, _opts: Dictionary = {}) -> void: pass
	func cancel(_id: String) -> void: pass
	func cancel_all() -> void: pass


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	assert_not_null(_rc, "CONTROL: RuleComposer autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend


func after_each() -> void:
	if _backend != null and is_instance_valid(_backend):
		if _backend.request_finished.is_connected(_svc._on_backend_finished):
			_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
	_backend = null
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


## Installs a backend that answers with exactly this text.
func _replay(text: String) -> void:
	_svc.llm_enabled = true
	_backend = ReplayBackend.new()
	_backend.name = "ReplayBE"
	_backend.next_text = text
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func _overlay() -> Control:
	var o: Control = OverlayScene.instantiate()
	add_child_autofree(o)
	o.open("autobattle", "fighter", [])
	return o


# ── the defect: a reply that could not be read blamed the player's prompt ─────

func test_an_unreadable_reply_does_not_read_as_a_bad_prompt() -> void:
	_replay("Sure! Here are some great autobattle rules for your fighter.")
	var res: Dictionary = await _rc.compose_async("autobattle", "attack when healthy", "fighter", [])
	assert_eq(str(res.get("source", "")), "fallback", "PREMISE: an unreadable reply is a fallback")
	var errs: Array = res.get("errors", [])
	assert_false(errs.is_empty(),
		"a reply that could not be read must say so, not fall through to the generic line")
	var joined: String = ", ".join(PackedStringArray(errs))
	assert_true(joined.find("could not be read") != -1,
		"and it must name the MODEL's answer as the problem, not the prompt: '%s'" % joined)


func test_the_player_reads_that_reason_on_the_overlay() -> void:
	_replay("Sure! Here are some great autobattle rules for your fighter.")
	var o: Control = _overlay()
	await o.compose("attack when healthy")
	var shown: String = o._status_label.text
	assert_true(shown.find("could not be read") != -1,
		"the overlay must show the reason it was given: '%s'" % shown)
	assert_eq(shown.find(GENERIC), -1,
		"and must NOT fall through to the generic line: '%s'" % shown)


# ── the case the generic line describes CORRECTLY keeps it ────────────────────

func test_a_model_that_answers_with_no_rules_still_reads_as_no_rules() -> void:
	_replay(JSON.stringify({"name": "Nothing", "description": "d", "rules_json": "[]"}))
	var o: Control = _overlay()
	await o.compose("do nothing at all")
	var shown: String = o._status_label.text
	assert_true(shown.find(GENERIC) != -1,
		"SCOPE: an empty-but-readable answer is exactly what the generic line says: '%s'" % shown)
	assert_eq(shown.find("could not be read"), -1,
		"and must not claim the answer was unreadable")


# ── over-reach: a GOOD composition carries no errors ─────────────────────────

func test_a_composition_that_worked_still_carries_no_reason() -> void:
	_replay(JSON.stringify({
		"name": "Open with fire", "description": "d",
		"rules_json": "[{\"conditions\":[{\"type\":\"always\"}],\"actions\":[{\"type\":\"attack\"}],\"enabled\":true}]",
	}))
	var res: Dictionary = await _rc.compose_async("autobattle", "just attack", "fighter", [])
	assert_eq(str(res.get("source", "")), "llm", "PREMISE: this one parsed")
	assert_eq(res.get("errors", []), [],
		"OVER-REACH: a reason belongs on a FAILURE; a working composition must carry none")


# ── the no-LLM reason names the right place, from one derivation ──────────────

func test_the_toggle_being_off_does_not_send_the_player_to_byok() -> void:
	_svc.llm_enabled = false
	assert_false(_rc.has_llm(), "PREMISE: the toggle off makes has_llm() false")
	var why: String = _rc.llm_unavailable_reason()
	assert_true(why.find("Dynamic Dialogue") != -1,
		"the toggle is the cause, so the toggle is what the reason must name: '%s'" % why)
	## Not "BYOK is absent" — it is the step AFTER the toggle, and naming it is right. What must
	## not happen is sending the player to BYOK FIRST when a toggle is what blocks them.
	assert_true(why.find("Dynamic Dialogue") < why.find("BYOK"),
		"the blocking cause must come before the server remedy: '%s'" % why)
	var o: Control = _overlay()
	assert_true(o._status_label.text.find("Dynamic Dialogue") != -1,
		"and open() must show that same reason: '%s'" % o._status_label.text)


func test_a_ready_toggle_with_no_reachable_backend_names_byok() -> void:
	_svc.llm_enabled = true
	_svc._backends.clear()
	_svc._backends.append(UnreadyBackend.new())
	_svc._active_backend = null
	assert_false(_rc.has_llm(), "PREMISE: enabled but nothing ready is still unavailable")
	var why: String = _rc.llm_unavailable_reason()
	assert_true(why.find("BYOK") != -1,
		"with the toggle ON the server is the cause, so name where to set one: '%s'" % why)
	assert_eq(why.find("Dynamic Dialogue"), -1,
		"and must not blame a toggle that is on: '%s'" % why)
	## The remedy a BYOK-only notice loses. Dropping it is what red
	## test_composer_no_backend_notice_regression when this fix first went out.
	assert_true(why.find("Ollama") != -1,
		"a local Ollama is the OTHER remedy and must still be named: '%s'" % why)


func test_pressing_compose_anyway_keeps_the_reason_it_was_given() -> void:
	_svc.llm_enabled = false
	var o: Control = _overlay()
	var upfront: String = o._status_label.text
	assert_true(upfront.find("Dynamic Dialogue") != -1, "PREMISE: open() explained it")
	await o.compose("heal when hurt")
	var after: String = o._status_label.text
	assert_eq(after.find(GENERIC), -1,
		"pressing Compose must not replace a real explanation with the generic line: '%s'" % after)
	assert_true(after.find("Dynamic Dialogue") != -1,
		"it must still name the same cause: '%s'" % after)


# ── the notice the player actually reads ─────────────────────────────────────
#
# The existing source pin (test_composer_no_backend_notice_regression) greps open()'s body for
# BYOK/Ollama. After this fix open() carries them only in its FALLBACK literal, so that pin
# would be satisfied even if the LIVE notice dropped a remedy. It stays as it is — its header
# says it deliberately avoids touching /root/LLMService — and this arm covers the live path,
# which is the one a player sees.

func test_the_notice_the_player_reads_names_both_remedies() -> void:
	_svc.llm_enabled = true
	_svc._backends.clear()
	_svc._backends.append(UnreadyBackend.new())
	_svc._active_backend = null
	assert_false(_rc.has_llm(), "PREMISE: nothing ready, so the notice fires")
	var o: Control = _overlay()
	var shown: String = o._status_label.text
	for needle in ["BYOK", "Ollama", "work fine without it"]:
		assert_true(shown.find(needle) != -1,
			"the notice a player reads must contain '%s': '%s'" % [needle, shown])


# ── floor: this file's dynamic reaches ───────────────────────────────────────

func test_the_surface_this_file_drives_still_exists() -> void:
	for m in ["compose_async", "has_llm", "llm_unavailable_reason"]:
		assert_true(_rc.has_method(m), "RuleComposer.%s is driven by this file" % m)
	var o: Control = _overlay()
	for m in ["open", "compose"]:
		assert_true(o.has_method(m), "RuleComposerOverlay.%s is driven by this file" % m)
	assert_not_null(o._status_label, "and its status label is what the player reads")
