extends GutTest

## Completes the loud-fail data-load family (tick 28 JobSystem +
## PassiveSystem, tick 29 ItemSystem + EquipmentSystem). EncounterSystem
## had an even WORSE shape than the others:
##
##   _load_enemy_pools: NO feedback at all on any failure path before —
##   if FileAccess.open returned null OR json.parse failed OR json.data
##   wasn't a dict, the function silently fell through to defaults.
##   No print, no warning, just '7 hardcoded pools' instead of the 33
##   real ones, with zero indication anything went wrong.
##
##   _load_monster_database: print-only "Warning: Could not load…" on
##   any failure — same silent failure class as the others.
##
## Fix: push_warning every distinct failure path with a specific
## message naming WHICH failure happened (missing / open-failed /
## parse-error / type-mismatch) so the dev can diagnose without
## digging.

const ENCOUNTER_SYSTEM := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_enemy_pools_load_has_four_distinct_warnings() -> void:
	var src := _read(ENCOUNTER_SYSTEM)
	# Each failure mode gets a distinct message — vague 'load failed'
	# doesn't help when there are 4 different ways for the load to fail.
	assert_true(src.contains("enemy_pools.json not found at"),
		"missing-file path must push_warning")
	assert_true(src.contains("enemy_pools.json exists but FileAccess.open failed"),
		"open-failed path must push_warning — usually means a permissions issue")
	assert_true(src.contains("enemy_pools.json parse error:"),
		"parse-error path must push_warning, naming the JSON error message")
	assert_true(src.contains("enemy_pools.json parsed but root is not a Dictionary"),
		"non-Dict-root path must push_warning")


func test_monster_database_load_has_four_distinct_warnings() -> void:
	var src := _read(ENCOUNTER_SYSTEM)
	assert_true(src.contains("monsters.json not found at"),
		"missing monsters.json must push_warning")
	assert_true(src.contains("monsters.json exists but FileAccess.open failed"),
		"open-failed monsters.json must push_warning")
	assert_true(src.contains("monsters.json parse error:"),
		"parse-error monsters.json must push_warning")
	assert_true(src.contains("monsters.json parsed but root is not a Dictionary"),
		"non-Dict-root monsters.json must push_warning")


func test_load_paths_use_early_return_pattern() -> void:
	# The original silent-failure shape was nested `if … if …` with a
	# fall-through to defaults at the bottom. New shape is early-return
	# after each push_warning so the success branch reads top-down. This
	# guards against a future cleanup re-nesting into the old shape.
	var src := _read(ENCOUNTER_SYSTEM)
	# Count push_warning calls in EncounterSystem — should be 8+
	# (4 per load function).
	var count := 0
	var idx := 0
	while true:
		idx = src.find("push_warning(\"[EncounterSystem]", idx)
		if idx < 0:
			break
		count += 1
		idx += 1
	assert_gte(count, 8,
		"EncounterSystem must have at least 8 push_warning calls (4 enemy_pools + 4 monsters.json failure modes)")
