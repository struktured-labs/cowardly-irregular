extends GutTest

## `drain_mp` restores the CASTER's MP per damaging hit (BattleManager:5085). The resolver read it
## nowhere, so two POOLED monsters that advertise an MP siphon got nothing in the grind:
##
##   data_drain    20 MP  magic              data_wraith (POOLED) · corrupted_guardian
##   memory_drain  15 MP  magic, all_enemies the_absence (POOLED)
##
## Live refills them per damaging hit, so they keep casting. In the grind they ran dry and stopped —
## so the grind's version of those fights was WEAKER than the game's, which is what the HP threshold
## and the battle cap are calibrated against. Same direction as the drain and secondary-effect gaps.
##
## ⛔ MAGIC ARM ONLY, and checked rather than assumed. Live reads drain_mp only in
## _execute_magic_ability and both owners are type=magic, so the paths agree. I wired two earlier keys
## into BOTH damage arms when live reads each on ONE, and the grind ended up harsher than the game for
## `temporal_strike` and healed `bone_warden` where the game heals nothing — so the executor check now
## comes before the fix, not after. The ledger's axis 2 pins this one the same way.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


## HP and MP set AFTER add_child — entering the tree restores both, so a pre-add assignment is
## silently discarded and every arm measures a full caster.
func _combatant(name: String, hp: int = 500, mp: int = 400) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": mp,
		"attack": 20, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = mp
	return c


func test_a_siphon_refills_the_caster_it_costs() -> void:
	var ab: Dictionary = _authored("data_drain")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var siphon: int = int(ab.get("drain_mp", 0))
	var cost: int = int(ab.get("mp_cost", 0))
	assert_gt(siphon, 0, "CONTROL: data_drain must still author a drain_mp")
	var wraith := _combatant("Data Wraith")
	var hero := _combatant("Hero", 99999)
	_res._player_party = [hero]
	_res._enemy_party = [wraith]
	## Half MP, so restore_mp has room — a full caster absorbs nothing and the arm would pass on no siphon.
	wraith.current_mp = int(wraith.max_mp / 2)
	var before: int = wraith.current_mp
	_res._resolve_ability(wraith, "data_drain", [hero])
	var net: int = wraith.current_mp - before
	gut.p("    data_drain: cost=%d siphon=%d net MP %+d" % [cost, siphon, net])
	assert_eq(net, siphon - cost,
		"the caster paid %d and siphoned %d, so it should net %+d — got %+d" % [cost, siphon, siphon - cost, net])


func test_an_all_enemies_siphon_stacks_across_the_party() -> void:
	## memory_drain is all_enemies and live applies the restore PER TARGET, so it scales with how many
	## it hit. A once-per-cast implementation passes the arm above and fails here.
	var ab: Dictionary = _authored("memory_drain")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var siphon: int = int(ab.get("drain_mp", 0))
	var cost: int = int(ab.get("mp_cost", 0))
	var absence := _combatant("The Absence")
	var party: Array = [_combatant("A", 99999), _combatant("B", 99999), _combatant("C", 99999)]
	_res._player_party = party
	_res._enemy_party = [absence]
	absence.current_mp = int(absence.max_mp / 2)
	var before: int = absence.current_mp
	_res._resolve_ability(absence, "memory_drain", party)
	var net: int = absence.current_mp - before
	gut.p("    memory_drain on %d targets: cost=%d siphon=%d each, net %+d" % [party.size(), cost, siphon, net])
	assert_eq(net, siphon * party.size() - cost,
		"a %d-target siphon must restore %d x %d and pay %d once — net %+d, got %+d" % [
			party.size(), siphon, party.size(), cost, siphon * party.size() - cost, net])


## ⚠️ THIS ARM DOES NOT TEST THE GATE ITS FIRST DRAFT CLAIMED TO, and the mutation said so: removing
## `damage_dealt <= 0` from _siphon_mp left it GREEN. The magic arm checks `target.is_alive` BEFORE
## reaching the siphon, so a corpse never gets there — and on a LIVING target the damage is floored at
## 1, so `damage_dealt <= 0` is unreachable. The inner gate mirrors BattleManager:5086 for readability,
## exactly as the corpse `break` in the hits loop does, and neither is observable. What this arm really
## pins is the property a player would notice: a monster cannot sustain itself off an already-won
## fight. That is worth keeping; claiming it defends the gate was not.
func test_a_siphon_cannot_refill_a_caster_off_a_corpse() -> void:
	var ab: Dictionary = _authored("data_drain")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var wraith := _combatant("Data Wraith")
	var corpse := _combatant("Corpse", 10)
	_res._player_party = [corpse]
	_res._enemy_party = [wraith]
	corpse.take_damage(99999)
	assert_false(corpse.is_alive, "CONTROL: the target must actually be dead")
	wraith.current_mp = int(wraith.max_mp / 2)
	var before: int = wraith.current_mp
	_res._resolve_ability(wraith, "data_drain", [corpse])
	assert_lte(wraith.current_mp, before,
		"the caster gained MP from a cast that dealt no damage — live gates the siphon on actual_damage > 0")


func test_an_ability_with_no_siphon_restores_nothing() -> void:
	## A siphon applied unconditionally would refund MP on every magic cast in the game.
	var ab: Dictionary = _authored("fire")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("drain_mp"), "CONTROL: fire must author no drain_mp, or it cannot police the default")
	var caster := _combatant("Mage")
	var hero := _combatant("Hero", 99999)
	_res._player_party = [hero]
	_res._enemy_party = [caster]
	caster.current_mp = int(caster.max_mp / 2)
	var before: int = caster.current_mp
	_res._resolve_ability(caster, "fire", [hero])
	assert_lt(caster.current_mp, before, "fire must still COST MP")
	assert_eq(caster.current_mp, before - int(ab.get("mp_cost", 0)),
		"an ability authoring no drain_mp must pay its cost and get nothing back")


func test_live_still_reads_the_siphon_on_the_magic_path_only() -> void:
	## Axis 2, asserted against live rather than remembered — the check I skipped twice today.
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var at: int = live.find('ability.get("drain_mp"')
	assert_gt(at, 0, "CONTROL: live must still read the key")
	var owner: int = live.substr(0, at).rfind("func _execute_")
	var owner_line: String = live.substr(owner, 44)
	assert_true(owner_line.begins_with("func _execute_magic_ability"),
		"live now reads drain_mp inside %s — the grind siphons only on the magic path and must follow" % owner_line)
	var code: String = GdSource.code_of(SRC)
	## FLOOR. Without it a blinded stripper returns "" -> find() is -1 -> the slice is empty -> the
	## assert below passes on nothing. Measured: the blind-the-stripper mutation was GREEN until this
	## line existed. Every other file in this lane carries this floor; this arm was written without it.
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	var phys: int = code.find('"physical":')
	assert_gt(phys, 0, "CONTROL: the physical arm must be locatable")
	var arm: String = code.substr(phys, code.find("\n\t\t\"", phys + 12) - phys)
	assert_false(arm.contains("_siphon_mp("),
		"the physical arm siphons — live reads drain_mp only on the magic path")
