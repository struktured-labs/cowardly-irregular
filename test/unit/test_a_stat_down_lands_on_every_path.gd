extends GutTest

## ⛔ SIXTEEN MONSTER ABILITIES PROMISED A DEBUFF AND WROTE A DEAD TOKEN. The six stat-down effects
## are handled in `_execute_support_ability`'s match, keyed on the effect NAME. A SUPPORT ability
## authoring `speed_down` got a real `add_debuff`; a MAGIC or PHYSICAL one authoring the same string
## fell to `_apply_ability_status`, which called `add_status("speed_down")` — and `has_status` reads
## `status_effects` while the stat lives in `active_debuffs`. Zero consumers, in any file.
##
## ⚠️ THE DATA WAS COMPLETE THE WHOLE TIME. 15 of the 16 author `stat_modifier` — the same key the
## working path reads — plus a duration and a description promising the effect. `oxidize`:
## "massively reducing defense", 0.6 for 4 turns. `armor_break`: "shatters armor", 0.5 for 3.
## Nothing here invents a magnitude; that is what separated this from the frost_armor hold.
##
## Found by @cowir-ai's `slow` finding in the autogrind console ring — a status the game can DISPLAY
## and can never APPLY. Same two-container split, one engine over: `status_effects` vs `active_debuffs`.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"

var _saved_party: Array
var _saved_enemies: Array


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	seed(20260917)


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


func _combatant(name_str: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name_str
	c.max_hp = 999999
	c.current_hp = 999999
	c.attack = 100
	c.magic = 100
	c.defense = 100
	c.speed = 100
	c.is_alive = true
	return c


## Casts a monster-shaped ability at one party member through the REAL executor and returns the
## target's buffed stat afterwards. `modifier` is the authored stat_modifier.
func _stat_after(type: String, effect: String, stat: String, modifier: float) -> float:
	var monster := _combatant("Rat")
	var victim := _combatant("Mira")
	BattleManager.enemy_party.assign([monster] as Array[Combatant])
	BattleManager.player_party.assign([victim] as Array[Combatant])
	var ability := {"type": type, "effect": effect, "effect_chance": 1.0,
		"stat_modifier": modifier, "duration": 3, "damage_multiplier": 0.01, "power": 0.01}
	if type == "magic":
		BattleManager._execute_magic_ability(monster, ability, [victim])
	else:
		BattleManager._execute_physical_ability(monster, ability, [victim])
	assert_true(victim.is_alive, "CONTROL: the fixture survived, so the apply was reached")
	return victim.get_buffed_stat(stat, victim.get(stat))


func test_a_stat_down_from_a_magic_ability_actually_lowers_the_stat() -> void:
	## The shipped bug, on the route 13 of the 16 take.
	for pair in [["defense_down", "defense"], ["attack_down", "attack"], ["speed_down", "speed"],
			["magic_defense_down", "magic_defense"]]:
		var after: float = _stat_after("magic", pair[0], pair[1], 0.5)
		assert_lt(after, 100.0,
			"%s must reduce %s — it authored a magnitude and the description promises it (got %s)" % [pair[0], pair[1], after])


func test_a_stat_down_from_a_physical_ability_lands_too() -> void:
	## armor_break, rending_bite and stack_smash are physical; same owner, same route.
	var after: float = _stat_after("physical", "defense_down", "defense", 0.5)
	assert_lt(after, 100.0, "a physical stat-down must land as well (got %s)" % after)


func test_the_magnitude_comes_from_the_data() -> void:
	## Anti-coincidence: the reduction must track the AUTHORED stat_modifier, not a constant.
	## Pinning a value would be the coincidental-value trap; pinning the RELATIONSHIP is the rule.
	var half: float = _stat_after("magic", "defense_down", "defense", 0.5)
	var mild: float = _stat_after("magic", "defense_down", "defense", 0.9)
	assert_lt(half, mild,
		"a 0.5 modifier must bite harder than a 0.9 one (%s vs %s), or the magnitude is invented" % [half, mild])


func test_a_non_stat_effect_is_still_a_status() -> void:
	## Anti-vacuity in the expensive direction: the new branch must not swallow ordinary statuses.
	var monster := _combatant("Rat")
	var victim := _combatant("Mira")
	BattleManager.enemy_party.assign([monster] as Array[Combatant])
	BattleManager.player_party.assign([victim] as Array[Combatant])
	BattleManager._execute_magic_ability(monster,
		{"type": "magic", "effect": "poison", "effect_chance": 1.0, "duration": 3,
		"damage_multiplier": 0.01, "power": 0.01}, [victim])
	assert_true(victim.has_status("poison"), "poison is a STATUS and must still be applied as one")


func test_a_stat_down_means_the_same_thing_on_both_paths() -> void:
	## ⛔ THE HELPER MIRRORS THE SUPPORT ARMS RATHER THAN OWNING THEM — those arms are non-contiguous
	## inside a 700-line match and folding them in is a separate change. CLAUDE.md's rule for a
	## redundant pair is to assert AGREEMENT rather than model precedence, so this derives both
	## (debuff name -> stat) maps from source and requires the shared entries to match exactly.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = code.find("func _apply_stat_down(")
	assert_gt(at, -1, "CONTROL: the ability-path owner survives stripping")
	var helper: String = code.substr(at, code.find("\nfunc ", at + 1) - at)
	var sup_at: int = code.find("func _execute_support_ability(")
	assert_gt(sup_at, -1, "CONTROL: the support executor survives stripping")
	var support: String = code.substr(sup_at, code.find("\nfunc ", sup_at + 1) - sup_at)
	var re := RegEx.create_from_string("add_debuff\\(\"([^\"]+)\", \"([^\"]+)\"")
	var helper_map: Dictionary = {}
	for m in re.search_all(helper):
		helper_map[m.get_string(1)] = m.get_string(2)
	var support_map: Dictionary = {}
	for m in re.search_all(support):
		support_map[m.get_string(1)] = m.get_string(2)
	assert_gt(helper_map.size(), 4, "CONTROL: the helper names several debuffs (%d)" % helper_map.size())
	assert_gt(support_map.size(), 4, "CONTROL: the support path names several debuffs (%d)" % support_map.size())
	var disagree: Array = []
	for name in helper_map:
		if support_map.has(name) and support_map[name] != helper_map[name]:
			disagree.append("%s: %s vs %s" % [name, helper_map[name], support_map[name]])
	assert_eq(disagree, [],
		"a debuff name must mean the same stat on both paths, or one authored effect has two meanings: " + str(disagree))
