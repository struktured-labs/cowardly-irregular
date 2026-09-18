extends RefCounted

## Whole-surface snapshot/restore of the AutogrindSystem autoload, for test teardown.
##
## ⛔ WHOLE-SURFACE BECAUSE A HAND-LISTED TEARDOWN CANNOT COVER WHAT THE FILE NEVER NAMES.
## Measured 2026-09-17, in-process before/after probe: the two gold files leak NINE fields and
## NAME exactly two. The other seven are written by `on_battle_victory()` — a file that drives one
## grind victory mutates the efficiency ladder, the corruption ladder, the win streak and the
## battle counter without any of those words appearing in it. Three files in this lane carry a
## correct `_FIELDS`/`_DICTS` list today; the list is a snapshot of what its author knew the
## subject wrote, which is the same defect shape as a hand-listed floor.
##
## The fields are derived from the autoload's own property list, so a new `var` is covered the day
## it lands rather than the day someone remembers to add it.

const _FLAG := "_test_disable_persistence"


## Every script variable on the autoload, deep-copied so a later mutation cannot reach the snapshot.
static func snapshot() -> Dictionary:
	var snap: Dictionary = {}
	for p in AutogrindSystem.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = str(p["name"])
		var v: Variant = AutogrindSystem.get(n)
		if v is Dictionary:
			snap[n] = (v as Dictionary).duplicate(true)
		elif v is Array:
			snap[n] = (v as Array).duplicate()
		else:
			snap[n] = v
	return snap


## Snapshot, then disable persistence — the pair every autogrind test opens with.
static func snapshot_and_isolate() -> Dictionary:
	var snap: Dictionary = snapshot()
	AutogrindSystem._test_disable_persistence = true
	return snap


static func restore(snap: Dictionary) -> void:
	## ⛔ SEVER BEFORE RESTORING. `_ability_learned_conns` is not a value — it holds LIVE signal
	## connections to Combatants, and `_rare_drop_conn` one to BattleManager. Assigning the old
	## array back drops the record while leaving the connection attached, which is strictly worse
	## than the leak: the disarm path can no longer find it. `_unwire_smart_interrupt_signals`
	## already guards `is_instance_valid`, so it is safe on members GUT has freed.
	if AutogrindSystem._ability_learned_conns.size() > 0 or AutogrindSystem._rare_drop_conn.is_valid():
		AutogrindSystem._unwire_smart_interrupt_signals()
	for n in snap:
		var want: Variant = snap[n]
		var cur: Variant = AutogrindSystem.get(n)
		## In-place for containers: `grind_party` is `Array[Combatant]` and rejects an untyped
		## assign, and anything already holding the old reference must see the restored contents.
		if want is Array and cur is Array:
			(cur as Array).assign(want)
		elif want is Dictionary and cur is Dictionary:
			(cur as Dictionary).clear()
			(cur as Dictionary).merge(want)
		else:
			AutogrindSystem.set(n, want)


## Fields that differ from `snap` — the assertable form of the throwaway probe this was built with.
static func leaked(snap: Dictionary) -> Array:
	var out: Array = []
	for n in snap:
		if str(AutogrindSystem.get(n)) != str(snap[n]):
			out.append("%s: %s -> %s" % [n, str(snap[n]), str(AutogrindSystem.get(n))])
	out.sort()
	return out
