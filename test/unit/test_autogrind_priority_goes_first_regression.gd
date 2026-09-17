extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## `quick_strike` authors `priority: true` and its description says "always goes first". Live honours
## that in BattleManager._compute_action_speed:2152 by subtracting PRIORITY_OFFSET; the grind sorted
## it by ordinary speed, so a grinding Ninja's signature move landed wherever its speed put it.
##
## ⚠️ NOT AN EXECUTOR KEY, which is why the parity ledger's axis 2 does not apply to it. Every other
## gap this lane has closed was a key read INSIDE a per-type executor (`_execute_physical_ability`
## and friends). `priority` is read at SELECTION time, before any executor exists — live reads it in
## _compute_action_speed, the grind now in _speed_for. A third category, recorded rather than forced
## into the axis-2 map where it would look assessed.
##
## 🔑 REACHABILITY, checked across all four forms BEFORE building, because this lane has ranked a
## backlog wrong by skipping that: no monster authors quick_strike, so forms 1 (pooled), 3
## (_spawn_meta_boss) and 4 (autogrind_spawned) are all out. Form 2 is the whole route — jobs.json
## grants it to `ninja`, the party casts it, and the grind's own _find_attack_ability filters to
## ["magic","physical"] which `quick_strike` (physical) passes. Arm 4 pins that route.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

var _res
var _abs_persistence_was: bool = false


func before_each() -> void:
	_res = ResolverScript.new()
	var abs_node = _res._get_autoload("AutobattleSystem")
	if abs_node:
		_abs_persistence_was = abs_node._test_disable_persistence


## The end-to-end arm installs a REAL grid script on a shared autoload. Left behind, it would hand
## my rule to any later test whose combatant happens to be named "Ninja".
func after_each() -> void:
	var abs_node = _res._get_autoload("AutobattleSystem") if _res else null
	if abs_node:
		abs_node.set_character_script("ninja", {})
		abs_node._test_disable_persistence = _abs_persistence_was


func _hero(name: String, speed: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 9999, "max_mp": 999,
		"attack": 40, "defense": 10, "magic": 40, "speed": speed})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _ability_action(ability_id: String) -> Dictionary:
	return {"type": "ability", "ability_id": ability_id}


func test_a_priority_ability_outruns_a_much_faster_ordinary_action() -> void:
	## The bug, stated as the player sees it: the Ninja is the SLOWER combatant here and must still go
	## first, because that is what the ability says it does.
	var ninja := _hero("Ninja", 1)
	var speedster := _hero("Speedster", 30)
	var quick: int = _res._speed_for(_ability_action("quick_strike"), ninja)
	var ordinary: int = _res._speed_for({"type": "attack"}, speedster)
	gut.p("    quick_strike(speed 1) = %d   attack(speed 30) = %d   (lower goes first)" % [quick, ordinary])
	assert_lt(quick, ordinary,
		"quick_strike authors priority and is described 'always goes first', but the grind ordered it behind a faster combatant's ordinary attack")


func test_lower_really_does_mean_earlier_in_the_loop_that_uses_it() -> void:
	## ⛔ THE ARM THE ONE ABOVE CANNOT BE TRUSTED WITHOUT. It proves a number got SMALLER; "smaller
	## goes first" lives in one line of resolve_battle, and if that line ever flipped to descending,
	## the arm above would still pass while priority actions went DEAD LAST. Pinned against the
	## source rather than restated here, so the rule has one home.
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 10000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('actions.sort_custom(func(a, b): return a.get("speed", 0) < b.get("speed", 0))'),
		"resolve_battle no longer sorts ascending by speed — 'lower goes first' is the assumption every arm in this file rests on")


