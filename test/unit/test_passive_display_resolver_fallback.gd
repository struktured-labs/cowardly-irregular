extends GutTest

## tick 185 regression: 4 passive-display sites now prettify the
## raw-id fallback (snake_case → Title Case). Pre-fix unknown
## passives surfaced as raw IDs like "counter_attack" instead
## of "Counter Attack".
##
## Affected sites:
##   - MenuScene line ~362: party status passives list
##   - MenuScene line ~858: equipped slots in customize view
##   - MenuScene line ~887: available-to-equip list
##   - StatusMenu line ~368: status menu passives section
##
## Same prettifier pattern as tick 141's JobMenu / tick 140's
## EquipmentMenu / tick 184's MenuScene equipment+items.
##
## Audit results for other getters confirmed clean:
##   - JobSystem.get_job in JobMenu: tick 141 prettifier ✓
##   - JobSystem.get_ability in MenuScene: defensive `if not
##     ability: continue/return` ✓
##   - JobSystem.get_ability in AutobattleGridEditor: guard with
##     is_empty before access ✓
##   - JobSystem.get_ability in GameLoop: defensive prettifier
##     default ✓
##   - PassiveSystem.get_passive in AbilitiesMenu: iterates
##     known keys, no leak ✓
##   - BestiarySystem.get_monster_data in ItemSystem: defensive
##     `.get("undead", false)` ✓

const MENU_SCENE := "res://src/ui/MenuScene.gd"
const STATUS_MENU := "res://src/ui/StatusMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── MenuScene passive sites ────────────────────────────────────────────

func test_menu_scene_party_passives_list_prettifies() -> void:
	# Pin: the equipped_passives loop at ~line 362 uses the
	# replace+capitalize prettifier.
	var src := _read(MENU_SCENE)
	# Pin the prettifier expression in the same context as
	# PassiveSystem.get_passive — narrow the window with a
	# distinctive nearby string.
	var anchor: int = src.find("for passive_id in member.equipped_passives:")
	assert_gt(anchor, -1, "equipped_passives loop must exist in MenuScene")
	var window: String = src.substr(anchor, 700)
	assert_true(window.contains("passive_id.replace(\"_\", \" \").capitalize()"),
		"party passives list must use the prettifier fallback")


func test_menu_scene_equipped_slot_buttons_prettify() -> void:
	# Pin: line ~858 (equipped passive slot buttons).
	var src := _read(MENU_SCENE)
	# Anchor: distinct slot_row.add_child(btn) line preceded by
	# passive.get name.
	var anchor: int = src.find("if i < member.equipped_passives.size():")
	assert_gt(anchor, -1, "equipped passive slot loop must exist")
	var window: String = src.substr(anchor, 500)
	assert_true(window.contains("passive_id.replace(\"_\", \" \").capitalize()"),
		"equipped slot buttons must use prettifier fallback")


func test_menu_scene_available_passives_prettify() -> void:
	# Pin: line ~887 (available-to-equip list).
	var src := _read(MENU_SCENE)
	var anchor: int = src.find("if passive_id in member.equipped_passives:")
	assert_gt(anchor, -1, "available passives loop must exist")
	var window: String = src.substr(anchor, 500)
	assert_true(window.contains("passive_id.replace(\"_\", \" \").capitalize()"),
		"available passives list must use prettifier fallback")


# ── StatusMenu passive site ────────────────────────────────────────────

func test_status_menu_passive_label_prettifies() -> void:
	var src := _read(STATUS_MENU)
	# Pin: equipped_passives loop uses prettifier on the
	# passive_id fallback.
	assert_true(src.contains("passive_data.get(\"name\", passive_id.replace(\"_\", \" \").capitalize())"),
		"StatusMenu equipped_passives loop must use prettifier fallback")


# ── Negative pins: old raw-id fallbacks gone ───────────────────────────

func test_old_raw_passive_id_fallbacks_gone_in_menu_scene() -> void:
	var src := _read(MENU_SCENE)
	# Negative: simple `passive_id` raw fallback patterns gone.
	# We can't grep `passive_id` alone (legitimate uses everywhere),
	# but the specific raw `if passive else passive_id` shape is
	# gone.
	assert_false(src.contains("if passive else passive_id\n"),
		"raw `if passive else passive_id` shape must be gone")


func test_old_raw_passive_id_fallback_gone_in_status_menu() -> void:
	var src := _read(STATUS_MENU)
	# Negative pin: the specific `passive_data.get("name", passive_id)`
	# raw form must be gone.
	assert_false(src.contains("passive_data.get(\"name\", passive_id)\n"),
		"raw `passive_data.get('name', passive_id)` must be replaced with prettifier")


# ── Cross-pins: clean callers preserved ────────────────────────────────

func test_job_menu_prettifier_preserved() -> void:
	var src := _read("res://src/ui/JobMenu.gd")
	assert_true(src.contains("character.secondary_job_id.replace(\"_\", \" \").capitalize()"),
		"tick 141 JobMenu prettifier preserved")


func test_abilities_menu_iteration_pattern_preserved() -> void:
	var src := _read("res://src/ui/AbilitiesMenu.gd")
	# Iterates known PassiveSystem.passives keys — no leak.
	assert_true(src.contains("for passive_id in PassiveSystem.passives:"),
		"AbilitiesMenu iterates known passive keys (no fallback needed)")


func test_game_loop_defensive_pattern_preserved() -> void:
	var src := _read("res://src/GameLoop.gd")
	# Defensive: prettifier as default, canonical overrides if
	# get_ability returns non-empty with "name" key.
	assert_true(src.contains("var ability_name: String = ability_id.replace(\"_\", \" \").capitalize()"),
		"GameLoop's defensive prettifier default preserved")
