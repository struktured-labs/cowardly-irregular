extends GutTest

## tick 128 regression: _on_party_ability_learned must use a
## prettified ability_id (snake_case → Title Case) as the toast
## fallback when JobSystem can't resolve the ability — not the raw
## snake_case key.
##
## Pre-fix, if JobSystem.get_ability returned an empty dict (debug
## ability path, Scriptweaver custom ability, save-format drift),
## the toast surfaced "Mira learned shield_bash!" with the
## underscore — engineer-facing, breaks immersion.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _handler_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_party_ability_learned")
	assert_gt(idx, -1, "_on_party_ability_learned must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_fallback_prettifies_via_replace_and_capitalize() -> void:
	# Pin the canonical prettifier: replace("_", " ").capitalize().
	# String.capitalize() in GDScript title-cases each word.
	var body := _handler_body()
	assert_true(body.contains("ability_id.replace(\"_\", \" \").capitalize()"),
		"_on_party_ability_learned must use ability_id.replace('_', ' ').capitalize() as the toast fallback")


func test_raw_ability_id_no_longer_the_initial_default() -> void:
	# Negative pin: the pre-fix default `var ability_name: String = ability_id`
	# (raw snake_case) must be gone. Otherwise a future refactor that
	# accidentally re-introduces it would surface ugly engineer-facing
	# strings without anyone noticing.
	var body := _handler_body()
	assert_false(body.contains("var ability_name: String = ability_id\n"),
		"raw ability_id default must be gone — fallback is now the prettified form")


func test_job_system_resolution_still_preferred() -> void:
	# Don't regress the JobSystem lookup — when the ability is
	# registered, its canonical name still wins over the prettified
	# fallback.
	var body := _handler_body()
	assert_true(body.contains("var a: Dictionary = JobSystem.get_ability(ability_id)"),
		"JobSystem.get_ability lookup must still be the first-choice resolver")
	assert_true(body.contains("if not a.is_empty() and a.has(\"name\"):"),
		"empty-dict + name-field guards must still gate the JobSystem branch")
	assert_true(body.contains("ability_name = str(a[\"name\"])"),
		"JobSystem name must still override the prettified fallback")


func test_capitalize_actually_title_cases_snake_case() -> void:
	# Sanity: verify the GDScript String.capitalize() behavior the
	# fix relies on. "shield_bash" → "Shield Bash" after replace.
	# This is the contract we're trusting; if it ever changed in
	# a future Godot version this test would catch the drift.
	var prettified: String = "shield_bash".replace("_", " ").capitalize()
	assert_eq(prettified, "Shield Bash",
		"GDScript .capitalize() must title-case each space-separated word — the fix depends on this")
	# Multi-underscore case.
	var multi: String = "crystal_heal_aoe".replace("_", " ").capitalize()
	assert_eq(multi, "Crystal Heal Aoe",
		".capitalize() must work on multi-underscore strings — covers complex meta-ability ids")


func test_toast_format_string_unchanged() -> void:
	# Pin the toast message format. Changing "%s learned %s!" would
	# break L10n / quest-log matchers that may look for this string.
	var body := _handler_body()
	assert_true(body.contains("\"%s learned %s!\" % [member.combatant_name, ability_name]"),
		"toast format string must remain '%s learned %s!' — consumers may match on this")


func test_null_member_guard_preserved() -> void:
	# Don't regress the null guard — the signal can fire with a
	# freed combatant in race scenarios.
	var body := _handler_body()
	assert_true(body.contains("if member == null:"),
		"null member guard must remain — defensive against signal-after-free")


func test_toast_color_unchanged() -> void:
	# Don't regress the SUCCESS_COLOR — green/positive toast is the
	# right semantic for an ability unlock.
	var body := _handler_body()
	assert_true(body.contains("Toast.SUCCESS_COLOR"),
		"toast color must remain SUCCESS_COLOR — ability unlock is a positive event")