func test_two_priority_actions_still_sort_against_each_other() -> void:
	## Live's own reason for an OFFSET rather than a flat constant (BattleManager.gd:2151). A flat
	## sentinel would pass arm 1 and collapse every priority action into a tie.
	var slow := _hero("Slow", 2)
	var fast := _hero("Fast", 20)
	var slow_q: int = _res._speed_for(_ability_action("quick_strike"), slow)
	var fast_q: int = _res._speed_for(_ability_action("quick_strike"), fast)
	gut.p("    two priority actions: speed 2 -> %d, speed 20 -> %d" % [slow_q, fast_q])
	assert_lt(fast_q, slow_q,
		"two priority actions no longer order by their own speed — the offset has become a flat sentinel")


func test_an_ordinary_ability_is_not_quietly_hastened() -> void:
	## The other half of the guard: an offset applied to everything is the same bug facing the other
	## way. `power_strike` is a physical ability authoring no `priority`.
	var hero := _hero("Fighter", 10)
	var plain: int = _res._speed_for(_ability_action("power_strike"), hero)
	var attack: int = _res._speed_for({"type": "attack"}, hero)
	gut.p("    power_strike = %d   attack = %d   (both ordinary; ability base is simply slower)" % [plain, attack])
	assert_gt(plain, attack - 1000,
		"an ability authoring no priority was given the priority offset — every action is now 'first'")
	assert_false(_res._ability_has_priority("power_strike"),
		"power_strike authors no priority key and must not be treated as a priority action")
	assert_false(_res._ability_has_priority(""),
		"a non-ability action carries no ability_id and must not be treated as a priority action")


func test_quick_strike_is_still_the_author_and_still_reaches_a_grind() -> void:
	## Reachability, pinned rather than remembered. If quick_strike loses the key, or ninja loses the
	## ability, this fix is defending nothing and should be revisited — not left looking live.
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_gt(abilities.size(), 100, "CONTROL: abilities.json was actually read")
	var authors: Array = []
	for id in abilities:
		if (abilities[id] as Dictionary).has("priority"):
			authors.append(id)
	gut.p("    abilities authoring `priority`: %s" % str(authors))
	assert_true(authors.has("quick_strike"),
		"quick_strike no longer authors `priority` — the resolver's offset now defends nothing")
	assert_eq(str(abilities["quick_strike"].get("type", "")), "physical",
		"quick_strike changed type — the grind's _find_attack_ability filters to magic/physical, and that filter is this ability's route into a grind")
	var ninja_kit: Array = jobs.get("ninja", {}).get("abilities", [])
	assert_true(ninja_kit.has("quick_strike"),
		"ninja no longer grants quick_strike — form 2 was the ONLY reachable route for this key, so losing it makes the wiring unreachable")


func test_the_offset_clears_the_speed_spread_a_grind_can_actually_reach() -> void:
	## ⛔ THE ARM THAT DEFENDS THE NUMBER. Live calls 1000 "larger than any reachable speed_value" on
	## a `base - speed*0.5` scale; the grind's is `base - speed`, twice as sensitive, so live's
	## justification does NOT transfer and the value had to be re-derived. Rather than record that
	## derivation in prose where a future speed rebalance cannot reach it, this recomputes the bound
	## from the authored data every run: 5x is a ceiling on Combatant.gd's +4%/level multiplier
	## (1.0 + 98*0.04 = 4.92 at job_level 99).
	var offset = _res.get("PRIORITY_OFFSET")
	assert_ne(str(offset), "<null>", "CONTROL: PRIORITY_OFFSET is readable — a direct read would abort this arm instead of reddening it")
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var top: int = 0
	for j in jobs.values():
		top = max(top, int((j as Dictionary).get("stat_modifiers", {}).get("speed", 0)))
	for m in monsters.values():
		top = max(top, int((m as Dictionary).get("stats", {}).get("speed", 0)))
	assert_gt(top, 5, "CONTROL: authored speeds were actually found — a 0 here means the stat shape moved, not that everything is slow")
	var bound: int = top * 5 + 10
	gut.p("    max authored speed %d -> level-99 bound %d   offset %d" % [top, bound, int(offset)])
	assert_gt(int(offset), bound,
		"a speed rebalance has outgrown PRIORITY_OFFSET: a fast enough combatant's ordinary action now outruns a priority one, which is the exact bug this const exists to prevent")


