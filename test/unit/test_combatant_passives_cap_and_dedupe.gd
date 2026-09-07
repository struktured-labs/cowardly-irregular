extends GutTest

## tick 160 regression: Combatant.from_dict must enforce
## max_passive_slots on equipped_passives AND dedupe both
## equipped + learned passives.
##
## PassiveSystem.equip_passive enforces both checks at write time
## (slot count + "already equipped") but from_dict bypassed them.
## Worst-case silent failures:
##
##   - Saved equipped_passives has 99 entries → all 99 propagate
##     to runtime → multiplicative stat boost stacks 99x past
##     design balance. PassiveSystem.get_passive_mods (used by
##     recalculate_stats) iterates the array.
##
##   - Duplicate entries in equipped_passives → stat multiplier
##     compounds (e.g., 1.2 × 1.2 × 1.2 instead of single 1.2).
##
##   - Duplicate entries in learned_passives → set-membership UI
##     counters drift; "X/N learned" labels show inflated values.

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_equipped_passives_load_enforces_slot_cap() -> void:
	var src := _read(COMBATANT)
	# Pin: the loop breaks once typed_ep.size() >= max_passive_slots.
	assert_true(src.contains("if typed_ep.size() >= max_passive_slots:"),
		"equipped_passives load must enforce max_passive_slots — break after N filled")
	assert_true(src.contains("break"),
		"slot-cap branch must use break (early exit, don't drop later entries silently via continue)")


func test_equipped_passives_load_dedupes() -> void:
	var src := _read(COMBATANT)
	# Pin: dedupe via seen Dictionary.
	# Find the equipped_passives load body.
	var idx: int = src.find("if data.has(\"equipped_passives\"):")
	assert_gt(idx, -1, "equipped_passives load branch must exist")
	# Look for the seen guard within 600 chars.
	var window: String = src.substr(idx, 1200)
	assert_true(window.contains("var seen: Dictionary = {}"),
		"equipped_passives load must build a seen dict for dedupe")
	assert_true(window.contains("if sid == \"\" or seen.has(sid):"),
		"equipped_passives load must skip empty + duplicate ids")


func test_learned_passives_load_dedupes() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"learned_passives\"):")
	assert_gt(idx, -1, "learned_passives load branch must exist")
	var window: String = src.substr(idx, 1200)
	assert_true(window.contains("var seen_lp: Dictionary = {}"),
		"learned_passives load must build a separate seen dict (don't share with equipped)")
	assert_true(window.contains("if sid == \"\" or seen_lp.has(sid):"),
		"learned_passives load must skip empty + duplicate ids")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_99_equipped_caps_at_max_passive_slots() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	# Default max_passive_slots = 5.
	var oversized: Array = []
	for i in 99:
		oversized.append("passive_%d" % i)
	c.from_dict({"equipped_passives": oversized})
	assert_eq(c.equipped_passives.size(), 5,
		"99 equipped passives must cap at max_passive_slots=5")
	# Keep-first semantic: first 5 are passive_0 .. passive_4.
	assert_eq(c.equipped_passives[0], "passive_0",
		"first-N semantic: oldest entry preserved")
	assert_eq(c.equipped_passives[4], "passive_4",
		"first-N semantic: entry 4 preserved")


func test_runtime_duplicate_equipped_passives_dedupe() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"equipped_passives": ["counter", "counter", "evasion", "evasion", "counter"]})
	assert_eq(c.equipped_passives.size(), 2,
		"5 entries with 2 unique must dedupe to 2")
	assert_eq(c.equipped_passives[0], "counter")
	assert_eq(c.equipped_passives[1], "evasion")


func test_runtime_empty_strings_filtered_from_equipped() -> void:
	# Save corruption could have empty strings — must skip them.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"equipped_passives": ["", "counter", "", "evasion", ""]})
	assert_eq(c.equipped_passives.size(), 2,
		"empty strings must be filtered out, not treated as a valid passive id")


func test_runtime_duplicate_learned_passives_dedupe() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"learned_passives": ["counter", "counter", "evasion", "counter"]})
	assert_eq(c.learned_passives.size(), 2,
		"learned_passives must dedupe")
	assert_eq(c.learned_passives[0], "counter")
	assert_eq(c.learned_passives[1], "evasion")


func test_runtime_learned_passives_no_size_cap() -> void:
	# learned has no slot limit (you can know more than you equip).
	# Don't accidentally cap it.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	var many: Array = []
	for i in 30:
		many.append("learned_%d" % i)
	c.from_dict({"learned_passives": many})
	assert_eq(c.learned_passives.size(), 30,
		"learned_passives has NO size cap — all 30 unique entries must survive")


# ── Non-regression ──────────────────────────────────────────────────────

func test_runtime_normal_load_passes_through() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({
		"equipped_passives": ["counter", "evasion", "first_aid"],
		"learned_passives": ["counter", "evasion", "first_aid", "berserk"],
	})
	assert_eq(c.equipped_passives.size(), 3,
		"normal 3-passive equipped load passes through unchanged")
	assert_eq(c.learned_passives.size(), 4,
		"normal 4-passive learned load passes through unchanged")
