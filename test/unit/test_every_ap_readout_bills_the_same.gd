extends GutTest

## Two AP readouts, two copies of the same subtraction, and both told the player the same lie.
##
## Full Bank refunds the fifth action. The Advance menu computed its preview as
## `current_ap - queued_count`, and the party panel — the readout a player watches for EVERY member,
## not just the acting one — had its own identical copy. Both reported a full-bank turn ending at -1
## when it ends at 0, and the plain-Label fallback branch had a third copy of it.
##
## Fixed by giving the question ONE authority: BattleManager.billed_ap(current_ap, queued). Every
## surface asks it rather than doing the arithmetic. That is the shape this codebase keeps rewarding
## — the tank/assassin utility filters, the summon field cap, the combo-element predicate — and the
## shape it keeps getting bitten by when three copies drift.
##
## ⚠️ The bug was NOT that the arithmetic was hard. It was that it was easy enough for each surface
## to write its own, and the Full Bank rule arrived after all three were written.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

func test_a_full_five_at_a_full_bank_bills_four() -> void:
	assert_eq(BattleManagerScript.billed_ap(4, 5), 4,
		"the fifth action is free — this is the number every readout must show")

func test_below_a_full_bank_everything_is_billed() -> void:
	## The discriminator. If the discount applied on AP alone, a two-action Advance at +4 would
	## preview as costing one and the economy would drift everywhere at once.
	assert_eq(BattleManagerScript.billed_ap(4, 2), 2, "a short queue at +4 is billed in full")
	assert_eq(BattleManagerScript.billed_ap(3, 5), 5, "and five actions below a full bank cost five")
	assert_eq(BattleManagerScript.billed_ap(0, 3), 3, "CONTROL: the ordinary case is unchanged")

func test_the_authority_agrees_with_the_engine() -> void:
	## The readout and the engine must not drift: five from +4 leaves 0, and billed_ap has to be the
	## number that produces it. If the refund ever changes, this reds before any UI does.
	var bm = BattleManagerScript.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mira"
	c.max_hp = 500; c.current_hp = 500
	c.current_ap = BattleManagerScript.FULL_BANK_AP
	var target := Combatant.new()
	autofree(target)
	target.combatant_name = "Dummy"
	target.max_hp = 999999; target.current_hp = 999999
	bm.player_party.append(c)
	bm.enemy_party.append(target)
	var actions: Array = []
	for i in BattleManagerScript.FULL_BANK_ACTIONS:
		actions.append({"type": "attack", "target": target})
	await bm._execute_advance(c, {"type": "advance", "combatant": c, "actions": actions, "full_bank": true})
	var predicted: int = BattleManagerScript.FULL_BANK_AP - BattleManagerScript.billed_ap(
		BattleManagerScript.FULL_BANK_AP, BattleManagerScript.FULL_BANK_ACTIONS)
	assert_eq(predicted, c.current_ap,
		"billed_ap predicts %d, the engine leaves %d — a readout is only honest if these agree" % [predicted, c.current_ap])

func test_no_surface_keeps_its_own_subtraction() -> void:
	## The anti-drift half, and the reason this file exists rather than two per-surface tests. A
	## fourth readout added later with its own arithmetic is the same bug again.
	var menu := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var panel := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_gt(menu.length(), 1000, "CONTROL: read Win98Menu")
	assert_gt(panel.length(), 1000, "CONTROL: read BattleUIManager")
	assert_string_contains(menu, "BattleManager.billed_ap(", "the menu must ask the authority")
	assert_string_contains(panel, "BattleManager.billed_ap(", "and so must the party panel")
	assert_false(panel.contains("ap_value - queued_count"),
		"the party panel must not keep its own subtraction — that copy is what told the lie")
	assert_false(menu.contains("_current_ap - queued_count"),
		"nor the menu")

func test_the_party_panel_marks_the_free_action() -> void:
	## A number that is quietly smaller reads as a bug. The panel shows a star when the turn is
	## being billed less than it queues, the same way the menu names it.
	var panel := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_string_contains(panel, "billed < queued_count",
		"the panel must know when the discount applied, not just apply it")
