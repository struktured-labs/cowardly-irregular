extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

## A grinding party's EQUIPMENT did nothing. The resolver read 0 of the 15 special_effects keys
## equipment.json authors, so the grind reported survivability, crit rate and rewards for a party
## wearing no gear effects at all — while the same party in a real battle got every one of them.
##
## Found from @cowir-battle's resist_ring fix, which is the live-side half of the same question. The
## gap was invisible to this lane's parity ledger because that ledger censuses abilities.json, and
## gear carries its own battle behaviour in a different file (see
## test_autogrind_equipment_parity_is_named_regression, which now owns that axis).
##
## This wires the MECHANISM plus its two most outcome-relevant consumers. Both mirror live's formula
## rather than inventing one, and the two differ in structure in a way that matters:
##   critical_bonus  folded in UNDER live's total cap (BattleManager:5423 caps
##                   base+speed+passive+equip+buff at 0.50). Added after the min, gear would cross a
##                   ceiling live never lets it cross.
##   evasion_bonus   a SEPARATE roll (BattleManager:9106), not folded into the miss chance — a cloak
##                   plus a passive gives two independent chances to dodge.
##
## Reachability checked before building, across all four forms: the grind's party IS the real party
## (`grind_party = party.duplicate()`), Combatant carries the three slot fields, they round-trip
## through to_dict/from_dict, and EquipmentSystem is an autoload. So the gear genuinely arrives.

const TRIALS: int = 3000

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(name: String, speed: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 999999, "max_mp": 100,
		"attack": 60, "defense": 10, "magic": 10, "speed": speed})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	return c


func _count_log(fragment: String) -> int:
	var n: int = 0
	for line in _res._battle_log:
		if str(line).contains(fragment):
			n += 1
	return n


func test_the_helper_sums_every_equipment_slot() -> void:
	## Deterministic and exact — the arm the statistical ones rest on. assassin_blade authors
	## critical_bonus 0.15 on the WEAPON slot and lucky_charm 0.1 on the ACCESSORY slot, so a helper
	## that walks only one slot, or stops at the first hit, cannot produce 0.25.
	var hero := _fighter("Geared", 5)
	hero.equipped_weapon = "assassin_blade"
	hero.equipped_accessory = "lucky_charm"
	var summed: float = _res._sum_equipment_special_effect(hero, "critical_bonus")
	gut.p("    assassin_blade(0.15) + lucky_charm(0.1) -> %.3f" % summed)
	assert_almost_eq(summed, 0.25, 0.001,
		"the helper must SUM across slots — 0.15 is weapon-only, 0.10 is accessory-only, and either means it stops early")


func test_a_bare_combatant_and_an_unauthored_key_contribute_nothing() -> void:
	## The other half: a helper that returned something for absent gear would inflate every grind.
	var bare := _fighter("Naked", 5)
	assert_almost_eq(_res._sum_equipment_special_effect(bare, "critical_bonus"), 0.0, 0.001,
		"a combatant with no equipment must contribute exactly nothing")
	var geared := _fighter("Geared", 5)
	geared.equipped_weapon = "assassin_blade"
	assert_almost_eq(_res._sum_equipment_special_effect(geared, "familiar_weight_bonus"), 0.0, 0.001,
		"a key the equipped gear does not author must contribute exactly nothing")
	assert_almost_eq(_res._sum_equipment_special_effect(null, "critical_bonus"), 0.0, 0.001,
		"a null combatant must be answered, not crashed on")


func test_gear_evasion_actually_makes_attacks_miss() -> void:
	## elven_cloak authors evasion_bonus 0.1. Base miss at equal speed is 0.10, so the cloak should
	## take total misses to ~0.19 — a separate roll, per live. Margins are ~10 sigma at this N;
	## a band rather than an exact count because the roll is random by design.
	var attacker := _fighter("Attacker", 5)
	var bare := _fighter("Bare", 5)
	for i in TRIALS:
		_res._resolve_attack(attacker, bare)
	var misses_bare: int = _count_log("misses") + _count_log("evades")
	_res._battle_log.clear()
	var cloaked := _fighter("Cloaked", 5)
	cloaked.equipped_accessory = "elven_cloak"
	for i in TRIALS:
		_res._resolve_attack(attacker, cloaked)
	var misses_cloaked: int = _count_log("misses") + _count_log("evades")
	gut.p("    misses/%d — bare %d, elven_cloak %d" % [TRIALS, misses_bare, misses_cloaked])
	assert_gt(misses_bare, 100, "CONTROL: the baseline must miss sometimes, or this comparison has no floor")
	assert_gt(misses_cloaked, misses_bare + 100,
		"an elven_cloak changed nothing — evasion_bonus is authored on the gear and the grind is not reading it")


