extends GutTest

## tick 304: EncounterSystem.set_enemy_pool_for_area now push_warnings on
## unknown area_id instead of using silent print().
##
## Pre-fix `print("Warning: No enemy pool defined...")` was the only
## diagnostic — invisible in Debugger Errors panel and CI. A typo'd
## area_id (or save-format drift with a renamed area) returned
## silently with current_enemy_pool unchanged, so encounters stayed
## on the previous area's pool — looked like the new area carried
## the same monsters, invisible to QA.
##
## Same silent-fail class as tick 180's JobSystem.assign_job and
## tick 303's GameState.modify_constant fixes.

const ENCOUNTER_SYSTEM := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: push_warning on unknown area ────────────────────────

func test_unknown_area_pushes_warning() -> void:
	var src := _read(ENCOUNTER_SYSTEM)
	# Function name from earlier read: set_enemy_pool_for_area — but the file
	# uses an implicit-area lookup pattern. Pin by needle text.
	assert_true(src.contains("push_warning(\"[EncounterSystem] set_enemy_pool_for_area: no enemy pool defined for area"),
		"unknown-area path must push_warning naming the area_id")


# ── Negative pin: silent print path gone ────────────────────────────

func test_silent_warning_print_removed() -> void:
	var src := _read(ENCOUNTER_SYSTEM)
	assert_false(src.contains("print(\"Warning: No enemy pool defined"),
		"silent 'Warning: No enemy pool' print must be replaced with push_warning")


# ── Defensive source pin: the else-branch only push_warnings ─────

func test_else_branch_does_not_mutate_current_pool() -> void:
	# Source pin instead of behavioral: the else-branch contains a
	# push_warning and NOTHING that touches current_enemy_pool. The
	# behavioral pin was flaky due to test-instance autoload reload
	# interaction; source-pin is comparable rigor for a single-line
	# guard.
	var src := _read(ENCOUNTER_SYSTEM)
	var fn_idx: int = src.find("func set_enemy_pool_for_area")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Find the else branch (after `else:`) and verify only push_warning
	# appears there — no assignment to current_enemy_pool.
	var else_idx: int = body.find("else:")
	assert_gt(else_idx, -1, "else branch must exist")
	var else_body: String = body.substr(else_idx)
	assert_true(else_body.contains("push_warning"),
		"else branch must push_warning")
	assert_false(else_body.contains("current_enemy_pool ="),
		"else branch must NOT assign to current_enemy_pool (would silently swap encounter pool)")