func test_the_real_selection_path_carries_the_priority_all_the_way() -> void:
	## ⛔ THE ARM THE ONES ABOVE CANNOT REPLACE, and my file was missing it. Every arm above calls
	## _speed_for DIRECTLY — but the grind's ONLY route to quick_strike is the PLAYER path, and there
	## AutobattleSystem builds the action dict, not the resolver. If that dict ever named the ability
	## under a different key, _speed_for's `ability_id` read would quietly see "" and every arm above
	## would still pass. @cowir-music's Jukebox finding is this exact shape: their helper was correct
	## and three green tests about it hid a menu where paging did nothing.
	var abs_node = _res._get_autoload("AutobattleSystem")
	assert_ne(abs_node, null, "CONTROL: AutobattleSystem must be reachable, or this arm proves nothing")
	abs_node._test_disable_persistence = true
	var ninja := _hero("Ninja", 1)
	ninja.learned_abilities.append("quick_strike")
	var speedster := _hero("Speedster", 30)
	abs_node.set_character_script("ninja", {"rules": [
		{"conditions": [], "actions": [{"type": "ability", "id": "quick_strike", "target": "lowest_hp_enemy"}]}
	]})
	_res._player_party = [ninja, speedster]
	_res._enemy_party = [_hero("Foe", 5)]
	var actions: Array = _res._selection_phase()
	var ninja_action: Dictionary = {}
	var other_action: Dictionary = {}
	for a in actions:
		if a.get("combatant") == ninja:
			ninja_action = a
		elif a.get("combatant") == speedster:
			other_action = a
	assert_false(ninja_action.is_empty(), "CONTROL: the ninja must have selected an action at all")
	assert_false(other_action.is_empty(), "CONTROL: the speedster must have selected an action at all")
	gut.p("    real path -> ninja %s/%s speed %s | speedster %s speed %s" % [
		ninja_action.get("type"), ninja_action.get("ability_id"), ninja_action.get("speed"),
		other_action.get("type"), other_action.get("speed")])
	assert_eq(str(ninja_action.get("ability_id", "")), "quick_strike",
		"the real selection path no longer carries the ability id under `ability_id` — _speed_for reads that key, so the priority offset would silently never apply")
	assert_lt(int(ninja_action.get("speed", 0)), int(other_action.get("speed", 0)),
		"through the REAL selection path the priority action did not outrank a faster combatant's — the helper is right and the path is not")


const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_MEMBERS := ["_ability_has_priority", "_enemy_party", "_get_autoload", "_player_party", "_selection_phase", "_speed_for"]

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	## The lane's floor. Counts distinct members reached in the text BEFORE this function, so the arm
	## cannot count its own get/has_method calls, and compares SETS rather than sizes.
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var before: String = own_src.substr(0, cut)
	var reached: Dictionary = {}
	for raw_line in before.split("\n"):
		if raw_line.contains("res://"):
			continue
		for m in RegEx.create_from_string("(?:_res|AutogrindSystem)\\.([A-Za-z_][A-Za-z_0-9]*)").search_all(raw_line):
			reached[m.get_string(1)] = true
	reached.erase("get")   ## PRIORITY_OFFSET is read through Object.get on purpose — see the margin arm
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
	assert_eq(unpinned, [], "this file reaches members the floor does not pin — the list is a snapshot: %s" % str(unpinned))
	assert_eq(spurious, [], "the floor pins members this file no longer reaches — stale entries: %s" % str(spurious))

	var missing: Array = []
	for name in _PINNED_MEMBERS:
		if not _res.has_method(name) and _res.get(name) == null:
			missing.append(name)
	assert_eq(missing, [], "the resolver no longer carries members this file drives: %s" % str(missing))
