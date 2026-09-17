extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## resist_ring authors status_resistance 0.3 — 800 gold, and also a Frosthold chest. @cowir-battle
## found it had exactly ONE reader in live, on the ATTACKER's on-hit path, so it only ever resisted
## the party's own poison_dagger; they wired the route every status a player actually suffers takes.
## The grind read the key nowhere at all, so a grinding party's ring did nothing on either route.
##
## ⚠️ THE ARITHMETIC IS NOT THE SAME AS ITS NEIGHBOURS, and copying them would have invented a cap.
## evasion_bonus and critical_bonus clamp their INPUT to 0.50 because live caps those at their own
## sites. Live caps status_resistance NOWHERE: it clamps the RESULT to [0,1]. With resist_ring at 0.3
## the difference is unobservable today, which is why arm 4 pins it structurally instead.

const TRIALS: int = 1000

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 99999, "max_mp": 100,
		"attack": 30, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	return c


func _ability(id: String) -> Dictionary:
	var js = _res._get_autoload("JobSystem")
	assert_ne(js, null, "CONTROL: JobSystem must be reachable, or these are not the authored numbers")
	return js.get_ability(id)


## How many of N attempts land the status, clearing it between attempts.
func _landed(ability_id: String, target: Combatant, n: int) -> int:
	var caster := _combatant("Caster")
	var ab: Dictionary = _ability(ability_id)
	var hits: int = 0
	for i in n:
		target.status_effects.clear()
		_res._maybe_inflict_status(caster, target, ab, ability_id)
		if target.status_effects.size() > 0:
			hits += 1
	return hits


func test_the_authored_numbers_this_file_rests_on_are_still_authored() -> void:
	## CONTROL FIRST, because every arm below is a comparison against these two values.
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var ring: Dictionary = (eq.get("accessories", {}) as Dictionary).get("resist_ring", {})
	assert_almost_eq(float((ring.get("special_effects", {}) as Dictionary).get("status_resistance", 0.0)), 0.3, 0.001,
		"resist_ring no longer authors status_resistance 0.3 — every band below is derived from it")
	assert_almost_eq(float(_ability("tetanus_touch").get("effect_chance", 0.0)), 1.0, 0.001,
		"tetanus_touch no longer authors effect_chance 1.0")
	assert_almost_eq(float(_ability("smash").get("effect_chance", 0.0)), 0.2, 0.001,
		"smash no longer authors effect_chance 0.2 — arm 3 needs a chance BELOW the ring's 0.3")


func test_a_resist_ring_makes_a_status_land_less_often() -> void:
	## tetanus_touch is a guaranteed poison (1.0). Against the ring: 1.0 - 0.3 = 0.7.
	var bare := _combatant("Bare")
	var bare_hits: int = _landed("tetanus_touch", bare, TRIALS)
	var ringed := _combatant("Ringed")
	ringed.equipped_accessory = "resist_ring"
	var ring_hits: int = _landed("tetanus_touch", ringed, TRIALS)
	gut.p("    poison landed/%d — bare %d, resist_ring %d (expect ~1000 vs ~700)" % [TRIALS, bare_hits, ring_hits])
	assert_eq(bare_hits, TRIALS, "CONTROL: a 1.0-chance status must always land on an unprotected target")
	assert_lt(ring_hits, bare_hits - 150,
		"a resist_ring changed nothing — status_resistance is authored on it and the grind is not reading it")
	assert_gt(ring_hits, 500,
		"the ring blocked far more than its 30% — the resist is being applied more than once, or as a multiplier rather than a subtraction")


func test_a_resist_that_exceeds_the_chance_blocks_the_status_entirely() -> void:
	## ⛔ THE DETERMINISTIC ONE: smash authors 0.2, the ring resists 0.3, so the effective chance is
	## clampf(-0.1, 0, 1) = 0 and the stun can never land. It proves the resist is SUBTRACTED rather
	## than ignored — measured, dropping the resist read makes this land 90 times in 500.
	## ⚠️ It does NOT catch a missing clamp, and I wrote that it did before measuring. Removing the
	## clampf leaves effective at -0.1, and the `effective <= 0.0` guard on the next line returns on
	## that already — so the behaviour is identical and this arm stays green. The clamp is defensive
	## in both directions and unobservable today (chance <= 1.0 and resist >= 0 bound the other end
	## too); the reason to keep it is that it is live's exact expression, which is what arm 4 pins.
	var ringed := _combatant("Ringed")
	ringed.equipped_accessory = "resist_ring"
	var hits: int = _landed("smash", ringed, 500)
	var bare := _combatant("Bare")
	var bare_hits: int = _landed("smash", bare, 500)
	gut.p("    smash(0.2) landed/500 — bare %d, resist_ring(0.3) %d (expect ~100 vs exactly 0)" % [bare_hits, hits])
	assert_gt(bare_hits, 30, "CONTROL: smash must land sometimes unresisted, or a 0 below proves nothing")
	assert_eq(hits, 0,
		"a resist larger than the chance did not block the status — the result is not clamped to [0,1], and a negative effective chance lands EVERY time")


func test_the_resist_is_not_clamped_the_way_its_neighbours_are() -> void:
	## Structural, because it is unobservable: resist_ring's 0.3 is the only authored value, so an
	## invented 0.50 input cap would change no outcome today and no behavioural arm could see it.
	## Live clamps the RESULT (clampf(chance - resist, 0.0, 1.0)) and caps the key nowhere.
	var grind: String = GdSource.code_of(GRIND)
	assert_gt(grind.length(), 10000, "CONTROL: the resolver was actually read")
	assert_true(grind.contains('clampf(chance - resist, 0.0, 1.0)'),
		"the resolver no longer clamps the RESULT of chance minus resist, which is live's formula at :5002 and :4592")
	var capped: Array = []
	for line in grind.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue
		if t.contains("status_resistance") and t.contains("0.50"):
			capped.append(t.substr(0, 70))
	assert_eq(capped, [],
		"status_resistance is being clamped to 0.50 like evasion_bonus and critical_bonus — live caps it NOWHERE, so this invents a ceiling the game does not have: %s" % str(capped))


const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_MEMBERS := ["_get_autoload", "_maybe_inflict_status"]

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var reached: Dictionary = {}
	for raw_line in own_src.substr(0, cut).split("\n"):
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
