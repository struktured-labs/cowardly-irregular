extends GutTest

## `CutsceneDirector._process` HEARTBEATS `push_lock("cutscene")` every frame while `_active` — it
## must, because cutscenes routinely run past the 10s stale-lock reaper — and only `_end_cutscene`
## ever pops it. So any teardown that does not run the ending left the canonical input lock HELD:
## a scene change under a live cutscene, an aborted scene, or a freed director.
##
## In the game that is up to 10 seconds of dead input before the reaper takes it. In the suite it was
## a cross-file leak: 16 test files arm `_active = true`, and the first of them in a 126-script batch
## left the global lock held for everything after it. It cost `test_overworld_transitions`'
## "Should start unlocked" a red in that batch (found by bisection 2026-09-16; that file passes 8/8
## alone, and the same batch on origin/main failed identically, so it predated any one branch).
##
## 🔑 The fix releases only what THIS director holds — `_holds_input_lock` — so a teardown can never
## pop a lock someone else pushed.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")


func _ilm() -> Node:
	return get_tree().root.get_node_or_null("InputLockManager")


func before_each() -> void:
	var ilm := _ilm()
	if ilm and ilm.has_lock("cutscene"):
		ilm.pop_lock("cutscene")


func after_each() -> void:
	var ilm := _ilm()
	if ilm and ilm.has_lock("cutscene"):
		ilm.pop_lock("cutscene")


## A director that armed the heartbeat and is then freed must leave the lock clean.
func test_a_freed_director_releases_the_lock_it_armed() -> void:
	var ilm := _ilm()
	assert_not_null(ilm, "PRECONDITION: the InputLockManager autoload must exist")
	if ilm == null:
		return
	var d = DirectorScript.new()
	add_child(d)
	d._active = true
	d._process(0.1)
	assert_true(ilm.has_lock("cutscene"), "control: the heartbeat must actually take the lock")
	d.free()
	assert_false(ilm.has_lock("cutscene"),
		"a freed director must release the lock its own heartbeat took — otherwise input is dead until the 10s reaper")


## And the ordinary path is unchanged: the ending pops it, and the free afterwards is a no-op.
func test_the_ending_still_owns_the_normal_release() -> void:
	var ilm := _ilm()
	if ilm == null:
		return
	var d = DirectorScript.new()
	add_child(d)
	d._freeze_player()
	assert_true(ilm.has_lock("cutscene"), "control: freezing takes the lock")
	d._unfreeze_player()
	assert_false(ilm.has_lock("cutscene"), "the ending releases it")
	assert_false(d._holds_input_lock, "and the director stops claiming it")
	d.free()
	assert_false(ilm.has_lock("cutscene"), "freeing after a clean release changes nothing")


## ⛔ A teardown must never pop a lock it did not take. Someone else's "cutscene" lock survives.
func test_a_director_that_never_armed_it_pops_nothing() -> void:
	var ilm := _ilm()
	if ilm == null:
		return
	ilm.push_lock("cutscene")
	var d = DirectorScript.new()
	add_child(d)
	assert_false(d._holds_input_lock, "PRECONDITION: this director never armed the lock")
	d.free()
	assert_true(ilm.has_lock("cutscene"),
		"a director that never took the lock must not release someone else's on the way out")
	ilm.pop_lock("cutscene")


## The heartbeat itself is the reason this is needed — pin that it still refreshes while active.
func test_the_heartbeat_still_holds_the_lock_while_active() -> void:
	var ilm := _ilm()
	if ilm == null:
		return
	var d = DirectorScript.new()
	add_child_autofree(d)
	d._active = true
	d._process(0.1)
	d._process(0.1)
	assert_true(ilm.has_lock("cutscene"),
		"the heartbeat must keep the lock held across frames — the 10s reaper is what it defends against")
	assert_true(d._holds_input_lock, "and the director must know it is holding it")


## An inactive director heartbeats nothing, so it has nothing to release.
func test_an_inactive_director_takes_no_lock() -> void:
	var ilm := _ilm()
	if ilm == null:
		return
	var d = DirectorScript.new()
	add_child_autofree(d)
	d._process(0.1)
	assert_false(ilm.has_lock("cutscene"), "_process returns early when not active")
	assert_false(d._holds_input_lock, "so nothing is claimed")
