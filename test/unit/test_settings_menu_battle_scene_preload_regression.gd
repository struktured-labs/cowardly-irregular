extends GutTest

## Code-quality regression: SettingsMenu's battle-speed save path now
## uses a class-level `const BATTLE_SCENE_SCRIPT := preload(...)`
## instead of a runtime `load("res://src/battle/BattleScene.gd")`.
##
## Matches the SaveSystem.BATTLE_SCENE_SCRIPT pattern (fix tick c17313e)
## — same script, same intent: persist the player's chosen default
## battle speed by writing through to BattleScene._battle_speed_index.
##
## Why this matters:
##   • Preload errors at compile time; load() can fail silently at
##     runtime (resource cache eviction, mid-import race). With load(),
##     the defensive `if BattleSceneScript:` wrapper silently skipped
##     the write — the player's slider move appeared to take effect
##     in the UI but the actual battle scene saw the old default.
##   • Polish #25 in the project's /loop priority queue claims this
##     was "DONE" for SettingsMenu. The code review found that note
##     was premature — _save_battle_speed still used runtime load().
##     This commit ships the fix.
##
## Tests:
##   • Source pin: BATTLE_SCENE_SCRIPT const exists and is a preload
##   • Negative source pin: no runtime load() of BattleScene.gd in
##     non-comment code
##   • Source pin: _save_battle_speed writes through
##     BATTLE_SCENE_SCRIPT (not via a runtime load variable)
##   • Behavioural: a real round trip through _save_battle_speed
##     leaves BattleScene._battle_speed_index pointing at the right
##     preset index

const SETTINGS_MENU_PATH := "res://src/ui/SettingsMenu.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_battle_scene_script_const_exists() -> void:
	var text := _read(SETTINGS_MENU_PATH)
	assert_true(text.contains("const BATTLE_SCENE_SCRIPT := preload(\"res://src/battle/BattleScene.gd\")"),
		"SettingsMenu must declare BATTLE_SCENE_SCRIPT as a preload class const")


func test_no_runtime_load_of_battle_scene() -> void:
	# Pin against regression: a future edit that adds another runtime
	# load("res://src/battle/BattleScene.gd") would defeat the preload.
	# Skip comment lines so the teaching doc above the const can cite
	# the legacy shape without tripping its own lint.
	var text := _read(SETTINGS_MENU_PATH)
	var lines := text.split("\n")
	var needle := "load(\"res://src/battle/BattleScene.gd\")"
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		# Skip the preload const line itself.
		if ln.contains("preload("):
			continue
		assert_false(ln.contains(needle),
			"SettingsMenu must NOT use runtime load() for BattleScene.gd — use BATTLE_SCENE_SCRIPT. Offending line: %s" % ln)


func test_save_battle_speed_writes_through_preload_const() -> void:
	var text := _read(SETTINGS_MENU_PATH)
	var idx := text.find("func _save_battle_speed")
	assert_gt(idx, -1, "_save_battle_speed must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("BATTLE_SCENE_SCRIPT._battle_speed_index ="),
		"_save_battle_speed must write BATTLE_SCENE_SCRIPT._battle_speed_index (not via a runtime load var)")
	# And the legacy local var must NOT appear in non-comment code.
	var lines := body.split("\n")
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		assert_false(ln.contains("var BattleSceneScript = load("),
			"_save_battle_speed must NOT declare a `BattleSceneScript` runtime load var")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_save_battle_speed_roundtrip_updates_battle_scene_static() -> void:
	# End-to-end: call _save_battle_speed on a live SettingsMenu and
	# assert BattleScene._battle_speed_index reflects the index we set.
	var BattleSceneScript := load("res://src/battle/BattleScene.gd")
	var original_idx: int = BattleSceneScript._battle_speed_index
	# Pick a deliberately-different preset index so the assertion is
	# unambiguous. BATTLE_SPEED_PRESETS is [0.25, 0.5, 1.0, 2.0, 4.0].
	var SettingsMenuScript: GDScript = load(SETTINGS_MENU_PATH)
	var menu: SettingsMenu = SettingsMenuScript.new()
	add_child_autofree(menu)
	# Make sure starting index differs from the target.
	var sizes: int = SettingsMenuScript.BATTLE_SPEED_PRESETS.size()
	var test_idx: int = (original_idx + 1) % sizes
	menu.battle_speed_index = test_idx
	menu.battle_speed = SettingsMenuScript.BATTLE_SPEED_PRESETS[test_idx]
	menu._save_battle_speed()
	assert_eq(BattleSceneScript._battle_speed_index, test_idx,
		"after _save_battle_speed, BattleScene._battle_speed_index must reflect the chosen preset")
	# Restore original state so we don't disturb downstream tests.
	BattleSceneScript._battle_speed_index = original_idx
