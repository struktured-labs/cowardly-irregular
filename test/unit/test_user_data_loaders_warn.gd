extends GutTest

## tick 167 regression: user-data JSON loaders (input profiles,
## autobattle profiles) now surface failure modes that pre-fix
## silently fell through. These loaders touch user-authored data
## (custom controller bindings, custom autobattle scripts), so
## silent failures = the player loses their config without any
## hint why.
##
## CutsceneDirector + HybridSpriteLoader audited clean (already
## follow the 4-stage shape with push_error / push_warning).

const INPUT_PROFILE := "res://src/input/InputProfileManager.gd"
const AUTOBATTLE_SYSTEM := "res://src/autobattle/AutobattleSystem.gd"
const CUTSCENE_DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const HYBRID_SPRITE := "res://src/battle/sprites/HybridSpriteLoader.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── InputProfileManager.load_config ─────────────────────────────────────

func test_input_profile_warns_on_file_open_fail() -> void:
	var src := _read(INPUT_PROFILE)
	assert_true(src.contains("push_warning(\"[InputProfileManager] Config exists at %s but FileAccess.open failed"),
		"load_config must warn when FileAccess.open returns null — pre-fix this fell through silently")


func test_input_profile_warns_on_non_dictionary_root() -> void:
	var src := _read(INPUT_PROFILE)
	assert_true(src.contains("push_warning(\"[InputProfileManager] Config parsed but root is not a Dictionary"),
		"load_config must warn when the parsed root is not a Dictionary")


func test_input_profile_existing_parse_warning_preserved() -> void:
	var src := _read(INPUT_PROFILE)
	assert_true(src.contains("push_warning(\"[InputProfileManager] Failed to parse config:"),
		"existing parse-error warning preserved")


func test_input_profile_file_missing_stays_silent() -> void:
	# Deliberately silent for legitimate first-launch state — no
	# config yet to load. Pin to ensure a future overzealous
	# refactor doesn't add a warning here.
	var src := _read(INPUT_PROFILE)
	# Find load_config body.
	var idx: int = src.find("func load_config")
	assert_gt(idx, -1, "load_config must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# The file-missing branch must NOT warn — just return.
	var idx_missing: int = body.find("if not FileAccess.file_exists(CONFIG_PATH):")
	assert_gt(idx_missing, -1, "file-missing branch must exist")
	# Look at next ~120 chars; should NOT contain push_warning before the `return`.
	var window: String = body.substr(idx_missing, 120)
	# Window contains the if + `return`. Verify no push_warning between them.
	var first_return: int = window.find("return")
	assert_gt(first_return, -1, "branch must return")
	var pre_return: String = window.substr(0, first_return)
	assert_false(pre_return.contains("push_warning"),
		"file-missing branch must stay silent — legitimate first-launch state, not an error")


# ── AutobattleSystem profiles load ──────────────────────────────────────

func test_autobattle_warns_on_profiles_file_open_fail() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("push_warning(\"[AutobattleSystem] profiles exists at %s but FileAccess.open failed"),
		"AutobattleSystem profiles load must warn on FileAccess.open failure")


func test_autobattle_warns_on_profiles_parse_fail() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("push_warning(\"[AutobattleSystem] profiles.json parse error"),
		"AutobattleSystem profiles load must warn on parse failure")


func test_autobattle_warns_on_profiles_non_dict_root() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("push_warning(\"[AutobattleSystem] profiles.json parsed but root is not a Dictionary"),
		"AutobattleSystem profiles load must warn on non-Dictionary root")


# ── Audit cross-check: already-clean loaders ────────────────────────────

func test_cutscene_director_keeps_4_stage_pattern() -> void:
	# Audit cross-pin: CutsceneDirector uses push_error (more severe
	# than push_warning since cutscene failures break story flow).
	var src := _read(CUTSCENE_DIRECTOR)
	for fragment in [
		"Cutscene file not found",
		"Failed to open",
		"JSON parse error in",
		"parsed but root is not a Dictionary",
	]:
		assert_true(src.contains(fragment),
			"CutsceneDirector must keep %s warning" % fragment)


func test_hybrid_sprite_loader_keeps_4_stage_pattern() -> void:
	var src := _read(HYBRID_SPRITE)
	for fragment in [
		"[SPRITES] sprite_manifest.json not found",
		"[SPRITES] sprite_manifest.json exists but FileAccess.open failed",
		"[SPRITES] sprite_manifest.json parse error",
		"[SPRITES] sprite_manifest.json parsed but root is not a Dictionary",
	]:
		assert_true(src.contains(fragment),
			"HybridSpriteLoader must keep %s warning" % fragment)


# ── Runtime sanity ──────────────────────────────────────────────────────

func test_runtime_input_profile_loads_after_normal_boot() -> void:
	# Sanity: changes are purely additive on the happy path.
	var ipm = Engine.get_main_loop().root.get_node_or_null("InputProfileManager")
	if ipm != null:
		# active_profile field exists and was populated by load_config
		# during _ready. No specific value pinned (test env may use
		# default; profile may differ in production).
		assert_true("active_profile" in ipm,
			"InputProfileManager must have active_profile field")
