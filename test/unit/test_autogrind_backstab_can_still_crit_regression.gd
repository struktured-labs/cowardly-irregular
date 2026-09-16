extends GutTest

## `crit_chance` lets an ABILITY roll its own critical hit (BattleManager:4795). The resolver's
## ability path had no crit at all — only its basic-attack path did — so `backstab`, which authors
## 0.3 and is a Rogue ability, never landed its signature in a grind.
##
## PLAYER SIDE, which is the half this lane exists for: autogrind is where a player TESTS a build,
## and a crit build was being evaluated with its crits switched off. The mean loss is ~15% of that
## ability's damage; the visible loss is that the thing the build is FOR never happened.
##
## ⚠️ 1.5 FLAT, and the divergence is declared rather than hidden. Live applies
## `_get_crit_multiplier`, which is 1.5 plus PassiveSystem's `crit_damage_bonus` accumulator. This
## file's own BASIC-ATTACK crit is also a flat 1.5 and also ignores that accumulator — so mirroring
## live's full multiplier here would make the two grind paths disagree with each other while only one
## agreed with live. Closing it is ONE change covering both paths, and it is not this one.

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


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 999999, "max_mp": 99999,
		"attack": 40, "defense": 10, "magic": 40, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


## Damage from N casts, seeded — a crit is a ROLL, so one cast measures nothing.
func _spread(ability_id: String, casts: int) -> Array:
	var caster := _combatant("Rogue")
	var target := _combatant("Victim")
	_res._player_party = [caster]
	_res._enemy_party = [target]
	seed(0x5EED)
	var out: Array = []
	for _i in casts:
		var before: int = target.current_hp
		_res._resolve_ability(caster, ability_id, [target])
		out.append(before - target.current_hp)
		caster.current_mp = caster.max_mp
	return out


func _distinct(values: Array) -> int:
	var seen: Dictionary = {}
	for v in values:
		seen[v] = true
	return seen.size()


func test_an_ability_that_authors_a_crit_chance_can_crit() -> void:
	var ab: Dictionary = _authored("backstab")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var chance: float = float(ab.get("crit_chance", 0.0))
	assert_gt(chance, 0.0, "CONTROL: backstab must still author a crit_chance")
	var rolls: Array = _spread("backstab", 60)
	gut.p("    backstab x60 at %.0f%%: min %d  max %d  distinct %d" % [chance * 100.0, rolls.min(), rolls.max(), _distinct(rolls)])
	assert_eq(_distinct(rolls), 2,
		"60 casts produced %d distinct damages; a crit roll gives exactly TWO outcomes here — 1 means it never crits, more means something else is varying" % _distinct(rolls))
	assert_gt(rolls.max(), rolls.min(),
		"backstab never crit in 60 casts at an authored %.0f%% — the Rogue's signature does not land in a grind" % (chance * 100.0))


func test_the_crit_is_the_authored_multiplier_not_a_bigger_one() -> void:
	## A crit that lands at the wrong size passes the arm above. The expected damage is derived by
	## driving the resolver's own single-hit path, so it tracks the damage model rather than pinning a
	## number — and the crit branch multiplies the BASE, so the comparison is against 1.5x base.
	var ab: Dictionary = _authored("backstab")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var rolls: Array = _spread("backstab", 60)
	var lo: int = rolls.min()
	var hi: int = rolls.max()
	gut.p("    non-crit %d, crit %d, ratio %.2f" % [lo, hi, float(hi) / float(lo)])
	assert_gt(float(hi) / float(lo), 1.2,
		"the crit landed at %.2fx the ordinary hit — too small to be a 1.5x on the base" % (float(hi) / float(lo)))
	assert_lt(float(hi) / float(lo), 1.9,
		"the crit landed at %.2fx — larger than a 1.5x on the base, so it is compounding somewhere" % (float(hi) / float(lo)))


func test_an_ability_with_no_crit_chance_never_crits() -> void:
	## The default must stay 0.0. A non-zero default would make every physical ability in the game
	## start critting, which is a far larger change than the one being made.
	var ab: Dictionary = _authored("power_strike")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("crit_chance"), "CONTROL: power_strike must author no crit_chance")
	var rolls: Array = _spread("power_strike", 40)
	assert_eq(_distinct(rolls), 1,
		"power_strike produced %d distinct damages over 40 casts — an ability authoring no crit_chance must never crit" % _distinct(rolls))


func test_live_still_rolls_the_abilitys_own_chance_on_the_physical_path() -> void:
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var at: int = live.find('ability.get("crit_chance"')
	assert_gt(at, 0, "CONTROL: live must still read the key")
	var owner: int = live.substr(0, at).rfind("func _execute_")
	assert_true(live.substr(owner, 46).begins_with("func _execute_physical_ability"),
		"live reads crit_chance outside the physical executor now — the grind rolls it only there")
	assert_true(live.substr(at, 1600).contains("randf() < crit_chance"),
		"live no longer rolls the ability's own chance — the grind mirrors that roll")
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('randf() < float(ability.get("crit_chance", 0.0))'),
		"the resolver must roll the AUTHORED chance with a 0.0 default, so an ability opts in as it does live")


func test_the_declared_multiplier_divergence_is_still_true() -> void:
	## The 1.5 flat is a DECLARED simplification, not an oversight: live adds PassiveSystem's
	## crit_damage_bonus and this file's basic-attack crit ignores it too. If the basic-attack path
	## ever learns the accumulator, the ability path must learn it in the same change — otherwise the
	## two grind paths disagree with each other, which is worse than both differing from live.
	var code: String = GdSource.code_of(SRC)
	var attack_at: int = code.find("func _resolve_attack(")
	assert_gt(attack_at, 0, "CONTROL: the basic-attack path must be locatable")
	var attack_body: String = code.substr(attack_at, code.find("\nfunc ", attack_at + 10) - attack_at)
	assert_true(attack_body.contains("damage *= 1.5"),
		"the basic-attack crit no longer uses a flat 1.5 — the ability crit still does, and the two grind paths now disagree")
	assert_false(attack_body.contains("crit_damage_bonus"),
		"the basic-attack path learned PassiveSystem's accumulator; the ability path must learn it in the SAME change")


## ⛔ `seed()` SETS THE PROCESS-WIDE RNG AND GUT RUNS EVERY FILE IN ONE PROCESS, so a file that
## seeds and does not restore makes every LATER file deterministic — @cowir-battle measured a probe
## drawing one identical value three times after a seeded file, and three different ones after the
## restore. The hazard is ORDER-DEPENDENCE: a later probabilistic arm's result then depends on which
## files preceded it, so a flake reads as a real failure and a probabilistic bug reads as absent.
## Same class as the Input-singleton leak CLAUDE.md documents for physics tests, and not in that list.
## after_all, not after_each: determinism WITHIN this file is deliberate and untouched — only the
## exit is cleaned up. randomize() rather than replaying a saved seed (@cowir-music): replaying
## re-freezes the next file's stream at a different constant, which is the same defect wearing a
## number that changes between runs.
func after_all() -> void:
	randomize()
