extends GutTest

## Regression (web-smoke soft-error budget, first find, 2026-07-11): an
## OverworldController freed while paused stranded its global
## 'exploration_paused' lock in InputLockManager — the player of the NEXT
## scene sat frozen until the 10-second stale-lock expiry fired. The
## controller must release the lock on teardown.

const ControllerScript := preload("res://src/exploration/OverworldController.gd")


func test_freed_paused_controller_releases_its_lock() -> void:
	InputLockManager.pop_all()
	var c = ControllerScript.new()
	add_child(c)
	c.pause_exploration()
	assert_true(InputLockManager.is_locked(), "pause must hold the global lock")
	c.free()
	assert_false(InputLockManager.is_locked(),
		"freeing a paused controller must release 'exploration_paused' — it stranded the lock and froze the next scene for 10s")


func test_normal_pause_resume_still_balanced() -> void:
	InputLockManager.pop_all()
	var c = ControllerScript.new()
	add_child_autofree(c)
	c.pause_exploration()
	c.resume_exploration()
	assert_false(InputLockManager.is_locked(), "resume must release the lock")
