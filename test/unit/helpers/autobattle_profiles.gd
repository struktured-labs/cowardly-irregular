extends RefCounted
## Snapshot/restore the WHOLE AutobattleSystem.character_profiles map.
##
## Instantiating AutobattleGridEditor registers a profile on the autoload — keyed by whatever
## character_id the editor holds, which is "" when nothing sets one — and it outlives the file.
## The key is registered three calls down (editor -> get_character_script -> _ensure_character_
## profiles), so a file can cause it without naming it, and a teardown erasing the keys the file
## WROTE cannot reach it. Restore the container, never the keys you thought of.
##
## The autoload is passed IN rather than resolved here: an autoload read from a `static func`
## aborts and yields the return type's default, which for this would be an empty map — silently
## restoring nothing while every arm stays green.
##
## ⚠️ RESTORE TARGET: the PRIOR SNAPSHOT, not a declared default. That makes this a CONDUIT —
## it does not mask an upstream leaker, and it gives a wired file no immunity of its own. A
## sibling helper restoring to DECLARED DEFAULTS is a BARRIER instead: it cleans up whoever
## leaked before it, so anything probing downstream sees clean and the real polluter is
## invisible. Neither is wrong; they answer different questions, and a probe run after a wired
## file means different things under each. Stated because the fleet wrote three teardown helpers
## in one night with three restore targets and none of them said which.
##
## POSITION: both calls are safe anywhere in their hook BECAUSE they cannot abort — the null
## guards above return rather than throwing. That matters: a restore placed LAST is skipped
## entirely if any line above it errors, and a snapshot placed below one captures nothing and
## then writes an empty baseline over live state. Placing either first is only available when
## nothing after it writes character_profiles; it is not a general rule.


static func snapshot(abs_sys) -> Dictionary:
	if abs_sys == null or not ("character_profiles" in abs_sys):
		return {}
	return (abs_sys.character_profiles as Dictionary).duplicate(true)


static func restore(abs_sys, entry: Dictionary) -> void:
	if abs_sys == null or not ("character_profiles" in abs_sys):
		return
	var live: Dictionary = abs_sys.character_profiles
	live.clear()
	for k in entry:
		live[k] = entry[k]
