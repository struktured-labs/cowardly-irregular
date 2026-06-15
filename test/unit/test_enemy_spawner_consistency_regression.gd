extends GutTest

## Defensive regression: BattleEnemySpawner's three spawn paths must
## agree on (a) which signals are disconnected during cleanup and
## (b) which suffix-array indexing rule they use.
##
## Bug shapes prevented:
##   1. Asymmetric signal cleanup. spawn_enemies' cleanup loop only
##      disconnected hp_changed + died — leaving status_added and
##      status_removed connected even after the enemy was queued for
##      free. If queue_free flushed mid-emit (rare but real), the
##      status listener would fire against a stale enemy reference.
##      Now ALL four signals connected on spawn are also disconnected
##      on cleanup.
##   2. Suffix-array out-of-bounds. spawn_enemies used
##      `["A", "B", "C"][type_count]` with no modulo guard. Sister
##      functions (spawn_from_data, spawn_encounter_enemies) used
##      `% 3`. Today num_enemies is capped at 3 by
##      mini(3, enemy_positions.size()), so type_count never reaches
##      3 — but the moment someone widens that cap (or adds a 4th
##      position marker) spawn_enemies crashes while the sister paths
##      keep working. Aligning all three rules removes the landmine.
##
## Tests:
##   • Source pin: cleanup loop covers all 4 signals (hp_changed,
##     died, status_added, status_removed)
##   • Source pin: spawn_enemies' suffix array indexes with `% 3`
##   • Source pin: the same `% 3` rule lives in spawn_from_data and
##     spawn_encounter_enemies (these were already correct — the
##     test locks them in alongside the new spawn_enemies match)

const SPAWNER_PATH := "res://src/battle/BattleEnemySpawner.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Cleanup signal symmetry ──────────────────────────────────────────────────

func test_spawn_enemies_cleanup_disconnects_all_four_signals() -> void:
	var text := _read(SPAWNER_PATH)
	var idx := text.find("func spawn_enemies")
	assert_gt(idx, -1, "spawn_enemies must exist")
	var rest := text.substr(idx)
	# Scope: from spawn_enemies through the start of spawn_from_data so we
	# only scan the function body.
	var next_fn := rest.find("\nfunc spawn_from_data")
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# All four signals must be named inside the cleanup body. (Comments in
	# the body also name them, but a missing reference would still flag
	# regression — the disconnect logic needs all four to be named at all.)
	for sig in ["hp_changed", "died", "status_added", "status_removed"]:
		assert_true(body.contains("\"" + sig + "\""),
			"spawn_enemies cleanup must name signal '%s' so it gets disconnected like the others" % sig)


# ── Suffix-array indexing parity ─────────────────────────────────────────────

func test_spawn_enemies_uses_modulo_3_suffix() -> void:
	# Pin the bounded indexing in spawn_enemies so a future widening of
	# num_enemies past 3 doesn't crash on `["A", "B", "C"][type_count]`.
	var text := _read(SPAWNER_PATH)
	var idx := text.find("func spawn_enemies")
	assert_gt(idx, -1, "spawn_enemies must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc spawn_from_data")
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Strip comments so the explanatory teaching doc (which also cites the
	# old un-modulated shape) can't trip its own lint.
	var lines := body.split("\n")
	var code_only: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		code_only.append(ln)
	var code := "\n".join(code_only)
	# Negative: the un-modulated shape `[type_count]` must NOT appear in code.
	assert_false(code.contains("[\"A\", \"B\", \"C\"][type_count]"),
		"spawn_enemies must NOT index the suffix array without `% 3` — that crashes when type_count >= 3")
	# Positive: the modulo form must appear in code.
	assert_true(code.contains("[\"A\", \"B\", \"C\"][type_count % 3]"),
		"spawn_enemies must index the suffix array with `type_count % 3`")


func test_sister_spawn_paths_keep_modulo_3_suffix() -> void:
	# spawn_from_data and spawn_encounter_enemies already had the modulo —
	# guard them so the pattern stays consistent across all three paths.
	var text := _read(SPAWNER_PATH)
	for fn_name in ["func spawn_from_data", "func spawn_encounter_enemies"]:
		var idx := text.find(fn_name)
		assert_gt(idx, -1, "%s must exist" % fn_name)
		var rest := text.substr(idx)
		var next_fn := rest.find("\nfunc ", 1)
		var body := rest.substr(0, next_fn) if next_fn > -1 else rest
		assert_true(body.contains("[\"A\", \"B\", \"C\"]"),
			"%s must use the same A/B/C suffix array as spawn_enemies (parity)" % fn_name)
		assert_true(body.contains("% 3]"),
			"%s must index with `% 3]` so it stays parity with spawn_enemies' new modulo guard" % fn_name)
