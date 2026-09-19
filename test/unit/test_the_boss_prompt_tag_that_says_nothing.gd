extends GutTest

## The boss-intent prompt's per-action tag is a CONSTANT, and the value that would
## fill it is logged one field away and thrown out.
##
## DialoguePrompts.build_boss_intent renders each recent action as
##
##     "  - [%s] %s used %s%s%s" % [kind, actor, ability, tgt_tag, dmg_tag]
##
## The `[%s]` slot is the only discriminator on the line. BattleManager's
## _build_boss_intent_context fills it with the literal "party_action" for every
## entry, so a five-action exchange reaches the model as
##
##     - [party_action] hero used fire -> lowest_hp
##     - [party_action] hero used potion -> ally
##
## Every tag identical: the slot carries zero bits and costs tokens on each line.
##
## ⛔ AND THE DISCRIMINATOR EXISTS. _log_player_action records
## `"action_type": action.get("type", "attack")` — attack / ability / item / defer /
## advance — in the same dict the context loop reads. The loop reads `ability_id`
## and `target_type` out of it and steps over `action_type`.
##
## Why no existing guard caught it: the sibling test's fixture WRITES
## {"kind": "party_action", ...} by hand and asserts the push cap. A fixture that
## echoes the producer's constant cannot notice the constant.

const MORDAINE_ID := "chancellor_mordaine"

var _bm: Node = null
var _llm_svc: Node = null
var _llm_saved_enabled: bool = true
var _saved_party: Array = []
var _saved_enemies: Array = []


func before_each() -> void:
	_llm_svc = get_node_or_null("/root/LLMService")
	if _llm_svc and "llm_enabled" in _llm_svc:
		_llm_saved_enabled = _llm_svc.llm_enabled
		_llm_svc.llm_enabled = false
	_bm = get_node_or_null("/root/BattleManager")
	if _bm:
		_saved_party = _bm.player_party.duplicate()
		_saved_enemies = _bm.enemy_party.duplicate()


func after_each() -> void:
	## The BattleManager is an AUTOLOAD — every arm below mutates its parties and its
	## action log. Restoring here rather than at the end of an arm, because an arm that
	## aborts would otherwise leak a fixture party into every later file in the suite.
	if _bm:
		_bm.player_party.assign(_saved_party)
		_bm.enemy_party.assign(_saved_enemies)
		if "_battle_action_log" in _bm:
			_bm._battle_action_log.clear()
	if _llm_svc and "llm_enabled" in _llm_svc:
		_llm_svc.llm_enabled = _llm_saved_enabled


func _mk(nm: String, hp: int = 100) -> Combatant:
	var c: Combatant = Combatant.new()
	c.combatant_name = nm
	c.max_hp = 100
	c.current_hp = hp
	c.max_mp = 30
	c.current_mp = 20
	c.is_alive = hp > 0
	add_child_autofree(c)
	return c


## Stands up a one-member party and one enemy, then logs two actions of DIFFERENT
## types through the real logger. Returns the boss so an arm can build a context.
func _drive_two_kinds() -> Combatant:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	var hero: Combatant = _mk("Hero", 80)
	_bm.player_party.append(hero)
	var boss: Combatant = _mk("Chancellor Mordaine", 40)
	_bm.enemy_party.append(boss)
	_bm._battle_action_log.clear()
	_bm._log_player_action(hero, {"type": "ability", "ability_id": "fire", "target": boss})
	_bm._log_player_action(hero, {"type": "item", "ability_id": "potion", "target": hero})
	return boss


# ── floor: the symbols this file reaches, and the value it claims is available ──

func test_the_producer_and_the_logger_are_both_reachable() -> void:
	## FILE-LEVEL FLOOR. Every arm below drives these three names on BattleManager;
	## a rename makes the arms abort mid-frame and score green on an earlier assert.
	assert_not_null(_bm, "BattleManager autoload unavailable — nothing below runs")
	for sym in ["_build_boss_intent_context", "_log_player_action"]:
		assert_true(_bm.has_method(sym),
			"BattleManager.%s is gone — the arms below abort silently without this floor" % sym)
	assert_true("_battle_action_log" in _bm,
		"BattleManager._battle_action_log is gone — the context loop this file is about reads it")


func test_the_logger_really_records_the_action_type() -> void:
	## THE WHOLE CLAIM RESTS ON THIS: the discriminator is present in the log.
	## If _log_player_action ever stops recording action_type, the defect below
	## becomes "there is nothing to propagate" and this file should be re-read.
	_drive_two_kinds()
	var log_rows: Array = _bm._battle_action_log
	assert_eq(log_rows.size(), 2, "both actions must reach the log for this file to be about anything")
	var kinds: Array = []
	for row in log_rows:
		kinds.append(str((row as Dictionary).get("action_type", "")))
	assert_eq(kinds, ["ability", "item"],
		("_battle_action_log must carry the action's own type, got %s — this is the value "
		+ "the boss-intent context drops on the floor") % [kinds])


