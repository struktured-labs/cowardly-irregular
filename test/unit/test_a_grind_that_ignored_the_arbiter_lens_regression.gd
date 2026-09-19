extends GutTest

## The Arbiter Lens's Final Word — "+50% damage to enemies below 25% HP" — fires on ALL THREE of
## live's damage paths (_execute_attack, _execute_physical_ability, _execute_magic_ability) and on
## NONE of the grind's. `HeadlessBattleResolver` contained zero occurrences of "lens".
##
## @cowir-battle found the same bonus missing from the player-facing PREVIEW and fixed that side;
## this is the third consumer. The lens is equippable from src/ui/LensMenu.gd and the assignment
## lives in GameState, so it is player state that outlives a battle — a grind run by an Arbiter
## holder simulated a different game than the one they were about to play.
##
## ⚠️ WHY data/lenses.json SURVIVED THREE PARITY REGISTRIES: they census abilities.json (70 keys)
## and equipment.json. Lenses are a THIRD data file and sit outside every one of their corpora —
## a registry cannot report a file it never opens. The remaining five meta keys are named in
## test_autogrind_the_lens_gap_is_named_regression rather than left invisible.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"

var _res
var _restore: Dictionary = {}


func before_each() -> void:
	_res = ResolverScript.new()
	if AutogrindSystem:
		AutogrindSystem._test_disable_persistence = true
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		_restore = (gs.lens_assignments as Dictionary).duplicate()


func after_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		gs.lens_assignments = _restore.duplicate()


func _key(name: String) -> String:
	return name.to_lower().replace(" ", "_")


func _combatant(name: String, hp: int, max_hp: int = 10000) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": max_hp, "max_mp": 99999,
		"attack": 40, "defense": 10, "magic": 60, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	return c


func _unequip(char_name: String) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		(gs.lens_assignments as Dictionary).erase(_key(char_name))


func _equip(char_name: String, axis: String) -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	gs.lens_assignments[_key(char_name)] = axis
	var ls: Node = get_node_or_null("/root/LensSystem")
	if ls == null or not ls.has_method("get_lens_meta_effects"):
		return false
	return not (ls.get_lens_meta_effects(_key(char_name)) as Dictionary).is_empty()


## Damage one action deals to a target at `hp`, with the attacker holding `axis` ("" = no lens).
func _damage(path: String, hp: int, axis: String) -> int:
	var attacker := _combatant("Arbiter Holder", 9999)
	var target := _combatant("Victim", hp)
	## ⛔ ERASE, do not merely skip equipping. The assignment lives in GameState and OUTLIVES this
	## call, so the previous pair's lens was still on for the next pair's "bare" measurement —
	## which read as "the bonus does not apply" on two of three paths. The plant poisoned the probe.
	_unequip("Arbiter Holder")
	if axis != "" and not _equip("Arbiter Holder", axis):
		return -1
	_res._player_party = [target]
	_res._enemy_party = [attacker]
	seed(0x11A2B3)
	var before: int = target.current_hp
	match path:
		"attack":
			_res._resolve_attack(attacker, target)
		"power":
			_res._resolve_attack_with_power(attacker, target, 120)
		"magic":
			_res._resolve_ability(attacker, "fire", [target])
	return before - target.current_hp


func _pair(path: String, hp: int) -> Array:
	return [_damage(path, hp, ""), _damage(path, hp, "arbiter")]


func test_the_arbiter_finishes_a_wounded_enemy_on_every_damage_path() -> void:
	if get_node_or_null("/root/LensSystem") == null:
		pass_test("LensSystem autoload unavailable")
		return
	for path in ["attack", "power", "magic"]:
		var r: Array = _pair(path, 1000)   # 10% of max_hp, under the 0.25 threshold
		gut.p("    %-6s wounded: bare %d -> arbiter %d" % [path, r[0], r[1]])
		assert_ne(r[1], -1, "CONTROL: the lens must actually equip, or this arm measures nothing")
		assert_gt(r[0], 0, "CONTROL: %s must deal damage at all" % path)
		assert_gt(r[1], r[0],
			"%s ignored the Arbiter Lens — live adds 50%% against a target under the threshold" % path)


## The discriminator. Without this, "the lens always adds damage" would pass just as well.
func test_a_healthy_enemy_is_untouched_by_the_arbiter() -> void:
	if get_node_or_null("/root/LensSystem") == null:
		pass_test("LensSystem autoload unavailable")
		return
	for path in ["attack", "power", "magic"]:
		var r: Array = _pair(path, 9000)   # 90% of max_hp, well above the threshold
		gut.p("    %-6s healthy: bare %d -> arbiter %d" % [path, r[0], r[1]])
		assert_gt(r[0], 0, "CONTROL: %s must deal damage at all" % path)
		assert_eq(r[1], r[0],
			"%s applied the execute bonus to a HEALTHY target — the threshold is not being read" % path)


