extends GutTest

## tick 192: BattleCommandMenu._free_move_hint adds a compact
## effect+scope hint to per-job Free Move labels so the flavor-
## named moves (Channel/Pray/Riff) self-document. Pre-fix the
## menu just showed "Riff" — new players had no idea what it
## did. Now it shows "Riff (MP+ party)" so the scope and
## effect are obvious without reading docs.
##
## Format derived from the underlying ability's `type` +
## `target_type` fields in abilities.json. Fighter/Rogue
## basic_attack labels (Attack/Strike) stay bare — those are
## already self-explanatory in a battle UI.

const BattleCommandMenuRes := preload("res://src/battle/BattleCommandMenu.gd")


func _menu() -> Object:
	# RefCounted; _free_move_hint doesn't touch _scene so null is safe.
	return BattleCommandMenuRes.new(null)


# ── Empty / unknown shapes ─────────────────────────────────────────────

func test_empty_dict_returns_empty_string() -> void:
	var m = _menu()
	assert_eq(m._free_move_hint({}), "",
		"empty ability dict must return empty hint (label stays bare)")


func test_unknown_type_returns_empty_string() -> void:
	var m = _menu()
	assert_eq(m._free_move_hint({"type": "physical", "target_type": "self"}), "",
		"non mp_restore/heal types must return empty hint (no hint for plain damage)")


func test_known_type_no_target_returns_symbol_only() -> void:
	var m = _menu()
	assert_eq(m._free_move_hint({"type": "mp_restore"}), "MP+",
		"known type with no target_type returns just the symbol")


# ── mp_restore (the live Free Move shape) ──────────────────────────────

func test_channel_self_targeting() -> void:
	# Channel (mage): "mp_restore" + "self" → "MP+ self"
	var m = _menu()
	var ability := {"type": "mp_restore", "target_type": "self"}
	assert_eq(m._free_move_hint(ability), "MP+ self",
		"Mage's Channel hint must be 'MP+ self'")


func test_pray_single_ally() -> void:
	# Pray (cleric): "mp_restore" + "single_ally" → "MP+ ally"
	var m = _menu()
	var ability := {"type": "mp_restore", "target_type": "single_ally"}
	assert_eq(m._free_move_hint(ability), "MP+ ally",
		"Cleric's Pray hint must be 'MP+ ally'")


func test_riff_all_allies() -> void:
	# Riff (bard): "mp_restore" + "all_allies" → "MP+ party"
	var m = _menu()
	var ability := {"type": "mp_restore", "target_type": "all_allies"}
	assert_eq(m._free_move_hint(ability), "MP+ party",
		"Bard's Riff hint must be 'MP+ party'")


# ── heal (forward-compat for future Free Moves) ───────────────────────

func test_heal_self() -> void:
	var m = _menu()
	assert_eq(m._free_move_hint({"type": "heal", "target_type": "self"}), "HP+ self",
		"heal+self → HP+ self (forward-compat)")


func test_heal_all_allies() -> void:
	var m = _menu()
	assert_eq(m._free_move_hint({"type": "heal", "target_type": "all_allies"}), "HP+ party",
		"heal+all_allies → HP+ party (forward-compat)")


# ── Integration: _build_free_move_item composes label correctly ────────

func test_build_free_move_item_appends_hint() -> void:
	# Pin: the call-site in _build_free_move_item wraps hint in parens
	# and appends to the label.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_true(src.contains("var ability_data: Dictionary = JobSystem.get_ability(ability_id) if JobSystem else {}"),
		"_build_free_move_item must look up ability data via JobSystem.get_ability")
	assert_true(src.contains("var hint: String = _free_move_hint(ability_data)"),
		"_build_free_move_item must call _free_move_hint helper")
	assert_true(src.contains("item[\"label\"] = (\"%s (%s)\" % [label, hint]) if hint != \"\" else label"),
		"label must wrap hint in parens and skip when hint is empty")


# ── Data integrity: live jobs.json hints resolve cleanly ───────────────

func test_live_job_data_yields_expected_hints() -> void:
	# Pin: the 3 ability-type Free Moves in jobs.json (Channel/Pray/Riff)
	# all resolve to non-empty hints. Catches future ability.json edits
	# that would degrade the menu.
	if not JobSystem:
		pending("JobSystem autoload not available in isolated test")
		return
	var m = _menu()
	var channel: Dictionary = JobSystem.get_ability("channel")
	var pray: Dictionary = JobSystem.get_ability("pray")
	var riff: Dictionary = JobSystem.get_ability("riff")
	if channel.is_empty() or pray.is_empty() or riff.is_empty():
		pending("channel/pray/riff abilities not loaded (likely autoload init order)")
		return
	assert_eq(m._free_move_hint(channel), "MP+ self", "live channel ability hint")
	assert_eq(m._free_move_hint(pray), "MP+ ally", "live pray ability hint")
	assert_eq(m._free_move_hint(riff), "MP+ party", "live riff ability hint")


# ── basic_attack path unchanged (Fighter/Rogue Strike/Attack) ──────────

func test_basic_attack_path_does_not_call_hint_helper() -> void:
	# Negative pin: the basic_attack branch (Fighter/Rogue) MUST NOT
	# wrap its label in the hint format — "Strike (...)" would be
	# noisy for self-explanatory melee.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	# Find _build_free_move_item function body.
	var fn_idx: int = src.find("func _build_free_move_item")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# The basic_attack return path returns a dict with {"label": label}
	# (bare), not formatted with hint.
	assert_true(body.contains("\"label\": label,\n\t\t\t\"data\": null"),
		"basic_attack no-enemy branch returns bare label, no hint format")
	assert_true(body.contains("\"label\": label,\n\t\t\"submenu\": enemy_targets"),
		"basic_attack enemy-submenu branch returns bare label, no hint format")
