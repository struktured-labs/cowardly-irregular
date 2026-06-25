extends GutTest

## tick 166 regression: extends tick 165's JSON-loader audit to
## the remaining boot-path loaders.
##
## Loaders covered this round:
##   - ItemSystem._load_item_data (gap: FileAccess.open-fail silent)
##   - SoundManager._load_sfx_manifest (all 3 failure modes silent
##     pre-fix — no file warn, no open-fail warn, no parse-fail
##     warn, no "missing 'sfx' key" warn)
##   - SoundManager._load_music_manifest (conflated parse-fail +
##     root-type + missing 'tracks' into one warning)
##
## EncounterSystem audit clean (already follows the 4-stage shape
## for BOTH enemy_pools and monsters loaders).

const ITEM_SYSTEM := "res://src/items/ItemSystem.gd"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const ENCOUNTER_SYSTEM := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── ItemSystem ──────────────────────────────────────────────────────────

func test_item_system_warns_on_file_open_fail() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("push_warning(\"[ItemSystem] items.json exists but FileAccess.open failed"),
		"ItemSystem must push_warning when FileAccess.open returns null — pre-fix this fell through silently to _create_default_items")


func test_item_system_existing_warnings_preserved() -> void:
	var src := _read(ITEM_SYSTEM)
	# Don't accidentally drop the pre-existing warnings.
	assert_true(src.contains("push_warning(\"[ItemSystem] items.json not found"),
		"existing file-not-found warning preserved")
	assert_true(src.contains("push_warning(\"[ItemSystem] items.json parse error"),
		"existing parse-error warning preserved")
	assert_true(src.contains("push_warning(\"[ItemSystem] items.json parsed but root is not a Dictionary"),
		"existing root-type warning preserved")


# ── SoundManager SFX manifest ───────────────────────────────────────────

func test_sfx_loader_warns_on_file_missing() -> void:
	var src := _read(SOUND_MANAGER)
	assert_true(src.contains("push_warning(\"[SFX] sfx_manifest.json not found"),
		"_load_sfx_manifest must warn when the file is missing — pre-fix this fell through silently")


func test_sfx_loader_warns_on_file_open_fail() -> void:
	var src := _read(SOUND_MANAGER)
	assert_true(src.contains("push_warning(\"[SFX] sfx_manifest.json exists but FileAccess.open failed"),
		"_load_sfx_manifest must warn when FileAccess.open returns null")


func test_sfx_loader_warns_on_parse_fail() -> void:
	var src := _read(SOUND_MANAGER)
	assert_true(src.contains("push_warning(\"[SFX] sfx_manifest.json parse error"),
		"_load_sfx_manifest must warn on parse failure")


func test_sfx_loader_warns_on_root_type_mismatch() -> void:
	var src := _read(SOUND_MANAGER)
	assert_true(src.contains("push_warning(\"[SFX] sfx_manifest.json parsed but root is not a Dictionary"),
		"_load_sfx_manifest must warn when root is not a Dictionary")


func test_sfx_loader_warns_on_missing_sfx_key() -> void:
	var src := _read(SOUND_MANAGER)
	assert_true(src.contains("push_warning(\"[SFX] sfx_manifest.json parsed but missing 'sfx' key"),
		"_load_sfx_manifest must warn when the 'sfx' key is missing (was silent — manifest stays empty)")


# ── SoundManager Music manifest ─────────────────────────────────────────

func test_music_loader_distinguishes_parse_vs_type_vs_missing_key() -> void:
	# Pre-fix the conflated `else: push_warning("Failed to parse")`
	# fired for parse failure AND root-type mismatch AND missing
	# 'tracks' key — devs couldn't tell which was the real cause.
	var src := _read(SOUND_MANAGER)
	assert_true(src.contains("push_warning(\"[MUSIC] music_manifest.json parse error"),
		"music loader must have a DISTINCT parse-error warning (was conflated pre-tick-166)")
	assert_true(src.contains("push_warning(\"[MUSIC] music_manifest.json parsed but root is not a Dictionary"),
		"music loader must have a DISTINCT root-type warning")
	assert_true(src.contains("push_warning(\"[MUSIC] music_manifest.json parsed but missing 'tracks' key"),
		"music loader must have a DISTINCT missing-tracks-key warning")
	# Pre-existing file-open warning preserved.
	assert_true(src.contains("push_warning(\"[MUSIC] Cannot open music_manifest.json"),
		"existing file-open warning preserved")


# ── EncounterSystem audit pin ───────────────────────────────────────────

func test_encounter_system_keeps_canonical_4_stage_warnings() -> void:
	# EncounterSystem audit clean — already had the full 4-stage
	# pattern for BOTH loaders. Pin all 8 warnings so a future
	# refactor doesn't accidentally regress them.
	var src := _read(ENCOUNTER_SYSTEM)
	for fragment in [
		"enemy_pools.json not found",
		"enemy_pools.json exists but FileAccess.open failed",
		"enemy_pools.json parse error",
		"enemy_pools.json parsed but root is not a Dictionary",
		"monsters.json not found",
		"monsters.json exists but FileAccess.open failed",
		"monsters.json parse error",
		"monsters.json parsed but root is not a Dictionary",
	]:
		assert_true(src.contains(fragment),
			"EncounterSystem must keep warning fragment: %s" % fragment)


# ── Runtime sanity: loaders still produce non-empty data ────────────────

func test_runtime_loaders_populated_after_normal_boot() -> void:
	# Changes should be purely additive (new warnings on failure
	# paths). Happy path unchanged.
	var is_sys = Engine.get_main_loop().root.get_node_or_null("ItemSystem")
	if is_sys != null:
		assert_gt(int(is_sys.items.size()), 0,
			"ItemSystem.items must be populated after normal boot")
	var es = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	if es != null:
		assert_gt(int(es.monster_database.size()), 0,
			"EncounterSystem.monster_database must be populated after normal boot")
