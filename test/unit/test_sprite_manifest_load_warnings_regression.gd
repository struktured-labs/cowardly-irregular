extends GutTest

## Worst silent-failure shape in the data-load family. _load_manifest
## had NO feedback on any failure path — file missing, FileAccess.open
## failed, parse error, non-Dict root all silently left _manifest = {}.
## Every job + monster falls back to procedural sprites with no signal.
## Devs would see "where are the artist sprites" with zero clue the
## manifest didn't load.
##
## Fix: push_warning each distinct failure mode with the specific cause.
## _manifest_loaded flips to true on every path so failure-mode-2's
## push_warning fires once, not every lookup.

const HYBRID_LOADER := "res://src/battle/sprites/HybridSpriteLoader.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_each_failure_mode_pushes_warning() -> void:
	var src := _read(HYBRID_LOADER)
	# Four distinct messages — vague 'manifest load failed' wouldn't
	# distinguish 'file's gone' from 'JSON has a syntax error', and
	# the dev has to diagnose differently in each case.
	assert_true(src.contains("sprite_manifest.json not found at"),
		"missing-file path must push_warning naming the path")
	assert_true(src.contains("sprite_manifest.json exists but FileAccess.open failed"),
		"open-failed path must push_warning (typically permissions)")
	assert_true(src.contains("sprite_manifest.json parse error:"),
		"parse-error path must push_warning naming the JSON error")
	assert_true(src.contains("sprite_manifest.json parsed but root is not a Dictionary"),
		"non-Dict-root path must push_warning")


func test_warnings_explain_user_visible_consequence() -> void:
	# 'manifest invisible' isn't useful to a dev grepping logs. Each
	# warning must name the CONSEQUENCE (artist sheets invisible) so
	# the player-facing symptom maps to the cause.
	var src := _read(HYBRID_LOADER)
	# At least 3 of the 4 failure-mode warnings must mention 'artist
	# sheets invisible' as the user-visible consequence.
	var count := 0
	var idx := 0
	while true:
		idx = src.find("artist sheets invisible", idx)
		if idx < 0:
			break
		count += 1
		idx += 1
	assert_gte(count, 3,
		"failure-mode warnings should name the user-visible consequence ('artist sheets invisible') in most cases")


func test_manifest_loaded_flag_set_on_all_paths() -> void:
	# Critical: _manifest_loaded MUST be set to true on every failure
	# path so push_warning fires once at startup, not per-lookup. The
	# pre-fix code only set _manifest_loaded at the bottom of the
	# function (after the if-tree) which preserved the once-per-session
	# behavior, but the new flatter structure has to be careful not to
	# drop that.
	var src := _read(HYBRID_LOADER)
	# Count _manifest_loaded = true assignments in the function body.
	# Expect 5 sites: 4 failure-return sites + 1 success-tail.
	var count := 0
	var idx := 0
	while true:
		idx = src.find("_manifest_loaded = true", idx)
		if idx < 0:
			break
		count += 1
		idx += 1
	assert_gte(count, 5,
		"every failure path AND the success path must set _manifest_loaded = true — otherwise push_warning would fire on every lookup")