func test_gear_crit_bonus_actually_raises_the_crit_rate() -> void:
	var target := _fighter("Target", 5)
	var bare := _fighter("Bare", 5)
	for i in TRIALS:
		_res._resolve_attack(bare, target)
	var crits_bare: int = _count_log("Critical hit!")
	_res._battle_log.clear()
	var geared := _fighter("Geared", 5)
	geared.equipped_weapon = "assassin_blade"
	geared.equipped_accessory = "lucky_charm"
	for i in TRIALS:
		_res._resolve_attack(geared, target)
	var crits_geared: int = _count_log("Critical hit!")
	gut.p("    crits/%d — bare %d, assassin_blade+lucky_charm %d" % [TRIALS, crits_bare, crits_geared])
	assert_gt(crits_bare, 50, "CONTROL: the baseline must crit sometimes, or this comparison has no floor")
	assert_gt(crits_geared, crits_bare + 200,
		"crit-bonus gear changed nothing — critical_bonus is authored on assassin_blade and lucky_charm and the grind is not reading it")


func test_gear_cannot_push_the_crit_rate_past_the_cap_live_enforces() -> void:
	## ⛔ THE ARM THAT DEFENDS THE STRUCTURE, not just the effect. Live caps the TOTAL at 0.50
	## (BattleManager:5423). Adding the equipment term AFTER the grind's own min would let a fast,
	## well-equipped attacker exceed a ceiling the real game never lets them cross — and it would
	## still pass the arm above, because it moves the number in the right direction.
	var fast := _fighter("Fast", 40)          ## 0.05 + 40*0.01 = 0.45 before gear
	fast.equipped_weapon = "assassin_blade"
	fast.equipped_accessory = "lucky_charm"   ## +0.25 -> 0.70 uncapped
	var target := _fighter("Target", 40)
	for i in TRIALS:
		_res._resolve_attack(fast, target)
	var hits: int = TRIALS - _count_log("misses") - _count_log("evades")
	var crits: int = _count_log("Critical hit!")
	var rate: float = float(crits) / float(max(hits, 1))
	gut.p("    capped crit rate: %d crits / %d hits = %.3f (live's ceiling is 0.50)" % [crits, hits, rate])
	assert_gt(hits, 500, "CONTROL: enough attacks must land for the rate to mean anything")
	assert_lt(rate, 0.58,
		"the crit rate exceeded live's 0.50 ceiling — the equipment term is being added OUTSIDE the cap, so a geared grind crits harder than the game it simulates")


const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_MEMBERS := ["_battle_log", "_resolve_attack", "_sum_equipment_special_effect"]

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	## ⛔ EXCLUDE THIS ARM'S OWN BODY, NOT EVERYTHING AFTER IT. Slicing to `cut` was a POSITIONAL
	## bound standing in for a structural one: an arm appended AFTER this function escaped the
	## derivation entirely. Measured 2026-09-17 — a planted arm reaching an UNPINNED member scored
	## `reaches: 2 | pinned: 2 | unpinned: []`, EC=0. The floor is conventionally last, so this bites
	## exactly when the file GROWS, which is when a new reach appears. @cowir-controller's
	## "substring position cannot express a region" and @cowir-sfx's substr-to-end-of-function, same
	## class: the scope was a coincidence of layout, not a property of the code.
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
	var missing: Array = []
	for name in _PINNED_MEMBERS:
		if not _res.has_method(name) and _res.get(name) == null:
			missing.append(name)
	assert_eq(missing, [], "the resolver no longer carries members this file drives: %s" % str(missing))
