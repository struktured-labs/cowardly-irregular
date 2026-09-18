extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## poison_dagger authors poison_chance 0.25 and sleep_dagger authors sleep_chance 0.20 — each
## weapon's headline gimmick. A grinding party got the stat bonus and none of the proc.
##
## 🔑 THE AXIS-2 DISTINCTION IS THE EASY MISTAKE HERE, and it is why this file exists as much as the
## proc does. Live calls _apply_equipment_on_hit_status from _execute_attack ONLY — the BASIC
## attack. This resolver has TWO damage entry points, `_resolve_attack` (basic) and
## `_resolve_attack_with_power` (ability damage), and they end in identical lines. Wiring both would
## make a grinding Rogue's power_strike proc poison where the real game's does not — the exact shape
## this lane's parity ledger was built after: `hits` wired into both arms when live reads it on one.
##
## ⚠️ The TARGET's status_resistance is subtracted here, as live does, with the clamp on the RESULT.
## That is the second consumer of resist_ring in this file; the first is _maybe_inflict_status (the
## ability path). Live has the same two, sharing one formula so they cannot drift.

const TRIALS: int = 1200

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 999999, "max_mp": 100,
		"attack": 40, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	return c


## How many of n basic attacks land the named status, clearing it between swings.
func _procs(attacker: Combatant, target: Combatant, status: String, n: int) -> int:
	var hits: int = 0
	for i in n:
		target.status_effects.clear()
		_res._resolve_attack(attacker, target)
		if target.has_status(status):
			hits += 1
	return hits


func test_the_authored_numbers_this_file_rests_on_are_still_authored() -> void:
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var weapons: Dictionary = eq.get("weapons", {})
	assert_almost_eq(float((weapons.get("poison_dagger", {}).get("special_effects", {}) as Dictionary).get("poison_chance", 0.0)), 0.25, 0.001,
		"poison_dagger no longer authors poison_chance 0.25 — the band below is derived from it")
	assert_almost_eq(float((weapons.get("sleep_dagger", {}).get("special_effects", {}) as Dictionary).get("sleep_chance", 0.0)), 0.20, 0.001,
		"sleep_dagger no longer authors sleep_chance 0.20")


func test_a_poison_dagger_actually_poisons_on_hit() -> void:
	var bare := _fighter("Bare")
	var armed := _fighter("Armed")
	armed.equipped_weapon = "poison_dagger"
	var bare_procs: int = _procs(bare, _fighter("VictimA"), "poison", TRIALS)
	var armed_procs: int = _procs(armed, _fighter("VictimB"), "poison", TRIALS)
	gut.p("    poison procs/%d — bare %d, poison_dagger %d (expect 0 vs ~300)" % [TRIALS, bare_procs, armed_procs])
	assert_eq(bare_procs, 0, "CONTROL: an unarmed attacker must never proc poison, or the comparison measures something else")
	assert_gt(armed_procs, 150,
		"a poison_dagger never poisoned anything — poison_chance is authored on it and the grind is not reading it")


func test_a_sleep_dagger_procs_its_own_status_and_not_the_other() -> void:
	## The table is generic, so a loop that read the wrong entry would still "work" for one weapon.
	var armed := _fighter("Armed")
	armed.equipped_weapon = "sleep_dagger"
	var victim := _fighter("Victim")
	var slept: int = _procs(armed, victim, "sleep", TRIALS)
	var poisoned: int = _procs(armed, victim, "poison", TRIALS)
	gut.p("    sleep_dagger — sleep %d, poison %d (expect ~240 vs exactly 0)" % [slept, poisoned])
	assert_gt(slept, 120, "a sleep_dagger never slept anything")
	assert_eq(poisoned, 0, "a sleep_dagger applied POISON — the on-hit table is reading the wrong entry for its key")


func test_a_resist_ring_reduces_the_on_hit_proc_too() -> void:
	## Live subtracts the target's status_resistance at THIS site as well as the ability site, sharing
	## one formula. 0.25 - 0.3 clamps to 0, so a ring-wearer cannot be poisoned by a dagger at all.
	var armed := _fighter("Armed")
	armed.equipped_weapon = "poison_dagger"
	var ringed := _fighter("Ringed")
	ringed.equipped_accessory = "resist_ring"
	var procs: int = _procs(armed, ringed, "poison", 600)
	var bare_victim: int = _procs(armed, _fighter("Bare"), "poison", 600)
	gut.p("    poison_dagger(0.25) vs resist_ring(0.3) — %d/600, unprotected %d/600" % [procs, bare_victim])
	assert_gt(bare_victim, 80, "CONTROL: the dagger must proc on an unprotected victim, or a 0 below proves nothing")
	assert_eq(procs, 0,
		"a resist larger than the proc chance did not block it — the result is not clamped the way live clamps it at :4592")


func test_an_ability_hit_does_not_proc_the_weapon() -> void:
	## ⛔ THE AXIS-2 ARM. Live procs on the BASIC attack only. `_resolve_attack_with_power` is the
	## ability-damage path and ends in lines identical to _resolve_attack's — wiring both is a
	## one-line mistake that no behavioural arm about poison would catch, because it moves the number
	## in the direction that looks like the feature working.
	var armed := _fighter("Armed")
	armed.equipped_weapon = "poison_dagger"
	var victim := _fighter("Victim")
	var procs: int = 0
	for i in 600:
		victim.status_effects.clear()
		_res._resolve_attack_with_power(armed, victim, 40)
		if victim.has_status("poison"):
			procs += 1
	gut.p("    ability-damage path procs: %d/600 (must be exactly 0)" % procs)
	assert_eq(procs, 0,
		"the on-hit proc fired on the ABILITY damage path — live calls it from _execute_attack only, so a grinding Rogue's power_strike would poison where the real game's does not")


const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_MEMBERS := ["_resolve_attack", "_resolve_attack_with_power"]

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var _after: int = own_src.find("\nfunc ", cut + 10)
	var scanned: String = own_src.substr(0, cut) + ("" if _after < 0 else own_src.substr(_after))
	var reached: Dictionary = {}
	for raw_line in scanned.split("\n"):
		if raw_line.contains("res://"):
			continue
		for m in RegEx.create_from_string("(?:_res|AutogrindSystem)\\.([A-Za-z_][A-Za-z_0-9]*)").search_all(raw_line):
			reached[m.get_string(1)] = true
	var pinned: Dictionary = {}
	for x in _PINNED_MEMBERS:
		pinned[x] = true
	assert_gt(reached.size(), 0, "CONTROL: the scan found reaches, or this comparison proves nothing")
	var unpinned: Array = []
	for k in reached:
		if not pinned.has(k):
			unpinned.append(k)
	var spurious: Array = []
	for k in pinned:
		if not reached.has(k):
			spurious.append(k)
	gut.p("    reaches: %d | pinned: %d | unpinned: %s | spurious: %s" % [reached.size(), pinned.size(), str(unpinned), str(spurious)])
	assert_eq(unpinned, [], "this file reaches members the floor does not pin: %s" % str(unpinned))
	assert_eq(spurious, [], "the floor pins members this file no longer reaches: %s" % str(spurious))
