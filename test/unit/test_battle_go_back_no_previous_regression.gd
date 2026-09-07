extends GutTest

## Regression test for two complementary go_back_to_previous_player() bugs
## that both live in the no-eligible-previous-player branch.
##
## --- Bug A: "stuck after B at first PC" (2026-06-04) ---
## Repro: pressing B during the lead PC's selection
##   1. BattleCommandMenu._on_win98_go_back_requested force-closes the menu
##   2. BattleManager.go_back_to_previous_player walks back, finds no
##      previous player (lead is first), and originally returned silently
##   3. Engine stays in PLAYER_SELECTING — no menu, no signal, no input
##      surface. Player can only escape by toggling autobattle.
## Fix: when no previous player exists, BattleManager must re-emit
## selection_turn_started so the menu re-opens at the current PC. The
## "back" becomes a no-op-with-feedback instead of a deadlock.
##
## --- Bug B: selection_index corruption when no previous player can act ---
## The backward-scan loop decrements selection_index (and `continue`s past
## non-players / AP-debt entries) WITHOUT restoring it. If no eligible
## previous player is found, selection_index is left wherever the loop
## stopped (often 0) while current_combatant is still the ORIGINAL combatant
## whose real position is at a higher index. When the PC commits, the round
## resumes from the wrong (earlier) position — re-processing combatants who
## already selected (double natural +1 AP, duplicate queued action).
## Fix: snapshot selection_index before the loop and restore it on the
## no-eligible-player path so it stays aligned with current_combatant.
##
## Common trigger for BOTH: pressing B as the 2nd PC when PC1 is the only
## earlier player and is in AP debt (the loop skips PC1 via `continue`).


const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


# Build a minimal Combatant standin (no JobSystem dependency) so the
# regression checks stay surgical and deterministic.
func _make_combatant(name: String, ap: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 50
	c.current_mp = 50
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 10
	c.is_alive = true
	c.current_ap = ap
	return c


func _new_battle_manager() -> Node:
	var bm = load(BATTLE_MANAGER_PATH).new()
	add_child_autofree(bm)
	return bm


# --- Bug A: source-pin (ported from commit d73b1a6) ------------------------

func test_go_back_no_previous_player_reemits_turn_signal() -> void:
	# Source pin: the no-previous-player branch of go_back_to_previous_player
	# must re-emit selection_turn_started so the closed command menu re-opens.
	var text = _read(BATTLE_MANAGER_PATH)
	var fn_idx = text.find("func go_back_to_previous_player")
	assert_gt(fn_idx, -1, "go_back_to_previous_player must exist")
	var fn_end = text.find("\nfunc ", fn_idx + 1)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx)
	var no_prev_idx = body.find("if not found_player:")
	assert_gt(no_prev_idx, -1, "no-previous-player branch must exist")
	var branch = body.substr(no_prev_idx)
	var ret_idx = branch.find("return")
	assert_gt(ret_idx, -1, "branch must have a return")
	var pre_return = branch.substr(0, ret_idx)
	assert_true(pre_return.find("selection_turn_started.emit") > -1,
		"no-previous-player branch must re-emit selection_turn_started before return so the menu re-opens. " +
		"Without this, force-closing the menu leaves the game in PLAYER_SELECTING with no input surface.")


# --- Bug B: source-pin for the selection_index restore ---------------------

