extends GutTest

## BEHAVIORAL integration test — a landed boss jailbreak (skip_turn) must
## actually change the boss's turn when driven through the REAL BattleManager
## execution path, not merely apply a status the existing unit tests simulate
## by hand.
##
## Distinct from sibling tests:
##   - test_boss_dialogue_jailbreak.gd          → check_jailbreak matching only
##   - test_jailbreak_skip_turn_regression.gd   → status add/decrement SIMULATED
##                                                 by hand + a source-grep guard
## Neither drives a real boss turn. This file does: it queues a boss attack into
## BattleManager.execution_order and proves the boss does NOT damage the party
## that turn AFTER a jailbreak landed via the real signal chain — and DOES
## damage the party when no jailbreak landed (negative control).
##
## The whole jailbreak path is exercised with NO LLM present (scripted floor):
## BossDialogue keyword matching is deterministic and llm_available stays false.
##
## Drive mechanism: BossDialogue.try_apply_jailbreak() emits jailbreak_succeeded,
## which BattleManager._ready connected to _on_boss_jailbreak_succeeded; that
## handler finds the live boss in enemy_party (by llm_persona_id meta) and applies
## "cannot_act". We then hand-build a one-action execution_order and call the real
## BattleManager._execute_next_action(), whose cannot_act consumer (BattleManager
## ~:1649) skips the boss's queued attack.

const BOSS_ID: String = "chancellor_mordaine"
## Directive proven by data/boss_dialogue.json to trip appeal_old_loyalty →
## skip_turn (keyword "loyalty"). Verified inline in the first test below.
const LOYALTY_DIRECTIVE: String = "I appeal to your old loyalty."
const NEUTRAL_DIRECTIVE: String = "hello there nothing meaningful at all"

var _bm: Node = null
var _dlg: Node = null
var _gs: Node = null


func before_each() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	_dlg = Engine.get_main_loop().root.get_node_or_null("BossDialogue")
	_gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	# Turbo so the negative-case attack continuation uses process_frame, not a
	# wall-clock timer — keeps the test fast/deterministic. (We assert on HP
	# synchronously right after the call regardless.)
	if _bm:
		_bm.turbo_mode = true


func after_each() -> void:
	# Leave BattleManager in a clean INACTIVE state for sibling tests.
	if _bm and _bm.has_method("_cleanup_battle"):
		_bm.current_state = _bm.BattleState.INACTIVE
		_bm.enemy_party.clear()
		_bm.player_party.clear()
		_bm.all_combatants.clear()
		_bm.execution_order.clear()
		_bm.pending_actions.clear()


# ── Combatant builders (no JobSystem dependency — surgical) ──────────────────

func _make_boss() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Chancellor Mordaine"
	c.max_hp = 500
	c.current_hp = 500
	c.max_mp = 100
	c.current_mp = 100
	c.attack = 80          # high enough to deal obvious damage in negative case
	c.defense = 10
	c.magic = 10
	c.speed = 30           # faster, but irrelevant since we drive order directly
	c.is_alive = true
	# The handler matches the live boss by llm_persona_id (falls back to
	# monster_type). This is the real lookup key in _on_boss_jailbreak_succeeded.
	c.set_meta("llm_persona_id", BOSS_ID)
	return c


func _make_player() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Hero"
	c.max_hp = 400
	c.current_hp = 400
	c.max_mp = 30
	c.current_mp = 30
	c.attack = 20
	c.defense = 5          # low defense so any landed hit is clearly > 0
	c.magic = 10
	c.speed = 10
	c.is_alive = true
	return c


## Wire a minimal live battle WITHOUT going through start_battle's round
## machinery (which would invoke AI selection). We need only: enemy_party,
## player_party, all_combatants populated, plus the per-battle VolatilitySystem
## that _execute_attack reads. State left in PROCESSING_ACTION so the cannot_act
## / attack branches in _execute_next_action are reachable.
func _stage_battle(boss: Combatant, hero: Combatant) -> void:
	_bm.enemy_party.clear()
	_bm.player_party.clear()
	_bm.all_combatants.clear()
	_bm.enemy_party.append(boss)
	_bm.player_party.append(hero)
	_bm.all_combatants.append(hero)
	_bm.all_combatants.append(boss)
	_bm.volatility = VolatilitySystem.new()
	_bm.volatility.reset_battle()
	_bm.current_state = _bm.BattleState.PROCESSING_ACTION


## Build a single-action execution_order: the boss attacks the hero.
func _queue_boss_attack(boss: Combatant, hero: Combatant) -> void:
	_bm.execution_order.clear()
	_bm.execution_order.append({
		"type": "attack",
		"combatant": boss,
		"target": hero,
		"speed": 1.0,
	})


# ─────────────────────────────────────────────────────────────────────────────
# 0. Precondition: confirm the data path yields skip_turn for our directive.
# ─────────────────────────────────────────────────────────────────────────────

func test_precondition_loyalty_directive_yields_skip_turn() -> void:
	assert_not_null(_dlg, "BossDialogue autoload required")
	if _dlg == null:
		return
	var r: Variant = _dlg.check_jailbreak(BOSS_ID, LOYALTY_DIRECTIVE)
	assert_not_null(r, "'%s' must trip a vulnerability" % LOYALTY_DIRECTIVE)
	if r == null:
		return
	assert_eq(r["vulnerability_id"], "appeal_old_loyalty",
		"loyalty keyword maps to appeal_old_loyalty")
	assert_eq(r["consequence"]["type"], "skip_turn",
		"appeal_old_loyalty consequence is skip_turn — the behavior under test")


