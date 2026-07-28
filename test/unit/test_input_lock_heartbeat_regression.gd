extends GutTest

## InputLockManager reaps any lock held longer than STALE_TIMEOUT_MS (10s). That timeout exists to
## clean up LEAKED locks — a holder that died without popping — but it cannot tell a leak from a
## holder that is simply still working. Two holders already learned this the hard way and each
## grew a heartbeat (re-pushing refreshes the timestamp):
##
##   cutscene            CutsceneDirector._process       v3.33.108, mid-cutscene interact leak
##   exploration_paused  OverworldController._process    2026-07-11, menu held open >10s
##
## `autogrind_summary` was added AFTER both, has the identical property — a modal the player READS,
## dismissed only by them — and never got one. Past 10 seconds the lock was reaped and the player
## walked the overworld with the summary still on screen: verbatim the 2026-07-14 playtest bug the
## lock was pushed to prevent. Textbook partial enumeration: the pattern was applied to the two cases
## that bit and never swept for siblings.
##
## THE INVARIANT: a lock released from a LAMBDA is released by an event of unbounded latency (a
## signal the player fires whenever they feel like it), so it must heartbeat. A lock released
## synchronously — a transition that pops when its await finishes — is bounded and does not.
## Currently zero exceptions, which is what makes this a guard rather than an allowlist.

const SRC_ROOT := "res://src"


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dirs: Array[String] = [root]
	while not dirs.is_empty():
		var current: String = dirs.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := "%s/%s" % [current, entry]
			if dir.current_is_dir():
				dirs.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found


## The quoted first argument of `call_name(` on this line, or "" if absent.
func _quoted_arg(line: String, call_name: String) -> String:
	var at := line.find(call_name)
	if at == -1:
		return ""
	var rest := line.substr(at + call_name.length())
	var open := rest.find("\"")
	if open == -1:
		return ""
	var close := rest.find("\"", open + 1)
	if close == -1:
		return ""
	return rest.substr(open + 1, close - open - 1)


## {pushed, heartbeated, lambda_released} — each a Dictionary used as a set of lock ids.
func _analyse_locks() -> Dictionary:
	var pushed := {}
	var heartbeated := {}
	var lambda_released := {}
	for path in _gd_files(SRC_ROOT):
		var txt := FileAccess.get_file_as_string(path)
		if not txt.contains("push_lock(") and not txt.contains("pop_lock("):
			continue
		var current_func := "<top>"
		var lambda_open := false
		for line in txt.split("\n"):
			if line.begins_with("func "):
				current_func = line.substr(5).split("(")[0].strip_edges()
				lambda_open = false
			# A lambda opening inside a function body: everything after it in this function is
			# deferred execution, so a pop there fires whenever the signal does.
			if line.contains("func(") or line.contains("func ("):
				if not line.begins_with("func "):
					lambda_open = true

			var pushed_id := _quoted_arg(line, "push_lock(")
			if pushed_id != "":
				pushed[pushed_id] = true
				if current_func == "_process":
					heartbeated[pushed_id] = true

			var popped_id := _quoted_arg(line, "pop_lock(")
			if popped_id != "" and lambda_open:
				lambda_released[popped_id] = true
	return {"pushed": pushed, "heartbeated": heartbeated, "lambda_released": lambda_released}


## THE GUARD.
func test_locks_released_by_a_signal_lambda_must_heartbeat() -> void:
	var analysis := _analyse_locks()
	var offenders: Array[String] = []
	for lock_id in analysis["lambda_released"]:
		if not analysis["heartbeated"].has(lock_id):
			offenders.append(lock_id)
	assert_eq(offenders, [] as Array[String],
		"these locks are released by a signal (unbounded hold) but never re-pushed, so InputLockManager's 10s stale expiry reaps them mid-hold and hands control back while the UI is still up: %s" % str(offenders))


## The specific regression, pinned by name.
func test_autogrind_summary_heartbeats() -> void:
	var analysis := _analyse_locks()
	assert_true(analysis["pushed"].has("autogrind_summary"), "the summary lock must still be pushed")
	assert_true(analysis["heartbeated"].has("autogrind_summary"),
		"the autogrind summary is a modal the player reads; without a heartbeat it is reaped after 10s and movement returns underneath it")


## Closes a false negative in the guard above, found by auditing its own exemption.
##
## The lambda rule exempts every lock it considers "bounded release" — but that verdict was inferred
## from the ABSENCE of a lambda-pop, and absence of a lambda-pop also matches absence of ANY pop.
## `encounter_transition` has one push and zero `pop_lock` calls anywhere in src/. It is fine: the
## push site documents that `pop_all` in `_start_exploration` clears it, and LoopState.BATTLE blocks
## movement independently long before the stale reaper fires. But the ORIGINAL guard could not tell
## that from a lock somebody simply forgot to release, which would freeze the player for 10s.
##
## So a lock with no paired pop must SAY what releases it. There is no suppression flag: you cannot
## silence this green, only explain it green, and the explanation is the thing that was missing.
func test_a_lock_with_no_paired_pop_must_document_what_releases_it() -> void:
	var undocumented: Array[String] = []
	var analysis := _analyse_locks()
	for lock_id in analysis["pushed"]:
		if analysis["heartbeated"].has(lock_id):
			continue
		var has_paired_pop := false
		var explained := false
		for path in _gd_files(SRC_ROOT):
			var txt := FileAccess.get_file_as_string(path)
			if txt.contains("pop_lock(\"%s\")" % lock_id):
				has_paired_pop = true
			# The release mechanism must be named WITHIN A FEW LINES of the push. A whole-file
			# search is vacuous — GameLoop mentions pop_all in four unrelated places, so the
			# first version of this check passed no matter what the comment said.
			var lines := txt.split("\n")
			for i in lines.size():
				if not lines[i].contains("push_lock(\"%s\")" % lock_id):
					continue
				for j in range(maxi(0, i - 4), mini(lines.size(), i + 3)):
					if lines[j].contains("pop_all"):
						explained = true
		if not has_paired_pop and not explained:
			undocumented.append(lock_id)
	assert_eq(undocumented, [] as Array[String],
		"these locks are pushed, never popped by name, and never heartbeated — either they leak and freeze the player until the 10s reaper, or something else releases them and that must be stated: %s" % str(undocumented))


## Guards the guard: if the scan stops finding the two known-good heartbeats, it has broken and would
## report a clean sweep over nothing. A zero-result checker and a correct one look identical.
func test_scanner_still_detects_the_known_heartbeats() -> void:
	var analysis := _analyse_locks()
	for known in ["cutscene", "exploration_paused"]:
		assert_true(analysis["heartbeated"].has(known),
			"scanner must still see the pre-existing '%s' heartbeat — if it cannot, an empty offender list proves nothing" % known)
	assert_gt(analysis["pushed"].size(), 3, "scanner must find the real set of lock ids")


## The stale timeout must stay meaningful: heartbeating means a leaked lock can no longer be reaped,
## so any heartbeated holder needs a release that fires on teardown, not only on user dismissal.
func test_heartbeated_summary_also_releases_on_teardown() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindSummary.gd")
	assert_true(src.contains("_exit_tree"),
		"a heartbeated lock is immune to the stale reaper, so its holder must pop on teardown or a non-dismiss free would freeze the player permanently")
	assert_true(src.contains("pop_lock(\"autogrind_summary\")"),
		"_exit_tree must actually release the lock")