# ── the defect ────────────────────────────────────────────────────────────────

func test_two_different_actions_do_not_reach_the_boss_as_the_same_tag() -> void:
	## THE DEFECT. Two actions of genuinely different types must not arrive at the
	## prompt wearing an identical tag — the `[%s]` slot exists to tell them apart.
	var boss: Combatant = _drive_two_kinds()
	var boss_dlg: Node = get_node_or_null("/root/BossDialogue")
	if boss_dlg == null:
		pending("BossDialogue autoload unavailable")
		return
	var ctx = _bm._build_boss_intent_context(boss, MORDAINE_ID, 3, boss_dlg)
	assert_not_null(ctx, "_build_boss_intent_context returned null")
	assert_eq(ctx.recent_actions.size(), 2, "both logged actions must reach the context")
	var tags: Array = []
	for entry in ctx.recent_actions:
		tags.append(str((entry as Dictionary).get("kind", "")))
	assert_ne(tags[0], tags[1],
		("an ability and an item reached the boss prompt under the SAME tag %s. The [%%s] slot "
		+ "in build_boss_intent's recent line is the only discriminator it has, and the "
		+ "action's real type is sitting unread in _battle_action_log's action_type") % [tags])


func test_the_tag_is_the_action_type_the_logger_recorded() -> void:
	## Direction matters: distinct is not enough, the tag must be the RIGHT value.
	## A producer that emitted a counter would satisfy the arm above and still tell
	## the model nothing about what the party is doing.
	var boss: Combatant = _drive_two_kinds()
	var boss_dlg: Node = get_node_or_null("/root/BossDialogue")
	if boss_dlg == null:
		pending("BossDialogue autoload unavailable")
		return
	var ctx = _bm._build_boss_intent_context(boss, MORDAINE_ID, 3, boss_dlg)
	var tags: Array = []
	for entry in ctx.recent_actions:
		tags.append(str((entry as Dictionary).get("kind", "")))
	assert_eq(tags, ["ability", "item"],
		("the boss prompt's per-action tag must be the action's own type, got %s") % [tags])


func test_the_rendered_prompt_tells_the_two_actions_apart() -> void:
	## THE CONSEQUENCE, at the surface the model actually reads. The arms above are
	## about the context dict; this one is about the string the boss is handed.
	var boss: Combatant = _drive_two_kinds()
	var boss_dlg: Node = get_node_or_null("/root/BossDialogue")
	if boss_dlg == null:
		pending("BossDialogue autoload unavailable")
		return
	var ctx = _bm._build_boss_intent_context(boss, MORDAINE_ID, 3, boss_dlg)
	var DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")
	var prompt: String = DialoguePrompts.build_boss_intent("Chancellor Mordaine", ctx.to_dict())
	## DERIVED from the prompt, never matched against a guessed actor name. The first
	## version of this arm spelled the actor "Hero" and the producer lowercases it to
	## "hero", so it passed while the two arms above were failing — a green from a
	## fixture typo, in the arm named for the consequence.
	var tags: Array = []
	for line in prompt.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("- [") and t.contains("]"):
			tags.append(t.substr(3, t.find("]") - 3))
	assert_gt(tags.size(), 1, "the prompt must carry both recent lines, got tags %s" % [tags])
	var distinct: Array = []
	for t in tags:
		if not distinct.has(t):
			distinct.append(t)
	assert_gt(distinct.size(), 1,
		("every recent line in the boss prompt carries the SAME tag %s — a cast and a "
		+ "consumable are indistinguishable to the model, and the slot costs tokens per "
		+ "line while conveying nothing:\n%s") % [distinct, prompt])


# ── control: the renderer is NOT the defect ───────────────────────────────────

func test_the_renderer_discriminates_when_it_is_given_distinct_kinds() -> void:
	## CONTROL, and the reason the arms above accuse the PRODUCER. Handed distinct
	## kinds directly, build_boss_intent renders them distinctly — so the constant
	## arrives from _build_boss_intent_context and no prompt change can fix it.
	##
	## Without this arm a reader could reasonably "fix" DialoguePrompts instead.
	var DialoguePrompts := preload("res://src/llm/DialoguePrompts.gd")
	var ctx_dict: Dictionary = {
		"boss_id": MORDAINE_ID,
		"phase": 1,
		"available_intents": ["aggress"],
		"recent_actions": [
			{"kind": "ability", "actor": "Hero", "ability_id": "fire", "target": "lowest_hp"},
			{"kind": "item", "actor": "Hero", "ability_id": "potion", "target": "ally"},
		],
	}
	var prompt: String = DialoguePrompts.build_boss_intent("Chancellor Mordaine", ctx_dict)
	assert_true(prompt.contains("[ability]") and prompt.contains("[item]"),
		("build_boss_intent does not render the kind it is given — the renderer, not the "
		+ "producer, would then be the defect and every arm above accuses the wrong file:\n%s")
			% prompt)
