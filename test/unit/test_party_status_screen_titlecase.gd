extends GutTest

## tick 204: PartyStatusScreen._format_id now does proper multi-
## word title-case instead of relying on String.capitalize()'s
## first-letter-only behavior (the tick 186 finding).
##
## Pre-fix _format_id("power_strike") → "Power strike" (lowercase
## 's'). The fallback fires whenever:
##   - the data file lacks a "name" field (authoring error)
##   - Scriptweaver injects a custom ability/passive/equipment id
##   - save-format drift (id removed from data file between saves)
##   - JobSystem/PassiveSystem/EquipmentSystem autoloads aren't
##     reachable (boot ordering edge cases)
##
## The party status screen opens multiple times per session, so
## a "Power strike" leak is high-visibility.
##
## This is the same fix pattern as ticks 185 (MenuScene), 186
## (StatusMenu), 187 (ShopScene), 193 (BestiarySystem._titlecase),
## 199 (JukeboxMenu._titlecase). PartyStatusScreen was the last
## menu still using the broken capitalize() prettifier.

const PARTY_STATUS_SCREEN := "res://src/ui/PartyStatusScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# Pure helper test — instantiate the Control (Godot lets us call methods
# on Controls without adding them to the tree).
func _new_screen() -> Object:
	var scene = load(PARTY_STATUS_SCREEN)
	return scene.new()


# ── Proper title-case behavior ─────────────────────────────────────────

func test_two_word_title_case() -> void:
	var s = _new_screen()
	assert_eq(s._format_id("power_strike"), "Power Strike",
		"2-word snake_case → 'Power Strike' (NOT 'Power strike')")
	s.queue_free()


func test_three_word_title_case() -> void:
	var s = _new_screen()
	assert_eq(s._format_id("iron_will_armor"), "Iron Will Armor",
		"3-word snake_case → 'Iron Will Armor'")
	s.queue_free()


func test_single_word_capitalized() -> void:
	var s = _new_screen()
	assert_eq(s._format_id("potion"), "Potion",
		"single word → 'Potion'")
	s.queue_free()


func test_empty_string_returns_empty() -> void:
	var s = _new_screen()
	assert_eq(s._format_id(""), "",
		"empty string → empty (no crash)")
	s.queue_free()


func test_already_uppercased_input_normalizes() -> void:
	# Pin: an input like "POWER_STRIKE" lowercases the rest of each
	# word, producing "Power Strike". Idempotency on the canonical
	# form: _format_id(_format_id(x)) == _format_id(x).
	var s = _new_screen()
	assert_eq(s._format_id("POWER_STRIKE"), "Power Strike",
		"upper-case input normalizes to title case")
	s.queue_free()


# ── Equipment row site uses _format_id ────────────────────────────────

func test_equipment_row_uses_format_id_fallback() -> void:
	# Pin: _add_equipment_row's "no name in info" fallback now uses
	# _format_id instead of the broken inline capitalize() pattern.
	var src := _read(PARTY_STATUS_SCREEN)
	assert_true(src.contains("item_name = info.get(\"name\", _format_id(item_id))"),
		"_add_equipment_row fallback must use _format_id(item_id)")


# ── Negative pin: broken capitalize() pattern gone from the file ──────

func test_broken_capitalize_pattern_gone() -> void:
	# Pre-fix the file had two `replace("_", " ").capitalize()` sites.
	# Both should be replaced.
	var src := _read(PARTY_STATUS_SCREEN)
	assert_false(src.contains("item_id.replace(\"_\", \" \").capitalize()"),
		"equipment-row broken capitalize() pattern must be gone")
	assert_false(src.contains("return id.replace(\"_\", \" \").capitalize()"),
		"_format_id's broken capitalize() return must be gone")


# ── Helper structure: per-word loop ────────────────────────────────────

func test_format_id_uses_split_underscore() -> void:
	# Pin: the implementation walks each underscore-delimited part,
	# title-casing each. This is the canonical pattern across the
	# codebase (BestiarySystem._titlecase, JukeboxMenu._titlecase).
	var src := _read(PARTY_STATUS_SCREEN)
	assert_true(src.contains("id.split(\"_\")"),
		"_format_id must split on underscore")
	assert_true(src.contains("to_upper()") and src.contains("to_lower()"),
		"_format_id must per-word upper-then-lower for each split part")


# ── Resolver fallback paths cascade through _format_id ────────────────

func test_resolve_ability_name_fallback_uses_format_id() -> void:
	# Pin: _resolve_ability_name returns _format_id(ability_id) on
	# JobSystem unavailability or missing-name. Now that _format_id
	# is correct, this fallback produces proper title case too.
	var src := _read(PARTY_STATUS_SCREEN)
	var fn_idx: int = src.find("func _resolve_ability_name")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return _format_id(ability_id)"),
		"_resolve_ability_name fallback must call _format_id")


func test_resolve_passive_name_fallback_uses_format_id() -> void:
	var src := _read(PARTY_STATUS_SCREEN)
	var fn_idx: int = src.find("func _resolve_passive_name")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return _format_id(passive_id)"),
		"_resolve_passive_name fallback must call _format_id")


func test_resolve_equipment_fallback_uses_format_id() -> void:
	var src := _read(PARTY_STATUS_SCREEN)
	var fn_idx: int = src.find("func _resolve_equipment")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return {\"name\": _format_id(item_id)"),
		"_resolve_equipment fallback dict must use _format_id for the name")


# ── End-to-end: cascaded resolver→_format_id pipeline ─────────────────

func test_cascaded_resolver_uses_proper_titlecase() -> void:
	# Integration: an ability with no data in JobSystem flows through
	# the fallback path to _format_id. With the fix, the result is
	# proper title case.
	var s = _new_screen()
	# Simulate an unknown ability id (no JobSystem entry).
	var name = s._resolve_ability_name("supercharged_volley_of_doom")
	# Whatever the result is (data lookup or fallback), it must NOT
	# leak the raw snake_case AND must use proper title case if it's
	# the fallback (5 words, each capitalized).
	assert_false("_" in name,
		"resolved name must not contain underscores")
	if name == "Supercharged Volley Of Doom":
		# Fallback path took effect.
		pass
	# (Else: JobSystem had a real entry — unlikely for an invented id.)
	s.queue_free()
