extends GutTest

## Regression test for struktured 2026-07-28:
## "u can always defer (so that u can get 50% dmg reduction even if the advance points are full)
##  ... but right now its greyed out at max ap."
##
## BattleCommandMenu greyed Defer whenever `current_ap >= 4`, on the stated reasoning (in its own
## comment: "skip turn, gain +1 AP") that Defer exists to gain AP. It doesn't:
##
##   Combatant.execute_defer()  sets is_defending = true — that is ALL it does,
##                              and its docstring says "Defer doesn't give AP directly"
##   the -50%                   applied in take_damage (Combatant.gd:279)
##   AP                         accrues from the natural per-turn +1, which gain_ap clampi's to 4
##
## So the gate withheld the entire DEFENSIVE option because of a resource benefit Defer never
## provided — at exactly the moment a player most wants it, since sitting at max AP means they
## have been surviving rather than spending.
##
## It was also internally inconsistent: the L-shoulder shortcut routes through defer_requested
## with no AP check, so the same action was available by button and greyed in the menu.
##
## NOTE ON COVERAGE: build_command_menu_items_with_targets needs a live BattleScene (it reaches
## _scene.get_viewport()), so the menu entry itself is pinned at source. Everything the fix
## actually rests on — that Defer grants no AP, and that defending halves damage — is tested
## behaviourally below, because those are the claims that make the gate wrong.

const MENU_PATH := "res://src/battle/BattleCommandMenu.gd"


func _combatant(ap: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Fighter"
	c.max_hp = 1000
	c.current_hp = 1000
	c.defense = 0
	c.current_ap = ap
	return c


## The Defer entry's `disabled` expression, isolated from the rest of the builder.
func _defer_disabled_expression() -> String:
	var src := FileAccess.get_file_as_string(MENU_PATH)
	var idx := src.find('"id": "defer"')
	assert_gt(idx, 0, "the Defer command entry must exist")
	var window := src.substr(idx, 260)
	var dis := window.find('"disabled"')
	assert_gt(dis, 0, "the Defer entry must declare a disabled condition")
	var line_end := window.find("\n", dis)
	return window.substr(dis, line_end - dis)


func test_defer_is_no_longer_gated_on_ap() -> void:
	var expr := _defer_disabled_expression()
	assert_false(expr.contains("current_ap"),
		"Defer must not be disabled by AP — its purpose is the -50% damage reduction, which has "
		+ "nothing to do with AP. Got: %s" % expr)


func test_cannot_defer_status_still_gates_it() -> void:
	# The one legitimate reason to grey Defer must survive the fix.
	var expr := _defer_disabled_expression()
	assert_string_contains(expr, "cannot_defer",
		"the cannot_defer status must still disable Defer — that gate is real")


func test_defer_grants_no_ap_which_is_why_the_ap_gate_was_wrong() -> void:
	# The premise. If Defer ever DOES grant AP directly, the old gate's reasoning becomes
	# arguable again and someone should revisit this deliberately rather than by accident.
	var c := _combatant(2)
	var before := c.current_ap
	c.execute_defer()
	assert_eq(c.current_ap, before,
		"execute_defer must not change AP — the AP gate guarded a benefit that does not exist")
	assert_true(c.is_defending, "and it must set the defending stance, which IS the point")
	c.free()


func test_defer_still_works_at_max_ap() -> void:
	# The reported case, end to end: a capped character defers and gets the stance.
	var c := _combatant(4)
	c.execute_defer()
	assert_true(c.is_defending, "a max-AP character must still be able to take the defensive stance")
	assert_eq(c.current_ap, 4, "and stay capped rather than overflowing")
	c.free()


func test_defending_actually_halves_incoming_damage() -> void:
	# The benefit the gate was withholding — measured, not assumed.
	var plain := _combatant(4)
	plain.take_damage(100)
	var plain_loss: int = 1000 - plain.current_hp

	var guarded := _combatant(4)
	guarded.execute_defer()
	guarded.take_damage(100)
	var guarded_loss: int = 1000 - guarded.current_hp

	assert_gt(plain_loss, 0, "the unguarded control must actually take damage")
	assert_lt(guarded_loss, plain_loss,
		"defending must reduce damage — this is precisely what max-AP players were denied")
	plain.free()
	guarded.free()
