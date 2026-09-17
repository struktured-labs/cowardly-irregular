extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## `thiefs_glove` authors steal_bonus 0.5 — the largest single gear effect in equipment.json — and a
## grinding Rogue got none of it. Live composes the rate in ONE place (BattleManager._steal_success_rate
## :5503, `clampf(base + equip + passive, 0.0, 1.0)`) precisely because two call sites had each grown
## their own inline clamp and a passive promising "+30% steal success" reached only one of them.
##
## ⚠️ THE PASSIVE TERM IS DELIBERATELY NOT PORTED and that is a ruling, not an oversight:
## `steal_chance` is one of the 12 stat_mods keys in the 45-passive scoping call sitting with
## struktured. Both terms ADD to the same rate, so wiring the equipment half alone moves the grind
## TOWARD live and never past it — unlike a half-ported Speculator, where the portable piece was the
## cost and the unportable piece was the benefit.
##
## 🔑 REACHABILITY across all four forms, checked before building: `steal` and `mug` are both in the
## Rogue's BASE kit (form 2), and thiefs_glove is an accessory the party equips. No monster authors
## either ability with the glove, so the enemy side cannot reach it — and the enemy steal PAYOUT is
## separately declared in the ledger as a gold-fountain risk, which this change does not touch.

const TRIALS: int = 1200

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _rogue(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 900, "max_mp": 100,
		"attack": 30, "defense": 10, "magic": 10, "speed": 12})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	return c


## Steals landed out of n attempts, reading the battle log rather than the gold total so the
## party-side gold guard cannot mask a rate change.
func _landed(caster: Combatant, target: Combatant, base_rate: float, n: int) -> int:
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._battle_log.clear()
	for i in n:
		_res._roll_steal(caster, {}, [target], base_rate)
	var hits: int = 0
	for line in _res._battle_log:
		if str(line).contains("steals"):
			hits += 1
	return hits


func test_the_authored_numbers_this_file_rests_on_are_still_authored() -> void:
	## CONTROL FIRST — every band below is derived from these two values.
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var glove: Dictionary = (eq.get("accessories", {}) as Dictionary).get("thiefs_glove", {})
	assert_almost_eq(float((glove.get("special_effects", {}) as Dictionary).get("steal_bonus", 0.0)), 0.5, 0.001,
		"thiefs_glove no longer authors steal_bonus 0.5 — the bands below are derived from it")
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var rogue_kit: Array = jobs.get("rogue", {}).get("abilities", [])
	assert_true(rogue_kit.has("steal") or rogue_kit.has("mug"),
		"the Rogue's base kit no longer carries a steal — form 2 was the only route to this gear effect")
	assert_true(abilities.has("steal"), "CONTROL: abilities.json was actually read")


func test_a_thiefs_glove_makes_a_steal_land_more_often() -> void:
	## base 0.3 bare vs 0.3 + 0.5 = 0.8 gloved. Over 1200 attempts that is ~360 vs ~960; the band is
	## wide enough that only a missing read, not sampling, can fail it.
	var bare := _rogue("Bare")
	var gloved := _rogue("Gloved")
	gloved.equipped_accessory = "thiefs_glove"
	var bare_hits: int = _landed(bare, _rogue("VictimA"), 0.3, TRIALS)
	var glove_hits: int = _landed(gloved, _rogue("VictimB"), 0.3, TRIALS)
	gut.p("    steals landed/%d — bare %d, thiefs_glove %d (expect ~360 vs ~960)" % [TRIALS, bare_hits, glove_hits])
	assert_gt(bare_hits, 200, "CONTROL: an unequipped Rogue must still land steals, or the comparison has no floor")
	assert_gt(glove_hits, bare_hits + 300,
		"a thiefs_glove changed nothing — steal_bonus is authored on it and the grind is not reading it")


func test_the_rate_is_clamped_at_one_and_not_past_it() -> void:
	## ⛔ THE STRUCTURAL HALF. base 0.6 + 0.5 = 1.1 uncapped. Live clamps the SUM to [0,1]; without
	## that a rate above 1 is indistinguishable from 1 today — `randf()` never returns 1.0 — so this
	## arm reds on the SOURCE rather than pretending a behavioural probe could tell them apart.
	var gloved := _rogue("Gloved")
	gloved.equipped_accessory = "thiefs_glove"
	var hits: int = _landed(gloved, _rogue("Victim"), 0.6, 400)
	gut.p("    base 0.6 + glove 0.5 -> %d/400 landed (a clamped 1.0 lands every time)" % hits)
	assert_eq(hits, 400, "a rate at or above 1.0 must land every attempt")
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 10000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('clampf(base_rate + _sum_equipment_special_effect(caster, "steal_bonus"), 0.0, 1.0)'),
		"the resolver no longer clamps the composed steal rate the way live does at :5509 — an unclamped sum is invisible behaviourally because randf() never reaches 1.0")


func test_the_passive_half_is_still_absent_on_purpose() -> void:
	## The other half of live's formula is a RULING, and an arm here stops it from being quietly
	## closed or quietly forgotten. It reds when someone wires passives — which is the moment the
	## scoping call was answered and this note should retire.
	var code: String = GdSource.code_of(GRIND)
	var passive_reads: Array = []
	for probe in ["steal_chance", "get_passive_mods", "PassiveSystem"]:
		if code.contains(probe):
			passive_reads.append(probe)
	assert_eq(passive_reads, [],
		"the resolver now reads the passive half of the steal rate — the 45-passive ruling landed, so compose all three terms and retire this arm: %s" % str(passive_reads))


const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_MEMBERS := ["_battle_log", "_enemy_party", "_player_party", "_roll_steal"]

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	## Excludes this arm's OWN body rather than everything after it — a reach added below the floor
	## would otherwise escape the derivation entirely.
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
