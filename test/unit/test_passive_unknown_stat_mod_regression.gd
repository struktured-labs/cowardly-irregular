extends GutTest

## Crash regression: PassiveSystem.get_passive_mods() crashed when a
## passive's stat_mods introduced a key that wasn't in the accumulator's
## initial defaults dict.
##
## Bug shape:
##   total_mods initialized with 10 fixed keys (attack_multiplier,
##   defense_multiplier, …, crit_chance, evasion). data/passives.json
##   has steal_boost { stat_mods: { steal_chance: 0.3 } } and "steal_chance"
##   is NOT one of the 10. When equip_passive(combatant, "steal_boost")
##   then a get_passive_mods call comes through:
##     total_mods["steal_chance"] += 0.3
##   In Godot 4, Dictionary[missing_key] returns null. `null + float`
##   raises a runtime SCRIPT ERROR. The whole get_passive_mods call
##   aborted, every stat read after equip silently fell back to base
##   stats, and the player saw zero benefit from the passive AND any
##   other equipped passive on the same combatant. Plus an error spam
##   in the console.
##
## Fix: extracted _compose_mod helper that initializes unknown keys
## with the right identity element (1.0 for *_multiplier, 0.0 for
## additive). Now any future passive that introduces a new stat key
## works without code changes.
##
## Tests:
##   • steal_boost (steal_chance) round-trips through get_passive_mods
##     without crashing and produces the expected accumulated value
##   • Mixed party: two passives, one known + one unknown, both compose
##   • Multiplier identity: unknown *_multiplier passive composes via 1.0
##   • Additive identity: unknown additive passive composes via 0.0
##   • Defaults still compose multiplicatively (existing behavior intact)

const PASSIVE_SYSTEM_PATH := "res://src/jobs/PassiveSystem.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func _ps() -> Node:
	return get_node_or_null("/root/PassiveSystem")


# ── Source pins ───────────────────────────────────────────────────────────────

func test_compose_mod_helper_exists() -> void:
	var text := _read(PASSIVE_SYSTEM_PATH)
	assert_gt(text.find("func _compose_mod"), -1,
		"_compose_mod helper must exist to gate the dict access")
	assert_true(text.contains("not total_mods.has(mod_key)"),
		"_compose_mod must guard the missing-key case")


# ── Behavioural: stub combatant + equip steal_boost ──────────────────────────

func _make_combatant() -> Combatant:
	# Minimal Combatant for passive ops — Combatant._ready resets HP/MP
	# after add_child, so set typed fields after.
	var c := Combatant.new()
	c.combatant_name = "TestStealer"
	c.max_hp = 100
	c.max_mp = 50
	c.max_passive_slots = 8
	add_child_autofree(c)
	c.current_hp = 100
	c.current_mp = 50
	# Ensure equipped_passives starts empty (the typed Array[String] is the
	# canonical class default — we just resnap it for test hygiene).
	c.equipped_passives = []
	return c


func test_steal_boost_does_not_crash_get_passive_mods() -> void:
	var ps := _ps()
	if ps == null:
		pending("PassiveSystem autoload unavailable")
		return
	# steal_boost is unrestricted in data/passives.json, so any combatant
	# can equip it. Pre-fix: get_passive_mods crashed because steal_chance
	# isn't in the initial total_mods dict.
	if not ps.passives.has("steal_boost"):
		pending("steal_boost passive not loaded from data/passives.json")
		return
	var c := _make_combatant()
	c.equipped_passives.append("steal_boost")
	var mods: Dictionary = ps.get_passive_mods(c)
	assert_false(mods.is_empty(),
		"get_passive_mods must return a non-empty dict (no crash)")
	assert_true(mods.has("steal_chance"),
		"steal_chance must be present in the returned mods dict")
	assert_almost_eq(float(mods.get("steal_chance", 0.0)), 0.3, 0.0001,
		"steal_boost's +0.3 steal_chance must compose via the 0.0 identity")


func test_mixed_known_and_unknown_passives_both_compose() -> void:
	var ps := _ps()
	if ps == null:
		pending("PassiveSystem autoload unavailable")
		return
	if not ps.passives.has("steal_boost"):
		pending("steal_boost passive not loaded")
		return
	# Find any *_multiplier passive in the data (existing behavior).
	# All starter offensive passives qualify.
	var known_id := ""
	for pid in ps.passives.keys():
		var p: Dictionary = ps.passives[pid]
		var sm: Dictionary = p.get("stat_mods", {})
		if sm.has("attack_multiplier"):
			known_id = pid
			break
	if known_id == "":
		pending("no attack_multiplier passive found in data/passives.json")
		return
	var c := _make_combatant()
	c.equipped_passives.append(known_id)
	c.equipped_passives.append("steal_boost")
	var mods: Dictionary = ps.get_passive_mods(c)
	assert_true(mods.has("attack_multiplier"),
		"known *_multiplier passive must still compose")
	var known_atk: float = float(mods["attack_multiplier"])
	assert_gt(known_atk, 1.0,
		"attack_multiplier must be > 1.0 after equipping the offensive passive")
	assert_true(mods.has("steal_chance"),
		"unknown steal_chance must compose alongside the known multiplier")


# ── Direct helper invariants ────────────────────────────────────────────────

func test_unknown_multiplier_initializes_with_1() -> void:
	var t: Dictionary = {}
	# Static-class call — _compose_mod is a static helper on PassiveSystem.
	# Reach via the class_name lookup path (PassiveSystem is an autoload
	# AND has a class_name).
	var PS := load(PASSIVE_SYSTEM_PATH)
	PS._compose_mod(t, "fire_damage_multiplier", 1.5)
	assert_almost_eq(float(t.get("fire_damage_multiplier", -1.0)), 1.5, 0.0001,
		"unknown *_multiplier must initialize with 1.0 then *= → 1.5")


func test_unknown_additive_initializes_with_0() -> void:
	var t: Dictionary = {}
	var PS := load(PASSIVE_SYSTEM_PATH)
	PS._compose_mod(t, "steal_chance", 0.3)
	assert_almost_eq(float(t.get("steal_chance", -1.0)), 0.3, 0.0001,
		"unknown additive must initialize with 0.0 then += → 0.3")


func test_known_keys_still_compose_as_before() -> void:
	# Identity guards must NOT clobber a key that's already set (regression
	# against a fix that initializes ALWAYS instead of only-when-missing).
	var t: Dictionary = {"attack_multiplier": 2.0}
	var PS := load(PASSIVE_SYSTEM_PATH)
	PS._compose_mod(t, "attack_multiplier", 1.5)
	assert_almost_eq(float(t["attack_multiplier"]), 3.0, 0.0001,
		"existing *_multiplier 2.0 must compose with 1.5 → 3.0 (not be reset to 1.5)")
	t = {"crit_chance": 0.05}
	PS._compose_mod(t, "crit_chance", 0.10)
	assert_almost_eq(float(t["crit_chance"]), 0.15, 0.0001,
		"existing additive 0.05 must compose with 0.10 → 0.15")
