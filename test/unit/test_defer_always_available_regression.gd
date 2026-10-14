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
## NOTE ON COVERAGE: the two menu-entry arms were pinned at SOURCE, on the grounds that
## build_command_menu_items_with_targets needs a live BattleScene. It does, and a test can supply
## one, so they are behavioural now. The source form pinned the KEY NAME `"disabled"`, which
## certified a spelling rather than the gate: when the row became landable-with-a-reason (a
## disabled row is SKIPPED by the cursor, so the player could never reach the reason) the gate was
## intact and the extraction broke. Everything else here was always behavioural.

const MENU_PATH := "res://src/battle/BattleCommandMenu.gd"
const SCENE_PATH := "res://src/battle/BattleScene.gd"


func _combatant(ap: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Fighter"
	c.max_hp = 1000
	c.current_hp = 1000
	c.defense = 0
	c.current_ap = ap
	return c


## The real Defer row, built by the real builder. Mechanism-agnostic by construction: whether the
## gate is carried by `disabled` or by `reject_reason`, what matters is whether the row refuses.
func _defer_row(c: Combatant) -> Dictionary:
	var scene_script: GDScript = load(SCENE_PATH)
	var scene: Node = scene_script.new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var foe := Combatant.new()
	add_child_autofree(foe)
	foe.combatant_name = "Rat"
	foe.max_hp = 10
	foe.current_hp = 10
	foe.is_alive = true
	scene.test_enemies.assign([foe])
	var typed: Array[Combatant] = []
	typed.append(c)
	scene.party_members.assign(typed)
	BattleManager.player_party.assign(typed)
	var menu_script: GDScript = load(MENU_PATH)
	var menu = menu_script.new(scene)
	for r in menu.build_command_menu_items_with_targets(c):
		if r is Dictionary and str(r.get("id", "")) == "defer":
			return r
	return {}


## Refused either way a gate can be spelled.
func _refuses(row: Dictionary) -> bool:
	return bool(row.get("disabled", false)) or str(row.get("reject_reason", "")) != ""


func test_defer_is_no_longer_gated_on_ap() -> void:
	var c := _combatant(4)
	add_child_autofree(c)
	c.is_alive = true
	c.job = JobSystem.get_job("fighter")
	var row: Dictionary = await _defer_row(c)
	assert_false(row.is_empty(), "the Defer command entry must exist")
	assert_false(_refuses(row),
		("a max-AP character must still be offered Defer — its purpose is the -50%% damage reduction, "
		+ "which has nothing to do with AP. struktured 2026-07-28. Row: %s") % str(row))


func test_cannot_defer_status_still_gates_it() -> void:
	# The one legitimate reason to withhold Defer must survive, by whatever mechanism carries it.
	var c := _combatant(4)
	add_child_autofree(c)
	c.is_alive = true
	c.job = JobSystem.get_job("fighter")
	c.add_status("cannot_defer", 2)
	var row: Dictionary = await _defer_row(c)
	assert_false(row.is_empty(), "the Defer command entry must exist")
	assert_true(_refuses(row),
		"the cannot_defer status must still withhold Defer — that gate is real. Row: %s" % str(row))


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
