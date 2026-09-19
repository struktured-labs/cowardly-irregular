extends GutTest

## tick 223: extracts the text-scale logic from CutsceneDialogue
## (tick 222) to a shared TextScale util, then refactors
## PartyStatusScreen + StatusMenu to use it. 41 font_size sites
## across the two menus now scale with the accessibility setting.
##
## CutsceneDialogue's local _scaled_font_size now delegates to
## TextScale.scaled — single source of truth across the codebase.

const TEXT_SCALE := "res://src/ui/TextScale.gd"
const PARTY_STATUS := "res://src/ui/PartyStatusScreen.gd"
const STATUS_MENU := "res://src/ui/StatusMenu.gd"
const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"


## ⛔ `GameState.text_size_scale` IS A SHARED AUTOLOAD FIELD AND THE ARMS BELOW MOVE IT, RESTORING
## INLINE AT THE END OF EACH ARM. A GDScript error above the restore strands the moved value for
## every later file in the process.
##
## 🔑 PRODUCED, AND THE PLACEMENT IS THE MEASUREMENT: an abort above the FIRST reset produces
## nothing, because a later arm resets it anyway — this file heals itself right up until its LAST
## touch. Abort above the last reset in `test_text_scale_util_extraction`:
##	 text_size_scale left at 0.8, and the file reported EC=0 · Passing 16.
## Silent, and every later file then renders at that scale.
##
## 📌 The catcher's baseline is taken ONCE in `before_all`. A per-arm baseline is re-read after the
## damage and compares a polluted value with itself — measured green under a live strand elsewhere
## in this tree today.
var _pristine_text_size_scale: float = 1.0
var _saved_text_size_scale: float = 1.0


func before_all() -> void:
	if GameState:
		_pristine_text_size_scale = GameState.text_size_scale


func before_each() -> void:
	if GameState:
		_saved_text_size_scale = GameState.text_size_scale


func after_each() -> void:
	if GameState:
		GameState.text_size_scale = _saved_text_size_scale


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── TextScale util ────────────────────────────────────────────────────

func test_text_scale_class_present() -> void:
	var src := _read(TEXT_SCALE)
	assert_true(src.contains("class_name TextScale"),
		"TextScale class_name must register globally")


func test_text_scale_scaled_is_static() -> void:
	var src := _read(TEXT_SCALE)
	assert_true(src.contains("static func scaled(base: int) -> int:"),
		"TextScale.scaled must be static for direct call")


func test_text_scale_floors_at_1() -> void:
	var src := _read(TEXT_SCALE)
	assert_true(src.contains("return max(1, int(round(float(base) * scale)))"),
		"helper must floor at 1 (max(1, ...))")


func test_text_scale_handles_missing_gamestate() -> void:
	# Pin: helper defaults to scale=1.0 when GameState is unavailable.
	# Otherwise a unit test running without the autoload graph would
	# return 0 or crash.
	var src := _read(TEXT_SCALE)
	assert_true(src.contains("var scale: float = 1.0"),
		"helper must default scale to 1.0")


# ── Live behavior ────────────────────────────────────────────────────

func test_scaled_at_default_returns_base() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.text_size_scale = 1.0
	assert_eq(TextScale.scaled(13), 13, "1.0x scale of 13 → 13")
	assert_eq(TextScale.scaled(14), 14, "1.0x scale of 14 → 14")


func test_scaled_at_1_5x() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.text_size_scale = 1.5
	assert_eq(TextScale.scaled(13), 20, "1.5x scale of 13 → 20 (rounded from 19.5)")
	assert_eq(TextScale.scaled(20), 30, "1.5x scale of 20 → 30")
	GameState.text_size_scale = 1.0  # Reset for other tests.


func test_scaled_at_2x() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.text_size_scale = 2.0
	assert_eq(TextScale.scaled(14), 28, "2.0x scale of 14 → 28")
	GameState.text_size_scale = 1.0


