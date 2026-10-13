extends GutTest

## When the LLM picks a boss posture but writes no taunt, the line the boss
## SPEAKS must belong to the posture it adopted.
##
## Reachable for a player who turned on Settings -> LLM Boss Strategy (opt-in,
## default OFF per test_boss_llm_strategy_flag_defaults_off) with a backend up.
##
## The defect this guards (measured 2026-10-13, before the fix): DialoguePrompts
## .validate_boss_intent deliberately accepts a payload that is just intent_id —
## test_boss_llm_strategy_regression's test_validate_accepts_missing_reason_and_taunt
## blesses it, because small models drop the taunt field under pressure (a line
## number would have been a pointer into a build). pick_intent_async then answered
## that empty taunt with `det_envelope.taunt_line`, a line from a SECOND,
## independent weighted roll over all nine of Mordaine's intents. So the boss
## announced a posture it was not adopting: `llm_intent` was set to the LLM's
## pick while the log carried some other intent's authored line. Measured 16 of
## 20 trials with taunt:"" speaking for another posture (aggress, fire_resist,
## defense_boost, rotate_aggro...), and the roll can also repeat the transition
## line the player just read (same intent twice: ~9% weighted, Mordaine phase 1).
##
## The fix never trades a wrong line for silence: BattleManager builds
## ctx.available_intents from the SAME scripted_intents array (min_phase
## filtered), and every intent of all five W1 bosses carries 2-3 taunt_lines, so
## every id the validator can accept has an authored line to speak. The ""
## return is data-defensive only — and the arm below pins that it is "" rather
## than an abort.
##
## Drives the SHIPPING path — the real LLMService.complete_json, the real
## _guard_json, the real validate_boss_intent — through tools/replay_backend.gd,
## so a change to any of them fails here rather than in prose.

const ReplayBackend := preload("res://tools/replay_backend.gd")
const BossIntentContextScript := preload("res://src/battle/BossIntentContext.gd")
const BOSS := "chancellor_mordaine"
const TRIALS := 20

