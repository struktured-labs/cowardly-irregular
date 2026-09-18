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
