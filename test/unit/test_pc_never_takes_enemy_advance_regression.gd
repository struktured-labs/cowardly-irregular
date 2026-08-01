extends GutTest

## Regression: struktured, live play 2026-07-31 — "cleric gave advance 3 actions when I cast
## protect". A player character routed into _process_ai_selection (BattleManager.gd:1503 sends
## one there when it is spotlight-locked OR player-trusted) fell through the enemy branch,
## because the early return only fires when AUTOBATTLE is enabled:
##
##     if is_player_controlled and AutobattleSystem.is_autobattle_enabled(char_id):
##         _process_grid_autobattle(combatant); return
##
## The enemy branch then ran `randf() < 0.15` -> `randi_range(2, 3)` actions, each hardcoded
## {"type": "attack"}. So 15% of a trusted character's turns queued 2-3 BASIC ATTACKS with no
## regard for their kit. Worst on a Cleric: ~41 damage a swing against MAG+270, three AP spent.
##
## Fixed by excluding player characters from that branch; they fall through to the
## ability-aware decision, which builds from the character's own job abilities.
##
## ⚠️ The advance branch is probabilistic (15%). A single call proves nothing, so this drives
## many turns and asserts the ADVANCE never appears for a PC — and a control asserts it DOES
## still appear for enemies, or the assertion would pass on an AI that simply never advances.

const TRIALS: int = 400


func _pc(name_str: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name_str
	c.is_alive = true
	c.max_hp = 1000
	c.current_hp = 1000
	c.current_ap = 3
	return c


func _queued_advances(for_player: bool) -> int:
	var saved_state = BattleManager.current_state
	var saved_pp = BattleManager.player_party.duplicate()
	var saved_ep = BattleManager.enemy_party.duplicate()
	var saved_pending = BattleManager.pending_actions.duplicate()

	var actor := _pc("Cleric" if for_player else "Goblin")
	var foe := _pc("Foe")
	# player_party/enemy_party are Array[Combatant]. Assigning a plain Array ABORTS the
	# enclosing function (CLAUDE.md's typed-array trap) — which silently zeroed both arms of
	# this test until the log named it.
	var pp: Array[Combatant] = []
	var ep: Array[Combatant] = []
	pp.append(actor if for_player else foe)
	ep.append(foe if for_player else actor)
	BattleManager.player_party = pp
	BattleManager.enemy_party = ep
	BattleManager.current_state = BattleManager.BattleState.ENEMY_SELECTING

	# _end_selection_turn cascades into _process_next_selection and drains the queue, but it
	# emits selection_turn_ended FIRST — snapshot there, while pending_actions is intact.
	var advances := [0]
	var probe := func(_c):
		for a in BattleManager.pending_actions:
			if str(a.get("type", "")) == "advance" and a.get("combatant") == actor:
				advances[0] += 1
	BattleManager.selection_turn_ended.connect(probe)

	for i in TRIALS:
		BattleManager.pending_actions = []
		# AP drains across calls and the branch needs >= 1; without this reset the whole
		# sweep goes unreachable after ~2 trials and BOTH arms read zero.
		actor.current_ap = 3
		foe.current_ap = 3
		actor.is_alive = true
		foe.is_alive = true
		BattleManager.current_combatant = actor
		BattleManager.current_state = BattleManager.BattleState.ENEMY_SELECTING
		BattleManager._process_ai_selection(actor)

	BattleManager.selection_turn_ended.disconnect(probe)
	BattleManager.pending_actions = saved_pending.duplicate()
	var rpp: Array[Combatant] = []
	var rep: Array[Combatant] = []
	for c in saved_pp: rpp.append(c)
	for c in saved_ep: rep.append(c)
	BattleManager.player_party = rpp
	BattleManager.enemy_party = rep
	BattleManager.current_state = saved_state
	return advances[0]


func test_control_enemies_still_advance() -> void:
	# CONTROL: at 15% over 400 trials, an enemy advancing zero times is ~1 in 10^28. If this
	# fails, the harness never reaches the branch and the PC assertion below is vacuous.
	assert_gt(_queued_advances(false), 0,
		"CONTROL: enemies must still take the advance branch — otherwise the PC check proves nothing")


func test_player_character_never_takes_the_enemy_advance() -> void:
	assert_eq(_queued_advances(true), 0,
		"a player character driven by AI must never queue the enemy advance — it hardcodes basic attacks, so a Cleric burns 3 AP on ~41-damage swings")
