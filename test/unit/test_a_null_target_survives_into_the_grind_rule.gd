extends GutTest

## `"target": null` is stripped for AUTOBATTLE and survives into AUTOGRIND.
##
## `_drop_null_targets` erases a null `target` key so the action falls back to its own
## default. Its header argues that is safe precisely because absence is a defined state:
##
##     "Absent is a documented, defined state for it — the action falls back to its own
##      default — so dropping the key changes nothing about what the rule DOES"
##
## That argument is domain-neutral, and so is the pass: it walks `rule["actions"]` and
## erases one key. Nothing in its body mentions autobattle. But compose_async calls it
## only inside `if domain == DOMAIN_AUTOBATTLE`, so a grind rule keeps the null.
##
## ⛔ AND A PRESENT-BUT-NULL KEY DEFEATS THE DEFAULT, WHICH IS THE WHOLE REASON THE PASS
## EXISTS. Measured in-engine: `{"target": null}.get("target", "")` returns `<null>`,
## not `""`, and `str()` of it is the four-character string "<null>".
##
## So `AutogrindSystem:2473` does `str(action.get("target", ""))` -> "<null>", and
## `_member_ability_apply` answers:
##
##     {"ok": false, "reason": "target '<null>' names no party member"}
##
## ⚠️ SEVERITY, STATED HONESTLY: this is NOT the OR bug. The composition is not lost,
## the validator does not reject it, and the refusal prints a clear reason. But the
## reason prints to the AUTOGRIND LOG, which is not a surface the player reads — so
## from the player's seat the rule they composed simply never fires, while the same
## rule composed for autobattle works.

const ReplayBackend := preload("res://tools/replay_backend.gd")

var _svc = null
var _rc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	if _svc == null or _rc == null:
		return
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = ReplayBackend.new()
	_backend.name = "ReplayNullTarget"
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func after_each() -> void:
	## NET. LLMService is an autoload; an arm that aborts would otherwise leave the
	## replay backend installed for every later FILE in the suite.
	if _backend and is_instance_valid(_backend):
		_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
		_backend = null
	if _svc:
		_svc._backends.clear()
		for b in _orig_backends:
			_svc._backends.append(b)
		_svc._active_backend = _orig_active
		_svc.llm_enabled = _orig_enabled


func _payload(rules_json: String) -> String:
	return JSON.stringify({"name": "n", "description": "d", "rules_json": rules_json})


## `always` is a NULLARY condition and `member_ability` needs member+ability, so the
## ONLY thing objectionable in this rule is the null target — and the validator does
## not object to it, which is why it reaches the runtime.
const GRIND_NULL_TARGET := '[{"conditions":[{"type":"always"}],"actions":[' \
	+ '{"type":"member_ability","member":"cleric","ability":"cure","target":null}' \
	+ '],"enabled":true}]'


func _targets_of(res: Dictionary) -> Array:
	var out: Array = []
	for r in (res.get("rules", []) as Array):
		for a in ((r as Dictionary).get("actions", []) as Array):
			out.append("ABSENT" if not (a as Dictionary).has("target") else (a as Dictionary)["target"])
	return out


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_drives_are_reachable() -> void:
	assert_not_null(_svc, "LLMService autoload missing — nothing below runs")
	assert_not_null(_rc, "RuleComposer autoload missing — nothing below runs")
	assert_true(_rc.has_method("_drop_null_targets"),
		"RuleComposer._drop_null_targets is gone — the pass this file is about")
	assert_true("DOMAIN_AUTOGRIND" in _rc and "DOMAIN_AUTOBATTLE" in _rc,
		"the domain constants this file switches on are gone")


func test_a_present_null_key_really_does_defeat_the_default() -> void:
	## PINS THE ASSUMPTION THE WHOLE PASS RESTS ON. If Dictionary.get ever returned the
	## default for a present-but-null key, `_drop_null_targets` would be unnecessary and
	## this file would be guarding nothing. Measured rather than assumed, because the
	## behaviour is the reason the defect is invisible at the call site.
	var a: Dictionary = {"target": null}
	assert_ne(str(a.get("target", "")), "",
		"a present null key now returns the default — _drop_null_targets is obsolete "
		+ "and every arm below is about a problem that no longer exists")
	assert_eq(str(a.get("target", "")), "<null>",
		"the null stringifies to something other than '<null>' — the reason text and "
		+ "the consumer's behaviour in this file's header need re-reading")


# ── control: the pass is sound and already does this for autobattle ───────────

func test_autobattle_strips_the_null_target() -> void:
	## CONTROL, and the reason the arms below accuse the CALL SITE and not the pass.
	## The identical shape, composed for autobattle, comes back with the key gone.
	if _backend == null:
		pending("replay backend unavailable")
		return
	_backend.next_text = _payload(
		'[{"conditions":[{"type":"hp_percent","operator":"<","value":30}],"actions":['
		+ '{"type":"attack","target":null}],"enabled":true}]')
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "attack", "hero", [])
	var t: Array = _targets_of(res)
	assert_true(t.has("ABSENT"),
		("autobattle no longer strips a null target — the pass itself is the defect and "
		+ "the grind arms below accuse the wrong place. targets=%s") % [t])


# ── the defect ────────────────────────────────────────────────────────────────

func test_the_grind_composition_does_not_keep_a_null_target() -> void:
	## THE DEFECT. The same key, the same pass, the other domain — and the pass is
	## never called, so the null rides through to the runtime as the string "<null>".
	if _backend == null:
		pending("replay backend unavailable")
		return
	_backend.next_text = _payload(GRIND_NULL_TARGET)
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOGRIND, "cleric cures the party", "", [])
	var t: Array = _targets_of(res)
	assert_true(t.has("ABSENT"),
		("a null target survived into a composed AUTOGRIND rule (targets=%s). "
		+ "AutogrindSystem reads str(action.get(\"target\", \"\")) — a present null "
		+ "defeats the default and yields \"<null>\", so _member_ability_apply refuses "
		+ "with \"target '<null>' names no party member\" and the rule never fires. "
		+ "_drop_null_targets already fixes this and is gated to autobattle.") % [t])


func test_the_grind_rule_still_composes_and_is_not_discarded() -> void:
	## Direction matters, and it bounds the severity claim. The null does NOT cost the
	## player the composition the way an unexpanded OR does — the set comes back. If
	## this ever starts failing, the defect has changed class and the header is stale.
	if _backend == null:
		pending("replay backend unavailable")
		return
	_backend.next_text = _payload(GRIND_NULL_TARGET)
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOGRIND, "cleric cures the party", "", [])
	assert_eq(str(res.get("source", "")), "llm",
		("the grind composition was discarded rather than merely carrying a bad target: %s. "
		+ "That is a different and worse defect than this file describes.")
			% [res.get("errors", [])])
