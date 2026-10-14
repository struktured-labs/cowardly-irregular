extends GutTest

## The ENGINE refuses an ability when the caster is silenced — JobSystem.can_use_ability:770 — but the
## command menu computed row availability as `current_mp >= mp_cost` and named silence NOWHERE. So a
## silenced caster's spells read as available: the player confirmed one, heard menu_select, spent the
## turn, and only then read "X is silenced — Fire won't come out!" in the log.
##
## That is the exact waste struktured named when menu_error was added (Win98Menu:2084): "a wasted
## action because of insufficient resources - mp, ap, etc, should have a noise and/or text to
## indicate it". The mechanism already existed and was used for MP; silence did not use it.
## Precedent for the class is in the file: :611 records tick 374 routing the ENGINE and
## can_use_ability through the MP resolver and MISSING THE MENU. Same divergence, the other axis.

## acid_spray, not fire: both are magic and silence blocks EVERY ability, so the choice does not
## narrow the subject — but a single_enemy row reads _scene.test_enemies (:646) while an
## all_enemies row touches no scene, so this one is buildable from a bare BattleCommandMenu.
const ABILITY := "acid_spray"


func _foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": "Slime", "max_hp": 50, "max_mp": 0, "attack": 5, "defense": 0, "magic": 0, "speed": 5})
	add_child_autofree(e)
	return e


func _caster(mp: int, silenced: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Mage", "max_hp": 100, "max_mp": 999, "attack": 8, "defense": 0, "magic": 20, "speed": 10})
	add_child_autofree(c)
	c.learned_abilities.append(ABILITY)
	c.current_mp = mp
	if silenced:
		c.add_status("silence", 2)
	return c


func _row(c: Combatant) -> Dictionary:
	var foes: Array[Combatant] = [_foe()]
	return BattleCommandMenu.new(null)._build_ability_menu_item(ABILITY, c, foes, Transform2D.IDENTITY)


func _cost() -> int:
	return JobSystem.get_ability_mp_cost(_caster(999, false), ABILITY)


func test_a_silenced_casters_row_says_why_before_it_is_confirmed() -> void:
	var c := _caster(999, true)
	## PREMISE: the engine does refuse it. If this ever stops being true the scenario is not the real one.
	assert_false(JobSystem.can_use_ability(c, ABILITY), "CONTROL: the engine refuses a silenced cast")
	var row := _row(c)
	assert_false(row.is_empty(), "CONTROL: the row was built")
	assert_string_contains(str(row.get("reject_reason", "")), "Silenc",
		"the row must name silence BEFORE the turn is spent, not after it in the battle log")


func test_the_silenced_row_stays_landable_rather_than_vanishing() -> void:
	## Win98Menu:2087 is explicit: disabled rows are SKIPPED by the cursor, reject_reason rows stay
	## landable so the player can move onto one and hear why. A spell you can no longer cast must be
	## findable — removing it would hide the kit the silence is suppressing.
	var row := _row(_caster(999, true))
	assert_false(bool(row.get("disabled", false)),
		"silence marks the row with a reason; it must not skip the cursor past the player's own spell")


func test_an_unsilenced_caster_is_not_marked() -> void:
	## CONTROL. Without this the fix could read as "every row carries a reason".
	var row := _row(_caster(999, false))
	assert_eq(str(row.get("reject_reason", "")), "",
		"an ordinary affordable cast carries no refusal")


func test_the_mp_case_keeps_its_own_message() -> void:
	## The regression this fix could cause. _reject_selection gives a CUSTOM reject_reason priority
	## over "Not enough MP (N needed)" (Win98Menu:2095-2099), so setting one when MP is the cause
	## would replace the number the player needs with a generic line.
	var cost := _cost()
	assert_gt(cost, 0, "CONTROL: the ability costs MP, or this arm proves nothing")
	var row := _row(_caster(maxi(cost - 1, 0), false))
	assert_eq(str(row.get("reject_reason", "")), "",
		"affordability keeps its own path so the MP amount still reaches the player")