func test_scaled_at_0_8x() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	GameState.text_size_scale = 0.8
	assert_eq(TextScale.scaled(10), 8, "0.8x scale of 10 → 8")
	GameState.text_size_scale = 1.0


# ── Consumer refactors: PartyStatusScreen ────────────────────────────

func test_party_status_uses_text_scale() -> void:
	# Pin: at least 18 sites using TextScale.scaled (matching the 18
	# original font_size literals from tick 223's sed pass).
	var src := _read(PARTY_STATUS)
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("TextScale.scaled(", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_gte(count, 18,
		"PartyStatusScreen must have ≥18 TextScale.scaled calls (was 18 raw font_size sites)")


func test_party_status_no_more_bare_font_size_literals() -> void:
	# Negative pin: no more `add_theme_font_size_override("font_size", <int>)`
	# raw integer literals — all routed through TextScale.scaled.
	var src := _read(PARTY_STATUS)
	# Use regex to find any remaining bare integer font_size override.
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"font_size\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"PartyStatusScreen must have NO bare integer font_size overrides remaining: %s" % (match.get_string() if match else "(clean)"))


# ── Consumer refactors: StatusMenu ───────────────────────────────────

func test_status_menu_uses_text_scale() -> void:
	var src := _read(STATUS_MENU)
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("TextScale.scaled(", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_gte(count, 23,
		"StatusMenu must have ≥23 TextScale.scaled calls (was 23 raw font_size sites)")


func test_status_menu_no_more_bare_font_size_literals() -> void:
	var src := _read(STATUS_MENU)
	var rgx := RegEx.new()
	rgx.compile("add_theme_font_size_override\\(\"font_size\", \\d+\\)")
	var match: RegExMatch = rgx.search(src)
	assert_eq(match, null,
		"StatusMenu must have NO bare integer font_size overrides remaining: %s" % (match.get_string() if match else "(clean)"))


# ── CutsceneDialogue delegation ──────────────────────────────────────

func test_cutscene_dialogue_delegates_to_text_scale() -> void:
	var src := _read(CUTSCENE_DIALOGUE)
	# Local helper now just delegates.
	assert_true(src.contains("return TextScale.scaled(base)"),
		"CutsceneDialogue._scaled_font_size must delegate to TextScale.scaled")


func test_cutscene_dialogue_call_sites_preserved() -> void:
	# Pin: tick 222's 4 call sites still use _scaled_font_size (which
	# now delegates).
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("_scaled_font_size(18)"), "speaker label call preserved (2026-07-15: +25% per struktured)")
	assert_true(src.contains("_scaled_font_size(16)"), "text label call preserved (2026-07-15: +25%)")
	assert_true(src.contains("_scaled_font_size(12)"), "advance hint call preserved (2026-07-15: +25%)")
	assert_true(src.contains("_scaled_font_size(18)"), "thinking label call preserved")


# ── Cross-pin: tick 222 SettingsMenu plumbing preserved ──────────────

func test_settings_menu_text_size_setting_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	assert_true(src.contains("const TEXT_SIZE_PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]"),
		"tick 222 TEXT_SIZE_PRESETS preserved")
	assert_true(src.contains("func _save_text_size_scale"),
		"tick 222 _save_text_size_scale helper preserved")


## ⛔ THE STRAND CATCHER, DECLARED LAST — declaration order is run order, and an aborting arm
## reports PASSING, so without this the teardown above is an unfalsifiable claim.
func test_zz_the_shared_text_size_scale_was_handed_back() -> void:
	if not GameState:
		pending("GameState autoload missing")
		return
	assert_eq(GameState.text_size_scale, _pristine_text_size_scale,
		"GameState.text_size_scale is %s and started this file at %s — an earlier arm left it moved, and "
			% [GameState.text_size_scale, _pristine_text_size_scale]
		+ "every later file in this process inherits it.")
