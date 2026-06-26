extends GutTest

## tick 203: TitleScreen now uses a single source of truth for
## the Continue button's target slot.
##
## Pre-fix the title screen had two different "does a save exist?"
## checks that could disagree:
##
##   _check_for_save() → SaveSystem.has_save()
##     → walks slots, returns true on first save_exists() (file
##        existence check ONLY)
##
##   _build_continue_subtitle() → SaveSystem.get_most_recent_slot()
##     → walks slots, picks newest by save_time IN METADATA;
##        returns -1 if no slot has metadata
##
## A save file that exists but is missing metadata (corrupted,
## truncated mid-write, older format with renamed keys) caused:
##   - Continue row shown (has_save=true)
##   - Subtitle empty (get_most_recent_slot=-1)
##   - Click → continue_selected.emit() → consumer calls
##     SaveSystem.load_game(slot) with slot=-1 → failure
##
## Fix: _check_for_save uses get_most_recent_slot directly and
## caches the slot in _cached_continue_slot. _build_continue_subtitle
## reads the cache instead of re-walking — guarantees the subtitle's
## slot and the load-path's slot are identical.

const TITLE_SCREEN := "res://src/ui/TitleScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Cache var present ─────────────────────────────────────────────────

func test_cached_slot_var_declared() -> void:
	var src := _read(TITLE_SCREEN)
	assert_true(src.contains("var _cached_continue_slot: int = -1"),
		"_cached_continue_slot must be declared at -1")


# ── _check_for_save populates cache via get_most_recent_slot ──────────

func test_check_for_save_uses_get_most_recent_slot() -> void:
	# Pin: the primary path goes through get_most_recent_slot, not
	# has_save. The semantics now match what Continue actually needs.
	var src := _read(TITLE_SCREEN)
	var fn_idx: int = src.find("func _check_for_save")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("SaveSystem.has_method(\"get_most_recent_slot\")"),
		"_check_for_save must check for get_most_recent_slot method")
	assert_true(body.contains("_cached_continue_slot = SaveSystem.get_most_recent_slot()"),
		"_check_for_save must populate _cached_continue_slot")
	assert_true(body.contains("return _cached_continue_slot >= 0"),
		"_check_for_save must return based on the cached slot")


func test_check_for_save_resets_cache_first() -> void:
	# Pin: cache is reset to -1 at the start so a missing SaveSystem
	# falls through to the file-existence fallbacks with a clean slate.
	var src := _read(TITLE_SCREEN)
	var fn_idx: int = src.find("func _check_for_save")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# The reset must come BEFORE the SaveSystem check.
	var reset_idx: int = body.find("_cached_continue_slot = -1")
	var check_idx: int = body.find("if SaveSystem")
	assert_gt(reset_idx, -1)
	assert_gt(check_idx, -1)
	assert_lt(reset_idx, check_idx,
		"cache reset must come BEFORE the SaveSystem check")


func test_old_has_save_path_gone() -> void:
	# Negative pin: the primary has_save() path is gone. (Fallback
	# file-existence checks remain as a safety net for very early
	# boot when SaveSystem isn't ready.)
	var src := _read(TITLE_SCREEN)
	var fn_idx: int = src.find("func _check_for_save")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_false(body.contains("return SaveSystem.has_save()"),
		"primary has_save() path must be gone (metadata mismatch risk)")


# ── Fallback safety net preserved ─────────────────────────────────────

func test_filesystem_fallback_preserved() -> void:
	# Pre-existing safety: if SaveSystem autoload isn't ready,
	# still consult the filesystem.
	var src := _read(TITLE_SCREEN)
	var fn_idx: int = src.find("func _check_for_save")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("FileAccess.file_exists(\"user://save_data.json\")"),
		"legacy save_data.json fallback preserved")
	assert_true(body.contains("FileAccess.file_exists(\"user://saves/save_00.json\")"),
		"legacy saves/save_00.json fallback preserved")


# ── _build_continue_subtitle reads cache ──────────────────────────────

func test_subtitle_reads_cache_first() -> void:
	var src := _read(TITLE_SCREEN)
	var fn_idx: int = src.find("func _build_continue_subtitle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("var slot: int = _cached_continue_slot"),
		"_build_continue_subtitle must read the cached slot first")


func test_subtitle_has_cache_miss_fallback() -> void:
	# Pin: if cache is -1 (cold boot path where check fell back to
	# filesystem), subtitle still tries the live lookup.
	var src := _read(TITLE_SCREEN)
	var fn_idx: int = src.find("func _build_continue_subtitle")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if slot < 0 and SaveSystem.has_method(\"get_most_recent_slot\"):"),
		"cache miss must fall through to live get_most_recent_slot")
	assert_true(body.contains("slot = SaveSystem.get_most_recent_slot()"),
		"cache miss must update slot via live lookup")


func test_subtitle_handles_negative_slot() -> void:
	# Pre-existing: if no slot resolves (cache and lookup both fail),
	# subtitle returns empty.
	var src := _read(TITLE_SCREEN)
	var fn_idx: int = src.find("func _build_continue_subtitle")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if slot < 0:\n\t\treturn \"\""),
		"unresolved slot → empty subtitle (pre-existing safety preserved)")


# ── Cross-pins: tick 202 + 197 work preserved ──────────────────────────

func test_tick_202_slot_label_helper_preserved() -> void:
	var src := _read(TITLE_SCREEN)
	assert_true(src.contains("static func _format_continue_slot_label(slot: int) -> String:"),
		"tick 202 slot label helper preserved")


func test_tick_202_subtitle_composition_preserved() -> void:
	var src := _read(TITLE_SCREEN)
	assert_true(src.contains("return \"%s · %s\" % [slot_label, detail]"),
		"tick 202 'Slot N · Chapter — Location' composition preserved")


# ── Live SaveSystem integration sanity ────────────────────────────────

func test_save_system_has_both_methods_in_live_build() -> void:
	# Pin: SaveSystem still exposes both APIs (has_save and
	# get_most_recent_slot). Catches a future refactor that
	# removes one of them.
	if not SaveSystem:
		pending("SaveSystem autoload not available in isolated test")
		return
	assert_true(SaveSystem.has_method("get_most_recent_slot"),
		"SaveSystem must still expose get_most_recent_slot (load path depends on it)")
	assert_true(SaveSystem.has_method("has_save"),
		"SaveSystem still exposes has_save (fallback consumers may use it)")
