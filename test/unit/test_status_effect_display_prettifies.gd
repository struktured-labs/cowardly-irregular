extends GutTest

## tick 186 regression: status effect display sites now prettify
## multi-word status names. Pre-fix `status.capitalize()` only
## capitalized the first letter — "cannot_act" surfaced as
## "Cannot_act" instead of "Cannot Act". Same class as the
## passive raw-id leaks from tick 185.
##
## Affected multi-word statuses from src/battle/:
##   cannot_act, cannot_defer, permakilled, physical_reflect,
##   prismatic_reflect, magic_block
##
## Sites fixed:
##   - StatusMenu line ~400: equipped status effects list
##   - BattleManager line ~3207: "afflicted with X!" log
##   - BattleManager line ~4932: monster counter-ability log
##     (raw-id fallback prettified for missing-name edge case)
##
## Audit confirmed clean:
##   - BattleScene._refresh_status_icons: uses STATUS_ICON_CONFIG
##     with substr(0,3).to_upper() fallback (compact, fine) ✓
##   - BattleCommandMenu element badges: defensive
##     ELEMENT_COLORS.get / ELEMENT_SYMBOLS.get with sensible
##     defaults ✓
##   - BattleManager direct ability["name"] accesses guarded by
##     prior is_empty check at line 2649 ✓

const STATUS_MENU := "res://src/ui/StatusMenu.gd"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── StatusMenu status effect list ──────────────────────────────────────

func test_status_menu_prettifies_multi_word_status_names() -> void:
	# Tick 215 extracted to shared StatusNames util — the helper
	# now produces the same output but routes through one source.
	var src := _read(STATUS_MENU)
	assert_true(src.contains("status_label.text = \"- %s\" % StatusNames.display(status)"),
		"StatusMenu status_effects loop must call StatusNames.display(status)")
	# Negative: simple capitalize() alone is gone.
	assert_false(src.contains("status_label.text = \"- %s\" % status.capitalize()"),
		"bare capitalize() must not be the call site (use StatusNames.display)")


# ── BattleManager "afflicted with" log ─────────────────────────────────

func test_afflicted_with_log_prettifies_effect_name() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("%s is afflicted with %s![/color]\" % [target.combatant_name, effect.replace(\"_\", \" \").capitalize()]"),
		"'afflicted with' log must prettify effect name (multi-word: physical_reflect, etc.)")


func test_afflicted_log_no_longer_uses_raw_effect() -> void:
	# Negative pin: the raw `effect` interpolation without prettifier
	# must be gone from the afflicted-with log.
	var src := _read(BATTLE_MANAGER)
	assert_false(src.contains("is afflicted with %s![/color]\" % [target.combatant_name, effect]"),
		"raw `effect` interpolation without prettifier must be gone")


# ── BattleManager monster counter log ──────────────────────────────────

func test_monster_counter_log_prettifies_id_fallback() -> void:
	var src := _read(BATTLE_MANAGER)
	# The new prettifier fallback for missing-name edge case.
	assert_true(src.contains("ability.get(\"name\", ability_id.replace(\"_\", \" \").capitalize())"),
		"monster counter log's missing-name fallback must use prettifier")
	# Negative: old raw ability_id fallback gone.
	assert_false(src.contains("counters with %s![/color]\" % [monster.combatant_name, ability.get(\"name\", ability_id)]"),
		"old raw `ability.get('name', ability_id)` fallback must be gone")


# ── Cross-pins: clean fallback sites preserved ─────────────────────────

func test_battle_scene_status_icon_default_preserved() -> void:
	# BattleScene's status icon fallback uses substr(0,3).to_upper
	# for compact display. Pin to ensure it stays defensive.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(src.contains("STATUS_ICON_CONFIG.get(status, {\"label\": status.substr(0, 3).to_upper()"),
		"BattleScene status icon fallback (3-char abbreviation) preserved")


func test_element_badge_uses_defensive_defaults() -> void:
	# BattleCommandMenu element badge uses ELEMENT_COLORS.get with
	# gray default + ELEMENT_SYMBOLS.get with "?" fallback.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_true(src.contains("ELEMENT_COLORS.get(element, Color(0.7, 0.7, 0.7))"),
		"element color defensive default preserved")
	assert_true(src.contains("ELEMENT_SYMBOLS.get(element, \"?\")"),
		"element symbol defensive '?' fallback preserved")


func test_ability_direct_name_access_guarded_by_is_empty() -> void:
	# Pin the safety contract: direct `ability["name"]` accesses
	# in _execute_ability are protected by the is_empty check at
	# line ~2649. Pin both the guard and at least one access.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("if ability.is_empty():"),
		"is_empty guard preserves the safety contract for direct ability['name'] accesses")
	assert_true(src.contains("[color=white]%s[/color] uses [color=aqua]%s[/color]!"),
		"X uses Y! announce log preserved (uses ability['name'] under the guard)")
