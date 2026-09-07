extends GutTest

## BestiarySystem._load_json had the same 4-silent-fail shape that
## ticks 28-31 caught everywhere else. Malformed monsters.json or
## bestiary.json silently returned {} → get_monster_data and
## get_flavor returned empty dicts → bestiary UI showed "?" entries
## with no clue why.
##
## Helper is used for BOTH monsters.json and bestiary.json so a single
## fix covers both data files.

const BESTIARY := "res://src/bestiary/BestiarySystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_all_four_failure_modes_push_warning() -> void:
	var src := _read(BESTIARY)
	# Distinct messages per failure mode — vague 'load failed' wouldn't
	# tell the dev whether the file's missing, unreadable, malformed,
	# or wrong shape.
	assert_true(src.contains("not found — entries from this file will return empty"),
		"missing-file path must push_warning")
	assert_true(src.contains("exists but FileAccess.open failed"),
		"open-failed path must push_warning")
	assert_true(src.contains("parse error:"),
		"parse-error path must push_warning naming the JSON error message")
	assert_true(src.contains("parsed but root is not a Dictionary"),
		"non-Dict-root path must push_warning")


func test_warnings_use_push_warning_namespace() -> void:
	var src := _read(BESTIARY)
	# All warnings must use the [BestiarySystem] prefix so log greps
	# can find them by subsystem.
	var count := 0
	var idx := 0
	while true:
		idx = src.find("push_warning(\"[BestiarySystem]", idx)
		if idx < 0:
			break
		count += 1
		idx += 1
	assert_gte(count, 4,
		"_load_json must have at least 4 [BestiarySystem]-prefixed push_warnings (one per failure mode)")


func test_load_helper_takes_path_argument() -> void:
	# The helper is shared between monsters.json and bestiary.json —
	# pin that it takes the path as an arg so warnings include it,
	# not a hardcoded filename.
	var src := _read(BESTIARY)
	var idx := src.find("static func _load_json(path: String)")
	assert_gt(idx, -1, "_load_json must take path as a parameter so warnings name the failing file")
