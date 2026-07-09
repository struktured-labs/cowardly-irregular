extends GutTest

## Feature 2026-07-05: the character StatusMenu showed a bare "EXP: 150" with no
## target, so the player couldn't see how close they were to leveling. It now
## shows progress against the gain_job_exp threshold (job_level*100), e.g.
## "EXP: 150 / 300", and "EXP: MAX" at the level-99 cap. Pairs with the
## v3.33.14 overworld EXP-pip fix.

const SM := preload("res://src/ui/StatusMenu.gd")


func test_shows_progress_to_next_level() -> void:
	assert_eq(SM._exp_display(3, 150), "EXP: 150 / 300",
		"level 3 threshold is 300 — the readout must show progress against it")


func test_level_one_threshold() -> void:
	assert_eq(SM._exp_display(1, 0), "EXP: 0 / 100", "level 1 threshold is 100")


func test_max_level_shows_max() -> void:
	assert_eq(SM._exp_display(99, 4200), "EXP: MAX",
		"at the level cap there is no next-level target")


func test_threshold_scales_with_level() -> void:
	# Guards against a regression to a flat denominator (the v3.33.14 bug class).
	assert_eq(SM._exp_display(7, 200), "EXP: 200 / 700", "threshold must be job_level*100")