var _svc = null
var _dlg = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _owner: Dictionary = {}


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	_dlg = get_tree().root.get_node_or_null("BossDialogue")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	assert_not_null(_dlg, "CONTROL: BossDialogue autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = ReplayBackend.new()
	_backend.name = "ReplayBE"
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend
	_owner = _taunt_owners()


func after_each() -> void:
	if _backend and is_instance_valid(_backend):
		_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


## Independent oracle: taunt string -> owning intent id, read from the JSON
## rather than from the subject, so the subject cannot define its own answer.
func _taunt_owners() -> Dictionary:
	var f := FileAccess.open("res://data/boss_dialogue.json", FileAccess.READ)
	assert_not_null(f, "CONTROL: boss_dialogue.json must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "CONTROL: boss_dialogue.json must parse")
	var out: Dictionary = {}
	for it in (parsed as Dictionary).get(BOSS, {}).get("scripted_intents", []):
		for t in it.get("taunt_lines", []):
			assert_false(out.has(str(t)),
				"CONTROL: the oracle needs unique taunt strings; '%s' is shared" % str(t))
			out[str(t)] = str(it.get("id", ""))
	assert_gt(out.size(), 0, "CONTROL: %s must have authored taunt lines" % BOSS)
	return out


func _ctx(allowed: Array) -> RefCounted:
	var ctx = BossIntentContextScript.new()
	ctx.boss_id = BOSS
	ctx.phase = 1
	ctx.available_intents = allowed
	return ctx


func _reply(intent_id: String, taunt: String) -> void:
	_backend.next_text = JSON.stringify({
		"intent_id": intent_id, "reason": "measured", "taunt": taunt,
	})


# ── premise: the replay reply really does reach the success branch ────────────

func test_a_written_taunt_is_the_line_the_boss_speaks() -> void:
	_reply("turtle", "You will tire before the stone does.")
	var got: Dictionary = await _dlg.pick_intent_async(_ctx(["turtle"]))
	assert_eq(str(got.get("intent_id", "")), "turtle",
		"PREMISE: a valid intent in available_intents must survive validation")
	assert_eq(str(got.get("taunt_line", "")), "You will tire before the stone does.",
		"PREMISE: the LLM's own taunt is what the boss speaks")
	assert_eq(str(got.get("reason", "")), "measured",
		"PREMISE: the replay reply reached the LLM success branch, not the fallback")


# ── the defect ───────────────────────────────────────────────────────────────

func test_an_unwritten_taunt_never_speaks_another_postures_line() -> void:
	var wrong: Array = []
	for _i in range(TRIALS):
		_reply("turtle", "")
		var got: Dictionary = await _dlg.pick_intent_async(_ctx(["turtle"]))
		assert_eq(str(got.get("intent_id", "")), "turtle",
			"the adopted posture must still be the LLM's pick")
		var line: String = str(got.get("taunt_line", ""))
		if line.is_empty():
			wrong.append("SILENT")
			continue
		var owner: String = str(_owner.get(line, "UNAUTHORED"))
		if owner != "turtle":
			wrong.append(owner)
	assert_eq(wrong.size(), 0,
		"a taunt under intent 'turtle' must be turtle's own authored line; %d of %d trials went wrong: %s" % [wrong.size(), TRIALS, str(wrong)])


func test_a_whitespace_taunt_counts_as_unwritten() -> void:
	for _i in range(5):
		_reply("focus_healer", "   ")
		var got: Dictionary = await _dlg.pick_intent_async(_ctx(["focus_healer"]))
		var line: String = str(got.get("taunt_line", ""))
		assert_false(line.is_empty(),
			"focus_healer has three authored lines; silence means the lookup found none")
		assert_eq(str(_owner.get(line, "UNAUTHORED")), "focus_healer",
			"a whitespace-only taunt is unwritten; the authored line must match the posture")


# ── over-reach control: the authored lookup must not displace a written line ──

func test_the_authored_line_never_overrides_what_the_llm_wrote() -> void:
	_reply("aggress", "Kneel, or be knelt.")
	var got: Dictionary = await _dlg.pick_intent_async(_ctx(["aggress"]))
	assert_eq(str(got.get("taunt_line", "")), "Kneel, or be knelt.",
		"OVER-REACH: a written taunt outranks the authored pool")
	assert_false(_owner.has(str(got.get("taunt_line", ""))),
		"OVER-REACH: the spoken line is the LLM's, not one of the authored nine")


# ── the lookup answers "" instead of aborting on a non-boss key ──────────────
#
# boss_dialogue.json's root holds `_comment` beside the boss ids and has_entry
# is a bare _data.has(), so a prose key passes it. pick_intent's typed
# `var entry: Dictionary = _data[boss_id]` ABORTS on that; the new lookup must
# not add a second site, because an abort here would return "" to a caller that
# reads "" as "this intent has no authored line" and say nothing, for the wrong
# reason. Unreachable from play — boss ids come from monster personas — so this
# pins the shape, not a live path.

func test_the_lookup_is_silent_on_a_key_that_is_not_a_boss() -> void:
	assert_eq(_dlg.taunt_for_intent("_comment", "aggress"), "",
		"a prose key at the data root must answer empty, not abort")
	assert_eq(_dlg.taunt_for_intent("no_such_boss_xyz", "aggress"), "",
		"an unknown boss must answer empty")
	assert_eq(_dlg.taunt_for_intent(BOSS, ""), "",
		"an empty intent id must answer empty")
	assert_eq(_dlg.taunt_for_intent(BOSS, "no_such_intent_xyz"), "",
		"an intent the boss does not own must answer empty")
	var line: String = _dlg.taunt_for_intent(BOSS, "turtle")
	assert_eq(str(_owner.get(line, "UNAUTHORED")), "turtle",
		"CONTROL: the same lookup DOES answer for a real intent — '%s'" % line)


# ── floor: only what THIS file reaches, per receiver ─────────────────────────
#
# One name, and the exclusions are MEASURED rather than argued — the call SHAPE
# decides, per CLAUDE.md's reach table. `taunt_for_intent` is called directly by
# the arm above AND self-called inside pick_intent_async, so renaming it is a
# PARSE error: the autoload fails to instantiate and all six arms red on the
# before_each CONTROL. Impossible to miss, so a floor over it is dead weight.
# `pick_intent` / `has_entry` / `complete_json` are reached only through the
# subject. What is left is the one DYNAMIC reach, below.
#
# The floor is load-bearing for the four names below, MEASURED rather than
# assumed: renaming pick_intent_async reds this arm ALONE — `Failing 1`, and
# the three arms whose first statement is that very call go SILENTLY GREEN.
# Each aborts with before_each's asserts already on the tally, which is
# CLAUDE.md's arm-B shape: one prior assert is the whole difference between
# EC=4 and a clean pass. Without this arm a rename is invisible here.

func test_the_surface_this_file_reaches_still_exists() -> void:
	assert_true(_dlg.has_method("pick_intent_async"),
		"BossDialogue.pick_intent_async is this file's one dynamic reach; nothing in the engine self-calls it, so only this arm names its rename")
	assert_true(_svc.has_method("_on_backend_finished"),
		"LLMService._on_backend_finished is how the replay backend answers")
	assert_true("_backends" in _svc and "_active_backend" in _svc,
		"the replay fixture swaps LLMService._backends / _active_backend")
	assert_true("llm_enabled" in _svc,
		"the fixture forces LLMService.llm_enabled on")
