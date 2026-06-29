extends GutTest

## tick 377: PassiveSystem.get_passive_mods now parses conditional_mods
## keys generically — hp_below_<N> / hp_above_<N> / mp_below_<N> /
## mp_above_<N> for any int N — instead of only recognizing the
## hardcoded "hp_below_25" key.
##
## Pre-fix:
##   if passive["conditional_mods"].has("hp_below_25") and hp_pct < 0.25:
##       ...
##
## Only the literal "hp_below_25" key fired. A future passive author
## writing `hp_below_50` or `mp_below_30` or `hp_above_75` got
## silently no-op'd — same silent-failure class that ticks 373-376
## fixed across other PassiveSystem mod consumers.
##
## Post-fix parses the key as `<stat>_<comparator>_<threshold_int>`,
## stat ∈ {hp, mp}, comparator ∈ {below, above}, threshold ∈ [0, 100].
## Unknown shapes silently skip (preserves old contract: typo'd keys
## stay no-op rather than throwing).

const PASSIVE_SYSTEM_PATH := "res://src/jobs/PassiveSystem.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: hardcoded hp_below_25 check removed ─────────────────

func test_hardcoded_hp_below_25_check_removed() -> void:
	var src := _read(PASSIVE_SYSTEM_PATH)
	# The original code line was:
	#   if passive["conditional_mods"].has("hp_below_25") and hp_pct < 0.25:
	# That hardcoded literal must be gone.
	assert_false(src.contains(".has(\"hp_below_25\") and hp_pct < 0.25"),
		"hardcoded `.has(\"hp_below_25\") and hp_pct < 0.25` line must be removed")


# ── Source pin: generic parser helper exists ────────────────────────

func test_conditional_key_parser_exists() -> void:
	var src := _read(PASSIVE_SYSTEM_PATH)
	assert_true(src.contains("func _conditional_key_satisfied"),
		"PassiveSystem must expose _conditional_key_satisfied helper")
	# Pin parsing for both stat / comparator shapes.
	assert_true(src.contains("\"below\":"),
		"parser must handle 'below' comparator")
	assert_true(src.contains("\"above\":"),
		"parser must handle 'above' comparator")
	assert_true(src.contains("\"hp\":"),
		"parser must handle 'hp' stat")
	assert_true(src.contains("\"mp\":"),
		"parser must handle 'mp' stat")


# ── Source pin: loop over conditional_mods keys instead of one ──────

func test_loop_over_conditional_mods_keys() -> void:
	var src := _read(PASSIVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func get_passive_mods")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("for cond_key in passive[\"conditional_mods\"].keys()"),
		"get_passive_mods must iterate ALL conditional_mods keys (not just hp_below_25)")
	assert_true(body.contains("_conditional_key_satisfied"),
		"get_passive_mods must route through the parser helper")


# ── Behavioral: parser recognizes hp_below_25 (backward compat) ─────

func test_parser_recognizes_hp_below_25() -> void:
	var script: GDScript = load(PASSIVE_SYSTEM_PATH)
	# Static helper — call directly on the script.
	assert_true(script._conditional_key_satisfied("hp_below_25", 0.20, 1.0),
		"hp_below_25 must satisfy when hp_pct=0.20 (below threshold)")
	assert_false(script._conditional_key_satisfied("hp_below_25", 0.50, 1.0),
		"hp_below_25 must NOT satisfy when hp_pct=0.50 (above threshold)")


# ── Behavioral: parser recognizes hp_below_50 (the new case) ────────

func test_parser_recognizes_hp_below_50() -> void:
	var script: GDScript = load(PASSIVE_SYSTEM_PATH)
	# Pre-fix this key was silently ignored — pin the new behavior.
	assert_true(script._conditional_key_satisfied("hp_below_50", 0.40, 1.0),
		"hp_below_50 must satisfy when hp_pct=0.40")
	assert_false(script._conditional_key_satisfied("hp_below_50", 0.60, 1.0),
		"hp_below_50 must NOT satisfy when hp_pct=0.60")


# ── Behavioral: parser recognizes hp_above_75 (inverse) ─────────────

func test_parser_recognizes_hp_above_75() -> void:
	var script: GDScript = load(PASSIVE_SYSTEM_PATH)
	assert_true(script._conditional_key_satisfied("hp_above_75", 0.90, 1.0),
		"hp_above_75 must satisfy when hp_pct=0.90")
	assert_false(script._conditional_key_satisfied("hp_above_75", 0.50, 1.0),
		"hp_above_75 must NOT satisfy when hp_pct=0.50")


# ── Behavioral: parser recognizes mp_below_<N> ──────────────────────

func test_parser_recognizes_mp_below() -> void:
	var script: GDScript = load(PASSIVE_SYSTEM_PATH)
	assert_true(script._conditional_key_satisfied("mp_below_30", 1.0, 0.20),
		"mp_below_30 must satisfy when mp_pct=0.20")
	assert_false(script._conditional_key_satisfied("mp_below_30", 1.0, 0.80),
		"mp_below_30 must NOT satisfy when mp_pct=0.80")


# ── Behavioral: parser rejects bogus shapes ─────────────────────────

func test_parser_rejects_bogus_shapes() -> void:
	var script: GDScript = load(PASSIVE_SYSTEM_PATH)
	# Unknown stat.
	assert_false(script._conditional_key_satisfied("ap_below_50", 0.5, 0.5),
		"unknown stat (ap) must NOT satisfy — silent skip preserves old contract")
	# Unknown comparator.
	assert_false(script._conditional_key_satisfied("hp_equal_50", 0.5, 0.5),
		"unknown comparator (equal) must NOT satisfy")
	# Non-numeric threshold.
	assert_false(script._conditional_key_satisfied("hp_below_low", 0.5, 0.5),
		"non-numeric threshold must NOT satisfy")
	# Wrong arity.
	assert_false(script._conditional_key_satisfied("hp_below", 0.5, 0.5),
		"two-part key must NOT satisfy")
	assert_false(script._conditional_key_satisfied("", 0.5, 0.5),
		"empty key must NOT satisfy")


# ── Behavioral: end-to-end Last Stand still works (regression guard)

func test_last_stand_still_fires() -> void:
	# Pin that the canonical pre-existing user of conditional_mods
	# (Last Stand, hp_below_25 → +200% attack/magic) still works.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("last_stand"):
		pending("data/passives.json must include last_stand (existing canonical user)")
		return

	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Hero", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	c.equipped_passives = ["last_stand"]
	# Force HP below 25%.
	c.current_hp = 20
	var mods: Dictionary = ps.get_passive_mods(c)
	assert_gt(float(mods.get("attack_multiplier", 1.0)), 1.0,
		"Last Stand must still amplify attack when HP < 25% — regression guard")
	# Above 25% the conditional must NOT fire.
	c.current_hp = 80
	mods = ps.get_passive_mods(c)
	# attack_multiplier should be 1.0 (no conditional fired); last_stand
	# also has stat_mods.max_hp_multiplier=0.8 which doesn't affect attack.
	assert_almost_eq(float(mods.get("attack_multiplier", 1.0)), 1.0, 0.001,
		"Last Stand must NOT amplify attack when HP > 25%")
