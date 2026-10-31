extends GutTest

## The formation special's TOTAL output used to be constant and then divided by the live enemy count,
## so one Four Heroes deleted a single target and was merely adequate against a pair. Measured
## 2026-10-26: 10,267 damage at level 10, which exceeded the full max_hp of 42 of the 50 monsters
## carrying an authored one_shot threshold — a system that pays up to x3.0 EXP and a unique trophy
## for killing everything in one execution phase. The reward for a committed build was free.
##
## Both levers had to move and neither works alone, which is why this file guards both:
##   exponent alone  -> trash L5 and Rat King L10 came back BIT-IDENTICAL at every value tested,
##                      while the W4 pair went 95% win -> 0% with 50-round stalemates
##   division alone  -> the pair fights collapsed to 2.00 rounds
## Together they are neutral on every anchor, because a single target has nothing to divide. That is
## the whole design: the cut lands on single-target burst and nowhere else.
##
## Nothing pinned either number before this file — the derived corpus for the change ran 792 guards
## and 4822 tests green, which means a balance-critical formula had no guard at all.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const RESOLVER_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"
const MANAGER_PATH := "res://src/battle/BattleManager.gd"
const MONSTERS := "res://data/monsters.json"
const THIS_FILE := "res://test/unit/test_a_group_attack_hits_each_enemy_for_its_own_share.gd"

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _fighter(att: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "PC"
	c.max_hp = 900
	c.current_hp = 900
	c.attack = att
	c.magic = att
	c.current_ap = 4
	c.is_alive = true
	return c


func _target(hp: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Foe"
	c.max_hp = hp
	c.current_hp = hp
	c.defense = 100
	c.is_alive = true
	return c


## Damage the FIRST enemy takes from one four_heroes against `count` identical enemies.
func _damage_to_first_of(count: int) -> int:
	var party: Array = [_fighter(400), _fighter(400), _fighter(400), _fighter(400)]
	var foes: Array[Combatant] = []
	for _i in range(count):
		foes.append(_target(400000))
	_bm._execute_formation_special(party, foes, "four_heroes")
	return int(foes[0].max_hp - foes[0].current_hp)


func test_the_floor_names_every_symbol_this_file_reaches() -> void:
	## DERIVED: every `_bm.<name>` here must exist, so a rename reds BY NAME rather than letting an
	## arm abort into a silent pass. These are lane-local reaches with one consumer apiece.
	var src: String = FileAccess.get_file_as_string(THIS_FILE)
	assert_gt(src.length(), 0, "the file must read its own source for the derivation to mean anything")
	var rx := RegEx.new()
	rx.compile("_bm\\.(\\w+)")
	var reached := {}
	for m in rx.search_all(src):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 1, "the derivation must find the real reach set (got %s)" % str(reached.keys()))
	var missing: Array = []
	for name in reached:
		if not ((name in _bm) or _bm.has_method(name) or _bm.has_signal(name)):
			missing.append(name)
	assert_eq(missing.size(), 0, "BattleManager no longer carries: " + str(missing))


func test_each_enemy_takes_its_own_share_not_a_divided_one() -> void:
	## ⛔ THE DEFECT ARM. Per-enemy damage must not depend on how many enemies are standing. Restore
	## the `/ alive_enemies.size()` division and the two-enemy case halves, which is exactly what made
	## a pair a cliff and a lone boss a deletion. Targets are given absurd HP so neither dies and the
	## comparison is of DAMAGE rather than of overkill.
	var solo: int = _damage_to_first_of(1)
	var pair: int = _damage_to_first_of(2)
	var trio: int = _damage_to_first_of(3)
	assert_gt(solo, 0, "CONTROL: the formation must deal damage at all, or every number here is 0")
	assert_eq(pair, solo,
		"a second enemy must not halve what the first one takes (solo %d, pair %d)" % [solo, pair])
	assert_eq(trio, solo,
		"nor must a third third it (solo %d, trio %d)" % [solo, trio])


func test_five_members_scale_linearly_not_to_eleven_times() -> void:
	## The magnitude lever, pinned as a RELATIONSHIP: n members scale to n, not to pow(n, 1.5).
	## At 1.5 a five-member strike was 11.18x one member while total_power already grew with the
	## party, so damage went as ~n^2.5.
	var one: Array = [_fighter(400)]
	var five: Array = [_fighter(400), _fighter(400), _fighter(400), _fighter(400), _fighter(400)]
	assert_almost_eq(_bm._group_scale(one), 1.0, 0.001, "a single member must scale to 1.0")
	assert_almost_eq(_bm._group_scale(five), 5.0, 0.001,
		"five members must scale to 5.0 — 11.18 is pow(5, 1.5) and is what made one button clear 42 of 50 one_shot thresholds")


func test_the_two_engines_scale_by_the_same_expression() -> void:
	## Live and headless formation damage being byte-identical is the only reason a harness number
	## transfers to the player. Twins by construction must agree, and nothing but this makes them.
	var live: String = FileAccess.get_file_as_string(MANAGER_PATH)
	var head: String = FileAccess.get_file_as_string(RESOLVER_PATH)
	var rx := RegEx.new()
	## GREEDY up to the LAST ", <number>)" on the line: the resolver nests parens inside maxi
	## (`maxi(1, _living(participants).size())`) where the live form does not, so a [^)]* inner
	## match finds the live one and returns null for the twin — which is how this arm first red.
	rx.compile("pow\\(.*,\\s*([0-9.]+)\\)")
	var lm := _first_code_match(rx, live)
	var hm := _first_code_match(rx, head)
	assert_not_null(lm, "BattleManager must still scale a group attack with pow(n, e)")
	assert_not_null(hm, "HeadlessBattleResolver must still scale a group attack with pow(n, e)")
	if lm == null or hm == null:
		return
	assert_eq(lm.get_string(1), hm.get_string(1),
		"the two engines' group-attack exponents must stay equal — the harness measures one and the player feels the other")
	## And neither may reintroduce the per-enemy division, which is the other half of the pair.
	assert_false(live.contains("/ max(1.0, float(alive_enemies.size()))"),
		"BattleManager must not divide group damage by the live enemy count again")
	assert_false(head.contains("/ max(1.0, float(alive_enemies.size()))"),
		"HeadlessBattleResolver must not divide group damage by the live enemy count again")


func test_every_one_shot_hint_states_the_damage_it_really_takes() -> void:
	## The bestiary shows one_shot.hp_threshold as the damage a player needs, and the engine's rule is
	## that every enemy dies in ONE execution phase — so the honest threshold is the monster's own
	## max_hp. 48 of 50 agreed; cave_rat_king said 2500 against 6500 HP, understating the TUTORIAL
	## boss by 2.6x, and rogue_lockward said 1740 against 1340. Derived, so a new monster is covered
	## the day it lands.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	var root: Dictionary = parsed if parsed is Dictionary else {}
	var inner: Variant = root.get("monsters", root)
	var mons: Dictionary = inner if inner is Dictionary else {}
	assert_gt(mons.size(), 90, "the monster roster must parse, or every arm below is vacuous")
	var checked := 0
	var liars: Array = []
	for id in mons:
		var row: Variant = mons[id]
		if not (row is Dictionary):
			continue
		var os_: Variant = (row as Dictionary).get("one_shot")
		var stats: Variant = (row as Dictionary).get("stats")
		if not (os_ is Dictionary) or not (stats is Dictionary):
			continue
		var want: Variant = (os_ as Dictionary).get("hp_threshold")
		var hp: Variant = (stats as Dictionary).get("max_hp")
		if want == null or hp == null:
			continue
		checked += 1
		if int(want) != int(hp):
			liars.append("%s: hint says %d, removing it takes %d" % [str(id), int(want), int(hp)])
	assert_gt(checked, 40, "CONTROL: the derivation must reach the real one_shot roster (got %d)" % checked)
	assert_eq(liars.size(), 0,
		"a one_shot hint must state the damage the kill really takes, or the bestiary lies to the player: " + str(liars))

## The first match on a line that is CODE. ⛔ Searching the whole file matched a COMMENT at
## BattleManager:4417 explaining the OLD pow(4,1.5)/pow(3,1.5) arithmetic, so this arm reported the
## live exponent as 1.5 while the code three lines further down said 1.0 — a guard reading prose as
## its subject, which is the failure this repo already documents.
func _first_code_match(rx: RegEx, src: String) -> RegExMatch:
	for raw in src.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			continue
		var m := rx.search(line)
		if m != null:
			return m
	return null