func test_go_back_no_previous_player_restores_selection_index() -> void:
	# Source pin: the no-previous-player branch must restore selection_index
	# to its pre-loop snapshot so it stays aligned with current_combatant.
	var text = _read(BATTLE_MANAGER_PATH)
	var fn_idx = text.find("func go_back_to_previous_player")
	assert_gt(fn_idx, -1, "go_back_to_previous_player must exist")
	var fn_end = text.find("\nfunc ", fn_idx + 1)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx)
	# The snapshot must be taken before the backward-scan loop.
	var save_idx = body.find("saved_index")
	var loop_idx = body.find("while selection_index > 0")
	assert_gt(save_idx, -1, "must snapshot selection_index into saved_index")
	assert_gt(loop_idx, -1, "backward-scan loop must exist")
	assert_lt(save_idx, loop_idx,
		"saved_index snapshot must come BEFORE the backward-scan loop")
	# The restore must happen in the no-previous-player branch before return.
	var no_prev_idx = body.find("if not found_player:")
	var branch = body.substr(no_prev_idx)
	var ret_idx = branch.find("return")
	var pre_return = branch.substr(0, ret_idx)
	assert_true(pre_return.find("selection_index = saved_index") > -1,
		"no-previous-player branch must restore selection_index = saved_index before return " +
		"so the round resumes from the correct position (no double-AP / duplicate action).")


# --- Bug B: behavioral test ------------------------------------------------

func test_go_back_with_ap_debt_pc1_keeps_index_aligned_to_current() -> void:
	# Scenario: PC2 is selecting (selection_index points at PC2). PC1 is the
	# only earlier player and is in AP debt (can't act). Pressing B walks the
	# loop back to PC1, skips it via `continue` (AP debt), exhausts the loop
	# with found_player == false. The fix must leave selection_index pointing
	# at PC2 (the still-current combatant) — NOT at the earlier slot the loop
	# decremented to — so committing PC2's action advances to the correct
	# successor and does NOT re-process PC1/PC2.
	var bm = _new_battle_manager()
	var pc1 := _make_combatant("PC1", -1)   # AP debt — cannot act
	var pc2 := _make_combatant("PC2", 2)    # currently selecting
	add_child_autofree(pc1)
	add_child_autofree(pc2)

	# Build typed arrays explicitly — assigning an untyped Array literal to a
	# typed Array[Combatant]/Array[Dictionary] field can silently fail (the
	# project's canonical typed-array pitfall), so append element-by-element.
	var party: Array[Combatant] = []
	party.append(pc1)
	party.append(pc2)
	var order: Array[Combatant] = []
	order.append(pc1)
	order.append(pc2)
	var no_enemies: Array[Combatant] = []
	var no_pending: Array[Dictionary] = []

	bm.player_party = party
	bm.enemy_party = no_enemies
	bm.selection_order = order
	bm.selection_index = 1               # points AT pc2
	bm.current_combatant = pc2
	bm.current_state = bm.BattleState.PLAYER_SELECTING
	bm.pending_actions = no_pending

	var pc2_ap_before := pc2.current_ap

	# Capture the re-emit so we can assert it fired for the right combatant.
	var emitted := []
	bm.selection_turn_started.connect(func(c): emitted.append(c))

	bm.go_back_to_previous_player()

	# Index must stay aligned with the still-current original combatant (pc2
	# at slot 1), NOT decremented to pc1's slot 0.
	assert_eq(bm.selection_index, 1,
		"selection_index must stay aligned with current_combatant (pc2 @ slot 1), " +
		"not corrupted to the earlier slot the backward-scan loop decremented to")
	assert_eq(bm.current_combatant, pc2,
		"current_combatant must remain pc2 — no eligible previous player to go back to")
	# selection_order[selection_index] must resolve to current_combatant.
	assert_eq(bm.selection_order[bm.selection_index], bm.current_combatant,
		"selection_index must index current_combatant in selection_order")

	# pc2's AP must be net-unchanged: go_back spends 1 (revert natural gain)
	# then the failure path restores 1. No double-AP, no leak.
	assert_eq(pc2.current_ap, pc2_ap_before,
		"pc2 AP must be net-unchanged (spend 1 then restore 1 on the failure path)")

	# The menu must be re-opened for pc2 (re-emit), not left with no signal.
	assert_eq(emitted.size(), 1,
		"selection_turn_started must be re-emitted exactly once on the no-previous-player path")
	assert_eq(emitted[0], pc2,
		"the re-emitted turn must be for the still-current pc2 so its menu re-opens")
