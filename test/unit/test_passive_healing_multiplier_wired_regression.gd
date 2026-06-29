extends GutTest

## tick 373: passive `healing_boost` (data/passives.json with
## healing_multiplier=1.5) now actually scales healing.
##
## Pre-fix:
##   - PassiveSystem.get_passive_mods accumulated healing_multiplier
##     into the total_mods dict (default 1.0).
##   - Combatant.heal() applied game_constants["healing_multiplier"]
##     (Scriptweaver knob) but never read the passive's value.
##   - Players equipped `healing_boost` seeing "+50% healing" in
##     the description and got nothing — a silent design failure
##     identical in spirit to the buff-consumables-do-nothing bug
##     (tick refs in test_item_buff_and_effect_handler_regression).
##
## Post-fix Combatant.heal() also reads PassiveSystem.get_passive_mods's
## healing_multiplier, clamped to the same [0.1, 10.0] band as the
## game_constants read so a broken passive can't black-hole healing.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make_combatant(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


# ── Source pin: heal() reads PassiveSystem's healing_multiplier ─────

func test_heal_reads_passive_healing_multiplier() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func heal(amount: int)")
	assert_gt(fn_idx, -1, "heal must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("PassiveSystem"),
		"heal() must consult PassiveSystem for the healing_multiplier")
	assert_true(body.contains("passive_mods.get(\"healing_multiplier\""),
		"heal() must read healing_multiplier from passive_mods (was unused pre-fix)")
	# Defensive clamp must match the game_constants band.
	assert_true(body.contains("0.1, 10.0)"),
		"passive healing_multiplier must clamp to [0.1, 10.0] (parity with game_constants read)")


# ── Behavioral: heal(50) with healing_boost equipped scales up ──────

func test_healing_boost_passive_actually_scales() -> void:
	# Don't simulate PassiveSystem from scratch — exercise the autoload
	# directly so we test the real wiring. PassiveSystem reads
	# data/passives.json at _ready.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required for this test")
		return
	if not ps.passives.has("healing_boost"):
		pending("data/passives.json must include healing_boost (was the whole point of this regression)")
		return
	# Verify the passive data itself has the multiplier we're testing.
	var passive_def: Dictionary = ps.passives.get("healing_boost", {})
	var stat_mods: Dictionary = passive_def.get("stat_mods", {})
	assert_eq(stat_mods.get("healing_multiplier", 1.0), 1.5,
		"healing_boost passive data must define healing_multiplier=1.5 — bedrock for the fix")

	var c: Combatant = _make_combatant("Hero")
	c.current_hp = 10  # max_hp = 100
	# Equip the passive directly (bypassing slot-limit checks in equip_passive).
	c.equipped_passives = ["healing_boost"]
	var healed: int = c.heal(40)
	# Pre-fix: 40. Post-fix: 40 * 1.5 = 60.
	assert_eq(healed, 60,
		"heal(40) with healing_boost (1.5x) must heal 60, not 40 — pre-fix the passive was a silent no-op")
	assert_eq(c.current_hp, 70,
		"current_hp must be 10 (start) + 60 (boosted heal) = 70")


# ── Behavioral: heal() without the passive is unchanged ─────────────

func test_heal_without_passive_unchanged() -> void:
	# Regression guard: the fix must NOT change healing for combatants
	# who haven't equipped healing_boost (no silent buff to everyone).
	var c: Combatant = _make_combatant("Hero")
	c.current_hp = 10
	# Explicitly clear passives.
	c.equipped_passives = []
	var healed: int = c.heal(40)
	assert_eq(healed, 40,
		"heal(40) with no passives must still heal 40 — fix must not silently buff baseline")


# ── Source pin: clamp protects against runaway passive multipliers ──

func test_passive_heal_mult_clamped_to_safe_band() -> void:
	# Verify the clamp value is sane — a typo'd passive with
	# healing_multiplier=999.0 must NOT actually 999x heal.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required for this test")
		return
	# Temporarily inject a corrupt passive — we'll restore after.
	var prior_has: bool = ps.passives.has("__tick373_test_corrupt__")
	var prior_def: Dictionary = ps.passives.get("__tick373_test_corrupt__", {})
	ps.passives["__tick373_test_corrupt__"] = {
		"name": "Test Corrupt",
		"stat_mods": {"healing_multiplier": 999.0}
	}

	var c: Combatant = _make_combatant("Hero")
	c.current_hp = 1  # max 100 so all 100 max heal possible
	c.max_hp = 1000  # large max so clamp test isn't masked by max cap
	c.current_hp = 1
	c.equipped_passives = ["__tick373_test_corrupt__"]
	var healed: int = c.heal(10)
	# Pre-clamp would be 10 * 999 = 9990; post-clamp must be 10 * 10 = 100.
	assert_true(healed <= 100,
		"healing_multiplier=999.0 must clamp to 10x ceiling — pre-clamp would heal 9990, post-clamp at most 100 (got %d)" % healed)

	# Restore.
	if prior_has:
		ps.passives["__tick373_test_corrupt__"] = prior_def
	else:
		ps.passives.erase("__tick373_test_corrupt__")