## The authored numbers are the contract; a rebalance should red this rather than drift silently.
func test_the_bonus_matches_what_the_lens_authors() -> void:
	var ls: Node = get_node_or_null("/root/LensSystem")
	if ls == null:
		pass_test("LensSystem autoload unavailable")
		return
	if not _equip("Arbiter Holder", "arbiter"):
		pass_test("arbiter lens unavailable")
		return
	var me: Dictionary = ls.get_lens_meta_effects(_key("Arbiter Holder"))
	var threshold: float = float(me.get("lens_execute_threshold", 0.0))
	var bonus: float = float(me.get("lens_execute_bonus", 0.0))
	assert_gt(threshold, 0.0, "CONTROL: the arbiter must still author a threshold")
	assert_gt(bonus, 0.0, "CONTROL: the arbiter must still author a bonus")
	## ⛔ ASSERTED ON THE HELPER, NOT ON DEALT DAMAGE. The bonus lands PRE-mitigation and this file's
	## defense formula is quadratic, so the dealt-damage ratio is 1.6 for an authored 1.5 — a real
	## number about the defense curve, not about the lens. My first version pinned that 1.6 and would
	## have red on any defense change while passing a genuinely wrong bonus.
	var attacker := _combatant("Arbiter Holder", 9999)
	var wounded := _combatant("Victim", int(10000 * threshold * 0.5))
	var healthy := _combatant("Healthy", 9000)
	assert_eq(_res._apply_lens_execute_bonus(attacker, wounded, 100), int(100.0 * (1.0 + bonus)),
		"the grind's multiplier drifted from the authored lens_execute_bonus")
	assert_eq(_res._apply_lens_execute_bonus(attacker, healthy, 100), 100,
		"CONTROL: above the threshold the helper must return the damage untouched")
	gut.p("    authored threshold %.2f bonus %.2f -> helper 100 becomes %d"
		% [threshold, bonus, _res._apply_lens_execute_bonus(attacker, wounded, 100)])


## ⚠️ ITS ORIGINAL JOB IS DONE AND IT NOW TESTS SOMETHING WEAKER — SAYING SO RATHER THAN LEAVING THE
## OLD CLAIM IN PLACE. It was written self-arming, while lens_execute_multiplier existed only on
## @cowir-battle's branch, to catch two copies of one authored number drifting apart. The helper
## landed, the arm armed (live x1.50 -> 300), and the grind now DELEGATES to it — so both sides of
## this comparison call one function and the formula can no longer disagree with itself.
## What it still catches is the resolver mis-applying the multiplier it is handed: the int
## truncation and the `mult <= 1.0` early return. That is a real but much smaller claim.
func test_the_grind_agrees_with_lives_multiplier_once_that_helper_exists() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("lens_execute_multiplier"):
		pass_test("live has no lens_execute_multiplier yet — nothing to reconcile")
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		pass_test("GameState autoload unavailable")
		return
	var keep: Dictionary = (gs.lens_assignments as Dictionary).duplicate()
	var attacker := _combatant("Arbiter Holder", 9999)
	if not _equip("Arbiter Holder", "arbiter"):
		gs.lens_assignments = keep
		pass_test("arbiter lens unavailable")
		return
	for hp in [1000, 9000]:
		var target := _combatant("Victim", hp)
		var live_mult: float = float(bm.lens_execute_multiplier(attacker, target))
		var mine: int = _res._apply_lens_execute_bonus(attacker, target, 200)
		gut.p("    hp %d: live x%.2f -> %d, grind -> %d" % [hp, live_mult, int(200.0 * live_mult), mine])
		assert_eq(mine, int(200.0 * live_mult),
			"the grind's execute arithmetic diverged from live's shared helper at hp %d — two copies of one authored number, and they no longer agree" % hp)
	gs.lens_assignments = keep


## Derived from this file's own source: every symbol reached on the resolver must exist on it.
func test_every_resolver_symbol_this_file_reaches_exists() -> void:
	var mine: String = GdSource.code_of(get_script().resource_path)
	assert_gt(mine.length(), 1000, "CONTROL: this test file was actually read")
	var rx := RegEx.new()
	rx.compile("_res\\.([A-Za-z_][A-Za-z0-9_]*)")
	var reached: Dictionary = {}
	for m in rx.search_all(mine):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 2, "CONTROL: the derivation found almost nothing — the regex is stale")
	var probe = ResolverScript.new()
	for sym in reached.keys():
		assert_true(probe.has_method(sym) or sym in probe,
			"this file reaches HeadlessBattleResolver.%s and the resolver no longer has it" % sym)
	gut.p("    floored: %s" % ", ".join(PackedStringArray(reached.keys())))
