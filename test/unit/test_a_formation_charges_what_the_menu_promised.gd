extends GutTest

## ⛔ THE AP A FORMATION SPECIAL *CHARGES* IS NOT THE AP THE MENU *CHECKED*, AND THE RATCHET THAT
## EXISTS FOR THIS CANNOT SEE IT. `test_formation_definitions_in_sync` compares
## `BattleCommandMenu.FORMATIONS` against `HeadlessBattleResolver.FORMATIONS` — ap_cost included —
## and is green. Neither table is what debits a live player. There are THREE copies of the number:
##
##   BattleCommandMenu   group_ap_shortfall("formation", row.ap_cost)              <- GATES the row
##   HeadlessBattleResolver   _execute_group_formation spends the row's own ap_cost   <- grind spends
##   BattleManager   `ap_cost = 3 if formation_id in [...]`                          <- LIVE spends
##
## `BattleManager` holds ZERO references to either FORMATIONS. So the ratchet pins the two that
## agree and is structurally blind to the third, which is the one that takes the AP — a test named
## for the defect passing, asking a different question.
##
## The three agree TODAY. The trigger is a SEVENTH formation or a rebalance, and both directions bite:
##   engine charges MORE than the gate checked -> spend_ap can hit the -4 floor and REFUSE, and its
##     bool return is discarded at _execute_formation_special's `p.spend_ap(ap_cost)`, so the special fires FOR FREE
##   engine charges LESS -> live and grind disagree on price, which the sync ratchet's own comment
##     says it exists to prevent ("never secretly cheaper/costlier")
##
## ⛔ AND AN ID WITH NO `match` ARM IS CHARGED TWICE: the `_:` fallback re-enters
## `_execute_physical_group(participants, alive_enemies, "all_out_attack", ap_cost)`, which spends
## again in ITS own `p.spend_ap(ap_cost)`. Measured below
## rather than read — it doubles as the control proving this instrument can say NO.
##
## Measured at the DEBIT, not in the source. `3 if … else 2` is one refactor away from any pattern;
## "what did the party actually pay" survives every rewrite of it.

const MENU := preload("res://src/battle/BattleCommandMenu.gd")

var _saved_party: Array
var _saved_enemies: Array


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	## chaos_theory rolls a jackpot tier AFTER the debit. Seeded anyway so a red is reproducible.
	seed(20260918)


func after_each() -> void:
	randomize()
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _member(name_str: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name_str
	c.max_hp = 500
	c.current_hp = 500
	c.attack = 40
	c.magic = 40
	c.defense = 0
	## 4 AP so no cost up to 3 — doubled to 6 by the fall-through — can be refused by the -4 floor.
	## A refusal would read as "charged less", which is the other defect's signature.
	c.current_ap = 4
	c.is_alive = true
	return c


func _dummy() -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Wall"
	e.max_hp = 100000000
	e.current_hp = 100000000
	e.defense = 0
	e.is_alive = true
	return e


## What one participant actually paid. Four members satisfies every table `min_members`.
## Called through a helper deliberately: if a later branch of the special aborts, the abort dies in
## ITS frame, and the debit — its first statement, `p.spend_ap(ap_cost)` — is already in the delta.
func _charged(formation_id: String) -> int:
	var roster: Array = []
	for i in range(4):
		roster.append(_member("PC%d" % i))
	var wall := _dummy()
	BattleManager.player_party.assign(roster as Array[Combatant])
	BattleManager.enemy_party.assign([wall] as Array[Combatant])
	var before: int = roster[0].current_ap
	BattleManager._execute_formation_special(roster, [wall] as Array[Combatant], formation_id)
	return before - roster[0].current_ap


func test_the_menu_table_quotes_more_than_one_price() -> void:
	## Without two distinct costs, "the engine agrees with the table" and "the engine always charges
	## 2" are the same green, and the arm below is a coincidence rather than a measurement.
	var costs: Dictionary = {}
	for f in MENU.FORMATIONS:
		costs[int(f.get("ap_cost", -1))] = true
	assert_gt(MENU.FORMATIONS.size(), 0,
		"CONTROL: BattleCommandMenu.FORMATIONS must be readable, or every arm here is vacuous")
	assert_gt(costs.keys().size(), 1,
		"the formations must not all cost the same, or this file cannot tell a table read from a "
		+ "hardcoded 2: %s" % str(costs.keys()))


func test_every_formation_charges_what_the_menu_gated_on() -> void:
	## Derived from the menu table so a SEVENTH formation is covered the day it is authored, which is
	## the only way this can break — the six present agree.
	var wrong: Array[String] = []
	for f in MENU.FORMATIONS:
		var fid: String = str(f.get("id", ""))
		var promised: int = int(f.get("ap_cost", -1))
		var paid: int = _charged(fid)
		if paid == promised:
			continue
		if paid == promised * 2:
			wrong.append("%s: paid %d for a quoted %d — DOUBLE, so it has no `match` arm in "
				% [fid, paid, promised]
				+ "_execute_formation_special and fell through to _execute_physical_group")
		else:
			wrong.append("%s: the menu gated the row on %d AP, live debited %d" % [fid, promised, paid])
	assert_eq(wrong, [],
		"BattleManager's `ap_cost = 3 if formation_id in [...]` computes formation AP from a hardcoded "
		+ "list and reads neither "
		+ "FORMATIONS table. It has drifted from the one the menu gates on: %s" % str(wrong))


func test_a_formation_id_with_no_arm_is_charged_twice() -> void:
	## The instrument watched saying NO — and the measurement behind this file's second claim.
	## An unknown id is charged once by _execute_formation_special and again by the fallback's
## _execute_physical_group.
	assert_eq(_charged("zz_not_a_formation"), 4,
		"the `_:` fallback must still double-charge, or the arm above can no longer tell a missing "
		+ "`match` arm from a price drift")

## ⛔ NO FLOOR ARM, AND THAT IS MEASURED RATHER THAN ASSUMED. This file reaches
## `_execute_formation_special` on ANOTHER object, which CLAUDE.md's call-shape table scores as
## runtime-resolved and therefore floor-worthy. It is not, because the DEFINITION has a self-caller:
## `_execute_group_action` calls it by bare name at :3779, so a rename gives
## `Parse Error: Function "_execute_formation_special()" not found in base self` and BattleManager.gd
## does not LOAD — the autoload is null for the whole run and every arm here dies with it.
## Measured: a floor declared FIRST still scored [Risky] and never printed its message, because the
## null happens before any arm. ✅ THE TABLE'S "instance method -> YES" ROW SPLITS ON WHERE THE CALL
## IS, NOT ON HOW THE TEST REACHES IT: a member called from inside its own script is parse-time
## checked, so it belongs in the row that needs no floor. A fully-updated rename leaves my own call
## dangling, `_charged` absorbs the abort and returns 0, and the arms above red with "live debited 0".