# ─────────────────────────────────────────────────────────────────────────────
# 1. POSITIVE: landed jailbreak → boss's queued attack is consumed, hero unhurt.
#    Driven entirely through the real signal chain + real _execute_next_action.
# ─────────────────────────────────────────────────────────────────────────────

func test_landed_jailbreak_skips_boss_turn_no_damage_to_party() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	assert_not_null(_dlg, "BossDialogue autoload required")
	if _bm == null or _dlg == null:
		return

	var boss := _make_boss()
	var hero := _make_player()
	add_child_autofree(boss)
	add_child_autofree(hero)
	_stage_battle(boss, hero)

	# Sanity: boss is NOT yet inhibited.
	assert_false(boss.has_status("cannot_act"),
		"boss should start the turn able to act")

	# Land the jailbreak via the REAL path: try_apply_jailbreak emits
	# jailbreak_succeeded → BattleManager._on_boss_jailbreak_succeeded applies
	# the consequence to the live boss. No LLM involved (scripted floor).
	var landed: bool = _dlg.try_apply_jailbreak(BOSS_ID, LOYALTY_DIRECTIVE)
	assert_true(landed, "try_apply_jailbreak should report a landed vulnerability")
	# Proof the consequence was applied through real code, not hand-set:
	assert_true(boss.has_status("cannot_act"),
		"BattleManager._on_boss_jailbreak_succeeded must apply cannot_act to the live boss")
	var dur_before: int = int(boss.status_durations.get("cannot_act", 0))
	assert_eq(dur_before, 1,
		"skip_turn params.duration in data/boss_dialogue.json is 1")

	var hp_before: int = hero.current_hp

	# Drive ONE boss turn through the REAL execution path.
	_queue_boss_attack(boss, hero)
	_bm._execute_next_action()

	# BEHAVIORAL assertion: the boss did NOT act this turn — hero took no damage.
	assert_eq(hero.current_hp, hp_before,
		"landed skip_turn jailbreak must consume the boss's attack — hero HP unchanged")
	# The boss's queued attack must have been pulled off the queue (consumed,
	# not left pending).
	assert_eq(_bm.execution_order.size(), 0,
		"the boss's single queued action must be consumed by the cannot_act skip")
	# Duration ticked down: 1 → removed (consumer removes when remaining <= 1).
	assert_false(boss.has_status("cannot_act"),
		"cannot_act with duration 1 must clear after being consumed by the skip")


# ─────────────────────────────────────────────────────────────────────────────
# 2. NEGATIVE control: a non-matching directive lands NOTHING — boss acts
#    normally and the hero takes damage. Proves the test would catch a
#    false-positive 'skip' (i.e. the skip is caused by the jailbreak, not by
#    some unrelated quirk of the harness).
# ─────────────────────────────────────────────────────────────────────────────

func test_non_matching_directive_boss_acts_and_deals_damage() -> void:
	if _bm == null or _dlg == null:
		return

	var boss := _make_boss()
	var hero := _make_player()
	add_child_autofree(boss)
	add_child_autofree(hero)
	_stage_battle(boss, hero)

	# No vulnerability should land for neutral text.
	var landed: bool = _dlg.try_apply_jailbreak(BOSS_ID, NEUTRAL_DIRECTIVE)
	assert_false(landed, "neutral directive must NOT land any vulnerability")
	assert_false(boss.has_status("cannot_act"),
		"no consequence applied — boss is free to act")

	var hp_before: int = hero.current_hp

	# Drive ONE boss turn. With no cannot_act, the boss reaches _execute_attack.
	# Attack has a miss chance, so retry a few stages to defeat RNG flakiness:
	# at attack 80 vs defense 5 the hit, when it lands, is unmistakably > 0.
	var dealt_damage := false
	for _i in range(12):
		if not hero.is_alive:
			break
		hero.current_hp = hero.max_hp  # reset between attempts so we isolate one hit
		var hp_attempt: int = hero.current_hp
		_queue_boss_attack(boss, hero)
		_bm._execute_next_action()
		if hero.current_hp < hp_attempt:
			dealt_damage = true
			break

	assert_true(dealt_damage,
		"with NO jailbreak landed the boss must be able to act and damage the hero " +
		"(this is the control that proves the positive test's 'skip' is real)")
	# Belt-and-suspenders: at no point did a phantom cannot_act appear.
	assert_false(boss.has_status("cannot_act"),
		"boss must never gain cannot_act from a non-matching directive")
	# hp_before captured the pre-loop HP; not asserted further (loop resets HP).
	assert_true(hp_before >= 0)


# ─────────────────────────────────────────────────────────────────────────────
# 3. GUARDRAIL: the entire applied jailbreak path must NOT mutate story_flags.
#    (Sibling test only covers check_jailbreak; this covers the APPLIED path
#     through BattleManager._on_boss_jailbreak_succeeded.)
# ─────────────────────────────────────────────────────────────────────────────

func test_applied_jailbreak_does_not_mutate_story_flags() -> void:
	if _bm == null or _dlg == null or _gs == null:
		return

	var boss := _make_boss()
	var hero := _make_player()
	add_child_autofree(boss)
	add_child_autofree(hero)
	_stage_battle(boss, hero)

	var before: Dictionary = (_gs.story_flags as Dictionary).duplicate(true)

	# Full applied path: land + drive the skipped turn.
	_dlg.try_apply_jailbreak(BOSS_ID, LOYALTY_DIRECTIVE)
	_queue_boss_attack(boss, hero)
	_bm._execute_next_action()

	var after: Dictionary = (_gs.story_flags as Dictionary).duplicate(true)
	assert_eq(after, before,
		"applying + resolving a boss jailbreak must never write canonical story_flags")
