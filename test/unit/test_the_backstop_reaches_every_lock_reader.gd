extends GutTest

## InputLockManager reaps any lock held past STALE_TIMEOUT_MS. That backstop exists because a
## holder can die mid-tween and never pop — and a lock nothing can clear freezes the player.
##
## ⛔ THE BACKSTOP IS CENTRALISED, NOT AUTOMATIC: `_reap_stale()` is one function, but a reader
## only gets it by CALLING it. `ab93b8265` fixed `has_lock` under the title "the stale-lock
## backstop reaches both readers, not one" — there were THREE. `get_active_locks` sat four lines
## below `is_locked` returning `_locks.keys()` raw, so the one API whose entire job is answering
## "what is held right now?" answered with locks the backstop had already expired.
##
## The derived arm below is the part that outlives this fix: it reads this file's own source and
## requires the backstop of EVERY public reader, so a fourth cannot arrive quietly the way the
## third did.

const ILM_PATH := "res://src/input/InputLockManager.gd"
const AGED := "aged_holder"
const FRESH := "fresh_holder"


func _ilm() -> Node:
	return get_node_or_null("/root/InputLockManager")


func after_each() -> void:
	var ilm: Node = _ilm()
	if ilm != null:
		ilm.pop_all()


## Ages a lock past the timeout using the same seam test_input_lock_heartbeat_regression uses.
func _age(ilm: Node, lock_id: String) -> void:
	ilm._locks[lock_id] = Time.get_ticks_msec() - (ilm.STALE_TIMEOUT_MS + 5000)


## ⛔ ONE ARM PER READER, EACH WITH ITS OWN AGED LOCK, AND NO SIBLING CALLED BEFORE IT.
## `_reap_stale()` mutates, so ANY reader that reaps hands the next one a clean dict. Asserting
## all three in sequence made `get_active_locks` pass on the live bug, because `is_locked` above
## it had already done the reaping — which is the precise mechanism `InputLockManager.gd:22`
## records as having hidden the SECOND reader. A shared arrangement cannot test a shared reaper.
func test_is_locked_hides_an_expired_lock() -> void:
	var ilm: Node = _ilm()
	assert_not_null(ilm, "CONTROL: InputLockManager autoload must be present")
	if ilm == null:
		return
	ilm.push_lock(FRESH)
	assert_true(ilm.is_locked(), "CONTROL: is_locked must see a fresh lock")
	ilm.pop_all()
	_age(ilm, AGED)
	assert_false(ilm.is_locked(), "is_locked must not report an expired lock")


func test_has_lock_hides_an_expired_lock() -> void:
	var ilm: Node = _ilm()
	assert_not_null(ilm, "CONTROL: InputLockManager autoload must be present")
	if ilm == null:
		return
	ilm.push_lock(FRESH)
	assert_true(ilm.has_lock(FRESH), "CONTROL: has_lock must see a fresh lock")
	ilm.pop_all()
	_age(ilm, AGED)
	assert_false(ilm.has_lock(AGED), "has_lock must not report an expired lock")


func test_get_active_locks_hides_an_expired_lock() -> void:
	var ilm: Node = _ilm()
	assert_not_null(ilm, "CONTROL: InputLockManager autoload must be present")
	if ilm == null:
		return
	ilm.push_lock(FRESH)
	assert_true(FRESH in ilm.get_active_locks(),
		"CONTROL: get_active_locks must see a fresh lock, or the staleness arm measures nothing")
	ilm.pop_all()
	_age(ilm, AGED)
	## Nothing above this line calls another reader, so nothing has reaped on its behalf.
	assert_false(AGED in ilm.get_active_locks(),
		"get_active_locks reported '%s' after the backstop expired it — the reader that answers "
		% AGED + "'what is held?' must not be the one that skips the reap")


func test_reaping_one_reader_does_not_disturb_a_live_lock() -> void:
	var ilm: Node = _ilm()
	assert_not_null(ilm, "CONTROL: InputLockManager autoload must be present")
	if ilm == null:
		return

	## A reap added to a reader must expire ONLY what aged out. A blanket clear would satisfy the
	## file above and silently break every live lock in the game.
	_age(ilm, AGED)
	ilm.push_lock(FRESH)
	var held: Array = ilm.get_active_locks()
	assert_true(FRESH in held, "the live lock must survive a reap triggered by its stale neighbour")
	assert_false(AGED in held, "CONTROL: the aged lock must still be gone, or this proves nothing")
	assert_eq(held.size(), 1, "exactly the live lock should remain, got %s" % [held])


## Derived from the autoload's own source, so it cannot go stale against a rename or a new reader.
## A READER is a public func returning a value computed from `_locks`; writers (push/pop/pop_all)
## return void and must NOT reap.
func test_no_public_reader_skips_the_backstop() -> void:
	var src: String = FileAccess.get_file_as_string(ILM_PATH)
	assert_gt(src.length(), 0, "CONTROL: must be able to read %s" % ILM_PATH)
	if src.is_empty():
		return

	var readers: Array = []
	var unreaped: Array = []
	var chunks: PackedStringArray = ("\n" + src).split("\nfunc ")
	for i in range(1, chunks.size()):
		var chunk: String = chunks[i]
		var name: String = chunk.substr(0, chunk.find("("))
		if name.begins_with("_"):
			continue
		var returns_locks: bool = false
		for line in chunk.split("\n"):
			var stripped: String = line.strip_edges()
			if stripped.begins_with("return") and stripped.contains("_locks"):
				returns_locks = true
				break
		if not returns_locks:
			continue
		readers.append(name)
		if not chunk.contains("_reap_stale()"):
			unreaped.append(name)

	## CONTROL: the derivation must actually find the readers. An empty set would pass the assert
	## below while measuring nothing — the exact shape that let the third reader through.
	assert_true(readers.size() >= 3,
		"CONTROL: expected at least the three known readers, derived %s" % [readers])
	assert_true(unreaped.is_empty(),
		"public reader(s) %s return state derived from _locks without calling _reap_stale() — " % [unreaped]
		+ "the backstop is centralised, not automatic, so each reader must call it")
