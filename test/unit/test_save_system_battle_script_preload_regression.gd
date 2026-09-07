extends GutTest

## Code-quality regression: SaveSystem's settings save/load path used two
## runtime `load("res://src/battle/BattleScene.gd")` calls (one per direction).
## Promoted to a single `const BATTLE_SCENE_SCRIPT := preload(...)` class
## constant. Benefits:
##   • One resource-cache hit at script load time, not two per session.
##   • Removes a defensive `if BattleSceneScript else` fallback the previous
##     code carried for the "load() returned null" edge case — preload errors
##     at compile time, not at runtime.
##   • Fixes a stale comment that referenced "line 577" for a load() call
##     that actually lived elsewhere.
##
## Tests:
##   • Source-pin that the preload constant exists and is used at every
##     settings save/load call site (no surviving runtime load() of
##     BattleScene.gd in SaveSystem).
##   • Behavioral roundtrip: save_settings() then load_settings() restores
##     the battle_speed_index, proving the preload path actually works.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ────────────────────────────────────────────────────────────────

func test_battle_scene_preload_const_exists() -> void:
	var text := _read(SAVE_SYSTEM_PATH)
	assert_true(text.contains("const BATTLE_SCENE_SCRIPT"),
		"SaveSystem must declare a BATTLE_SCENE_SCRIPT const")
	assert_true(text.contains("preload(\"res://src/battle/BattleScene.gd\")"),
		"BATTLE_SCENE_SCRIPT must be a preload (not a runtime load)")


func test_no_runtime_load_of_battle_scene_in_settings_path() -> void:
	# Pin against regression: a future edit that adds another runtime load
	# of BattleScene.gd would defeat the preload const. Skip lines that are
	# comments — the const's own teaching doc comment cites the old pattern
	# verbatim so future readers know what was replaced.
	var text := _read(SAVE_SYSTEM_PATH)
	var lines := text.split("\n")
	var bad: PackedStringArray = PackedStringArray()
	for i in lines.size():
		var line: String = lines[i]
		if line.strip_edges().begins_with("#"):
			continue
		var needle := "load(\"res://src/battle/BattleScene.gd\")"
		var n_idx := line.find(needle)
		if n_idx == -1:
			continue
		# Allow `preload("res://...")` — the const declaration. Only flag
		# a bare runtime `load(...)`. The preload form is `preload("..."` —
		# i.e. the char before `load` is `e` (from "preload").
		if n_idx > 0 and line.substr(n_idx - 3, 3) == "pre":
			continue
		bad.append("  line %d: %s" % [i + 1, line])
	assert_eq(bad.size(), 0,
		"SaveSystem must NOT use runtime load() for BattleScene.gd — use the BATTLE_SCENE_SCRIPT const. Offending lines:\n" + "\n".join(bad))


func test_save_and_load_settings_reference_the_const() -> void:
	# Pin both call sites — without explicit pins, a partial revert could
	# leave one path on the const and the other reverted to runtime load.
	var text := _read(SAVE_SYSTEM_PATH)
	var save_idx := text.find("func save_settings")
	assert_gt(save_idx, -1, "save_settings must exist")
	var load_idx := text.find("func load_settings")
	assert_gt(load_idx, -1, "load_settings must exist")
	var save_body := text.substr(save_idx, load_idx - save_idx)
	# load_settings runs to end of the file or next func.
	var load_rest := text.substr(load_idx)
	var next_fn := load_rest.find("\nfunc ", 1)
	var load_body := load_rest.substr(0, next_fn) if next_fn > -1 else load_rest
	assert_true(save_body.contains("BATTLE_SCENE_SCRIPT"),
		"save_settings must use BATTLE_SCENE_SCRIPT")
	assert_true(load_body.contains("BATTLE_SCENE_SCRIPT"),
		"load_settings must use BATTLE_SCENE_SCRIPT")


# ── Behavioural roundtrip ──────────────────────────────────────────────────────

func test_settings_roundtrip_preserves_battle_speed_index() -> void:
	# Hit the live autoload — exercises the preload path end-to-end.
	var ss := get_node_or_null("/root/SaveSystem")
	assert_not_null(ss, "SaveSystem autoload must be reachable")
	# Preserve original state so we don't pollute the running session.
	var BattleSceneScript := load("res://src/battle/BattleScene.gd")
	var original_idx: int = BattleSceneScript._battle_speed_index
	# Also snapshot settings.json so a real on-disk settings file isn't
	# overwritten with a test-driven value if the harness happens to have one.
	var settings_path := "user://settings.json"
	var prior_settings := ""
	if FileAccess.file_exists(settings_path):
		var f := FileAccess.open(settings_path, FileAccess.READ)
		if f != null:
			prior_settings = f.get_as_text()
			f.close()

	# Pick an idx that's definitely in range (0..size-1) but distinct
	# from the default so the assertion is non-trivial.
	var sizes: int = BattleSceneScript.BATTLE_SPEEDS.size()
	assert_gt(sizes, 1, "BATTLE_SPEEDS must have at least 2 entries to test")
	var test_idx: int = (original_idx + 1) % sizes

	BattleSceneScript._battle_speed_index = test_idx
	ss.save_settings()
	# Reset to a different value so load_settings has work to do.
	BattleSceneScript._battle_speed_index = (test_idx + 1) % sizes
	ss.load_settings()
	assert_eq(BattleSceneScript._battle_speed_index, test_idx,
		"load_settings must restore battle_speed_index from disk via the preload const")

	# Restore original state.
	BattleSceneScript._battle_speed_index = original_idx
	if prior_settings != "":
		var f2 := FileAccess.open(settings_path, FileAccess.WRITE)
		if f2 != null:
			f2.store_string(prior_settings)
			f2.close()
	# Reload so the autoload's in-memory state matches whatever was on
	# disk before the test ran.
	ss.load_settings()
	BattleSceneScript._battle_speed_index = original_idx
