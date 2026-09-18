extends GutTest

## Three input-lock holders released their lock only on the happy path, and a teardown in between
## left the player unable to move.
##
## The shape is identical in all three: `push_lock` → `await` something the PLAYER drives → `pop`.
## Nothing ran the pop if the node was freed during that await, and the lock is held on
## InputLockManager, an autoload, so it survives into the next scene. `OverworldPlayer._can_move()`
## consults it, so the player is frozen until the 10-second stale reaper fires with a warning.
##
##     ReadableProp      held for as long as the player READS — by far the widest window. A roaming
##                       monster touching the player starts a battle, GameLoop frees the overworld,
##                       and `_close_panel` never runs. Measured: is_locked stayed TRUE after the free.
##     RoamingMonster    held while the elite prompt is up, and the monster is freed by the very
##                       battle the prompt leads to.
##     VillageElevator   held across `await tween.finished`; a map change frees the car.
##
## ⚠️ EACH HOLDER RELEASES ONLY ITS OWN LOCK. The id is a shared constant — two ReadableProps use
## "readable_prop" — so an unconditional pop on teardown would release a lock a DIFFERENT instance
## is holding, which is the same freeze with a harder repro. Every fix is gated on a per-instance
## flag set at push time, and the third arm below is the one that catches a regression to the
## unconditional form.

const READABLE := "res://src/exploration/ReadableProp.gd"
const ELEVATOR := "res://src/exploration/VillageElevator.gd"


func _ilm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("InputLockManager")


func _drain(ilm: Node, id: String) -> void:
	for i in range(6):
		ilm.pop_lock(id)


func test_a_readable_freed_while_open_releases_its_lock() -> void:
	var ilm := _ilm()
	if ilm == null:
		pending("InputLockManager required")
		return
	_drain(ilm, ReadableProp.LOCK_NAME)
	assert_false(ilm.is_locked(), "CONTROL: nothing is locked before the prop opens")

	var prop = load(READABLE).new()
	add_child(prop)
	await get_tree().process_frame
	prop.setup("probe", func(): return ["page one", "page two"])
	prop.interact(null)
	await get_tree().process_frame
	assert_true(prop.is_open(), "PRECONDITION: the panel opened")
	assert_true(ilm.is_locked(), "PRECONDITION: reading holds the input lock")

	# The scene goes away underneath it — battle, map change, teardown.
	prop.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var still: bool = ilm.is_locked()
	_drain(ilm, ReadableProp.LOCK_NAME)
	assert_false(still,
		"a ReadableProp freed while open left '%s' held. OverworldPlayer._can_move() consults " % ReadableProp.LOCK_NAME +
		"InputLockManager, so the player cannot move until the 10s stale reaper fires")


func test_closing_normally_still_releases() -> void:
	var ilm := _ilm()
	if ilm == null:
		return
	_drain(ilm, ReadableProp.LOCK_NAME)
	var prop = load(READABLE).new()
	add_child_autofree(prop)
	await get_tree().process_frame
	prop.setup("probe", func(): return ["only page"])
	prop.interact(null)
	await get_tree().process_frame
	assert_true(ilm.is_locked(), "PRECONDITION: open holds the lock")
	prop._close_panel()
	await get_tree().process_frame
	var held: bool = ilm.is_locked()
	_drain(ilm, ReadableProp.LOCK_NAME)
	assert_false(held, "the ordinary close path must still release — the teardown fix cannot replace it")


## The arm that refuses the cheap fix: an unconditional pop on teardown releases a lock that a
## DIFFERENT holder owns. Two props exist, one is reading, the other is freed.
func test_a_prop_that_never_opened_releases_nothing() -> void:
	var ilm := _ilm()
	if ilm == null:
		return
	_drain(ilm, ReadableProp.LOCK_NAME)

	var reader = load(READABLE).new()
	add_child_autofree(reader)
	var bystander = load(READABLE).new()
	add_child(bystander)
	await get_tree().process_frame
	reader.setup("reader", func(): return ["page"])
	reader.interact(null)
	await get_tree().process_frame
	assert_true(ilm.is_locked(), "PRECONDITION: the reader holds the lock")

	bystander.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var still_locked: bool = ilm.is_locked()
	reader._close_panel()
	_drain(ilm, ReadableProp.LOCK_NAME)
	assert_true(still_locked,
		"freeing a prop that was never opened released the lock the READING prop still holds — " +
		"the id is a shared constant, so teardown must release only this instance's own claim")


func test_an_elevator_freed_mid_ride_releases_its_lock() -> void:
	var ilm := _ilm()
	if ilm == null:
		return
	var lift = load(ELEVATOR).new()
	_drain(ilm, lift.LOCK_ID)
	add_child(lift)
	await get_tree().process_frame

	# Stand in for the awaited tween: the ride has begun and the car is gone before it finishes.
	InputLockManager.push_lock(lift.LOCK_ID)
	lift._holds_lock = true
	assert_true(ilm.is_locked(), "PRECONDITION: the ride holds the lock")
	lift.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var still: bool = ilm.is_locked()
	_drain(ilm, "village_elevator")
	assert_false(still, "an elevator freed mid-ride left its lock held into the next scene")


## Ratchet: a future holder cannot ship the same shape. Every file that CALLS push_lock must define
## a teardown. Source-level because the defect is a missing path, and a missing path has no runtime.
func test_every_lock_holder_defines_a_teardown() -> void:
	var offenders: Array = []
	var checked := 0
	var files: Array = []
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var e: String = dir.get_next()
		while e != "":
			if dir.current_is_dir():
				stack.append(d + "/" + e)
			elif e.ends_with(".gd"):
				files.append(d + "/" + e)
			e = dir.get_next()
		dir.list_dir_end()
	files.sort()

	for path in files:
		if path.ends_with("InputLockManager.gd"):
			continue  # the manager defines push_lock, it does not hold one
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var code := ""
		for line in src.split("\n"):
			var l := str(line)
			var at := l.find("#")
			code += (l.substr(0, at) if at >= 0 else l) + "\n"
		if not code.contains("push_lock("):
			continue
		checked += 1
		if not code.contains("func _exit_tree("):
			offenders.append("%s calls push_lock and defines no _exit_tree — a free during its await leaves the player frozen" % str(path).get_file())
	assert_gt(checked, 5,
		"CONTROL: only %d files call push_lock — the scan is broken and the [] below is free" % checked)
	offenders.sort()
	assert_eq(offenders, [], "a lock holder has no teardown path: %s" % ", ".join(offenders))
