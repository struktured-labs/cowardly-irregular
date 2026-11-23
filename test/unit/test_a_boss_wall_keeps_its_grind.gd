extends GutTest

## His 2026-11-14 log: six straight wipes at the Cave Rat King. One answer cut encounter_rate 10%, taking away the grind he
## ruled is how that wall is beaten (no nerf), and wipes five and six logged nothing because a throttled trigger after the
## first was only counted (main 25931/25940).

const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")
const GL := preload("res://src/GameLoop.gd")

class PromptReplay extends "res://tools/replay_backend.gd":
	var last_prompt: String = ""
	func submit(id: String, prompt: String, opts: Dictionary = {}) -> void:
		last_prompt = prompt
		super.submit(id, prompt, opts)

const CUT := {"constant": "encounter_rate", "multiplier": 0.9, "reason": "fewer fights"}
const EXP := {"constant": "exp_multiplier", "multiplier": 1.05, "reason": "level faster"}

var _svc: Node
var _backend
var _orig_backends: Array = []
var _orig_active: Variant = null
var _orig_enabled: bool = false


func after_each() -> void:
	if _svc == null:
		return
	if _backend != null and is_instance_valid(_backend):
		_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
	_backend = null
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled
	_svc = null


func _wire(reply: Dictionary) -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: the LLMService autoload exists")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = PromptReplay.new()
	_backend.next_text = JSON.stringify(reply)
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


## One wipe considered and answered; returns [the proposal, the daemon's log lines].
func _wipe_answered(boss_fight: bool, deltas: Array) -> Array:
	_wire({"verdict": "nudge_easier", "confidence": 0.8, "deltas": deltas, "reason": "they keep dying"})
	var d = DAEMON.new()
	var lines: Array = []
	d.logged.connect(func(l): lines.append(l))
	assert_true(d.consider("party_wipe", {"map_id": "whispering_cave", "survivors": 0, "boss_fight": boss_fight}), "FIXTURE: the wipe is considered")
	assert_true(await d.request_llm_proposal(d.pending.size() - 1), "FIXTURE: the reply is accepted")
	return [d.pending[d.pending.size() - 1], lines]


func test_a_boss_wipe_never_cuts_encounters() -> void:
	var got: Array = await _wipe_answered(true, [CUT, EXP])
	var p: Dictionary = got[0]
	assert_eq(p["deltas"], [EXP], "the encounter cut is dropped and the exp nudge stays")
	assert_true((got[1] as Array).any(func(l): return str(l).contains("dropped an encounter_rate cut")), "and the log says so: %s" % str(got[1]))
	assert_true(_backend.last_prompt.contains("do NOT lower encounter_rate"), "the model is told before it answers")


func test_a_boss_wipe_whose_only_answer_was_the_cut_changes_nothing() -> void:
	var got: Array = await _wipe_answered(true, [CUT])
	assert_eq(got[0]["deltas"], [], "nothing left to apply")
	assert_eq(got[0]["verdict"], "no_change", "so it is not reported as a nudge")


func test_control_an_ordinary_wipe_may_still_cut_encounters() -> void:
	var got: Array = await _wipe_answered(false, [CUT])
	assert_eq(got[0]["deltas"], [CUT], "CONTROL: a field wipe keeps the cut")
	assert_false(_backend.last_prompt.contains("do NOT lower encounter_rate"), "CONTROL: and the prompt does not forbid it")


func test_control_a_boss_wipe_may_still_raise_encounters() -> void:
	var more := {"constant": "encounter_rate", "multiplier": 1.1, "reason": "more grind"}
	assert_eq(DAEMON.boss_safe_deltas([more], true), [more], "CONTROL: only a cut is dropped")


func test_every_wipe_in_a_streak_gets_a_line() -> void:
	var d = DAEMON.new()
	d.min_consideration_interval_sec = 999.0
	var lines: Array = []
	d.logged.connect(func(l): lines.append(l))
	for i in 6:
		d.consider("party_wipe", {"map_id": "whispering_cave", "survivors": 0})
	assert_eq(lines.size(), 6, "six wipes, six lines: %s" % str(lines))
	assert_eq(lines.filter(func(l): return str(l).contains("held party_wipe")).size(), 5, "each held one names itself")


func test_control_a_level_up_burst_is_still_counted_not_printed() -> void:
	var d = DAEMON.new()
	d.min_consideration_interval_sec = 999.0
	var lines: Array = []
	d.logged.connect(func(l): lines.append(l))
	for i in 5:
		d.consider("level_up", {})
	assert_eq(lines.size(), 2, "CONTROL: considered + the first throttle line only, as test_a_throttled_trigger_is_counted pins: %s" % str(lines))


func test_the_wipe_knows_it_was_a_boss_fight() -> void:
	assert_true(GL.wipe_was_a_boss_fight([], {"flag": "cave_rat_king_defeated"}), "a dungeon boss arms pending_boss_defeat")
	var duelist := Combatant.new()
	duelist.set_meta("is_miniboss", true)
	assert_true(GL.wipe_was_a_boss_fight([duelist], {}), "a duel miniboss carries is_miniboss")
	var slime := Combatant.new()
	assert_false(GL.wipe_was_a_boss_fight([slime], {}), "CONTROL: a field fight is not a boss wall")
	duelist.free()
	slime.free()


func test_the_wipe_context_carries_the_flag() -> void:
	var src: String = GdSource.code_of("res://src/GameLoop.gd")
	var at: int = src.find("var wipe_ctx: Dictionary = {")
	assert_gt(at, -1, "CONTROL: the wipe context is built in GameLoop")
	var block: String = src.substr(at, src.find("}", at) - at)
	assert_true(block.contains("\"boss_fight\":  wipe_was_a_boss_fight(BattleManager.enemy_party, _stashed_boss_defeat)"), "the wipe tells the daemon whether it was a boss")
