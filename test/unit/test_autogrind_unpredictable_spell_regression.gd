extends GutTest

## `damage_variance` widens a magic ability's damage roll (BattleManager:5013). `type_error` authors
## 2.0 — "wildly unpredictable", a roll spanning [0, 2x] where every other spell sits near 1.0 — and
## the resolver read it nowhere, so it landed at a flat multiplier every single cast.
##
##   type_error   magic, 1.5x, damage_variance 2.0   cast by forgotten_variable (POOLED)
##
## ⚠️ WHY A DETERMINISTIC ATTACKER IS THE WRONG KIND OF WRONG FOR THIS LANE SPECIFICALLY. The mean is
## roughly right — [0, 2x] averages near 1x — so an EXP-per-hour figure barely moves. What moves is
## the tail: live can spike to 2x and the grind never did, and the HP-threshold interrupt is
## calibrated against exactly the worst case the grind reports. A safety net tuned on a spread that
## does not exist is the failure this mechanism is for.
##
## Rolled BEFORE the elemental multiplier because live does, and the order changes the spread once a
## weakness or resistance is in play.

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


func _combatant(name: String, hp: int = 999999) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 99999,
		"attack": 20, "defense": 10, "magic": 60, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	return c


## Damage from N casts, seeded so the arms measure a distribution rather than flake on one.
func _spread(ability_id: String, casts: int) -> Array:
	var caster := _combatant("Forgotten Variable")
	var target := _combatant("Victim")
	_res._player_party = [target]
	_res._enemy_party = [caster]
	seed(0x5EED)
	var out: Array = []
	for _i in casts:
		var before: int = target.current_hp
		_res._resolve_ability(caster, ability_id, [target])
		out.append(before - target.current_hp)
		caster.current_mp = caster.max_mp
	return out


func test_an_unpredictable_spell_actually_varies() -> void:
	var ab: Dictionary = _authored("type_error")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_gt(float(ab.get("damage_variance", 0.0)), 1.0,
		"CONTROL: type_error must still author a variance above 1, or there is no spread to find")
	var rolls: Array = _spread("type_error", 40)
	var lo: int = rolls.min()
	var hi: int = rolls.max()
	gut.p("    type_error over 40 casts: min %d  max %d  distinct %d" % [lo, hi, _distinct(rolls)])
	assert_gt(_distinct(rolls), 5,
		"40 casts produced %d distinct damages — the spell the data calls 'wildly unpredictable' is a flat number in the grind" % _distinct(rolls))
	assert_gt(hi, lo * 2,
		"the spread is %d..%d, far narrower than the authored [0, 2x] — a tail the safety net is calibrated against is missing" % [lo, hi])


func test_a_spell_without_the_key_stays_steady() -> void:
	## The other direction: applying a [0, N] roll to every spell would make all magic wildly swingy
	## and is a bigger defect than the one being fixed.
	var ab: Dictionary = _authored("fire")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("damage_variance"), "CONTROL: fire must author no variance")
	var rolls: Array = _spread("fire", 12)
	assert_eq(_distinct(rolls), 1,
		"fire produced %d distinct damages over 12 casts — an ability authoring no variance must land the same every time in this engine" % _distinct(rolls))


func test_the_roll_can_reach_both_sides_of_the_flat_value() -> void:
	## A roll clamped to [1, N] would pass the spread arm and still be wrong: live's is [0, N], so a
	## cast can land BELOW the unvaried damage as well as above.
	var ab: Dictionary = _authored("type_error")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var flat: Array = _spread("fire", 1)
	var rolls: Array = _spread("type_error", 40)
	var below := 0
	var above := 0
	for r in rolls:
		if r < int(flat[0]):
			below += 1
		elif r > int(flat[0]):
			above += 1
	gut.p("    vs a steady cast: %d below, %d above" % [below, above])
	assert_gt(below, 0, "no cast landed below the steady value — the roll is not reaching the bottom of [0, 2x]")
	assert_gt(above, 0, "no cast landed above the steady value — the roll is not reaching the top")


func test_live_still_rolls_it_before_the_elemental_path() -> void:
	## Order matters once a weakness or resistance is involved, and only the source says which side
	## live rolls on.
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var at: int = live.find('ability.get("damage_variance"')
	assert_gt(at, 0, "CONTROL: live must still read the key")
	var owner: int = live.substr(0, at).rfind("func _execute_")
	assert_true(live.substr(owner, 44).begins_with("func _execute_magic_ability"),
		"live reads damage_variance outside the magic executor now — the grind rolls it only there")
	var after: String = live.substr(at, 600)
	assert_true(after.contains("randf_range(0.0,"),
		"live's variance roll no longer spans from ZERO — the grind mirrors [0, N] and must follow")
	assert_lt(after.find("get_terrain_damage_modifier"), after.find("damage_variance", 30) if after.find("damage_variance", 30) > 0 else 99999,
		"CONTROL: the terrain path still follows the variance roll in live, which is the order the grind mirrors")
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('ability.get("damage_variance", 0.0)'),
		"the resolver must read the same authored key")


func _distinct(values: Array) -> int:
	var seen: Dictionary = {}
	for v in values:
		seen[v] = true
	return seen.size()
