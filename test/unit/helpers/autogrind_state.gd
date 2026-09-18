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
##
## ⛔ BUT THE SURFACE IS ONE AUTOLOAD, AND A SIGNAL CAN CARRY A WRITE OUTSIDE IT. `restore()` uses
## `set()`, which does NOT emit — so a test that mutated through an EMITTING door and is restored
## through this SILENT one leaves every listener holding the old value, and a whole-surface probe
## on AutogrindSystem still reads clean. That is the `.420` polluter's shape exactly (cowir-adhoc:
## restore through the same door you mutated through). The live exposure here is
## `meta_corruption_level`, which GameLoop reads at `_resolve_headless_battle` and
## `_on_autogrind_battle_ended` and pushes into `SoundManager.set_corruption_intensity()`.
## Measured 2026-09-18, in-process probe bracketing all 285 lane files, positive control at 0.42:
## the render is 0.0000 before and after, so NO file trips it today. That is a fact about today's
## corpus, not a property of this helper — a file that drives either GameLoop path with corruption
## set needs SoundManager restored too, and this helper will not do it for you.

## ⚠️ THIS RESTORES THE *PRIOR* SNAPSHOT, NEVER A DECLARED DEFAULT — so it is a CONDUIT, not a
## BARRIER, and 59 files now depend on that without it ever having been written down.
##
##   CONDUIT (this file, and @cowir-ai's autobattle_profiles.gd)
##     restores what the caller inherited -> cannot MASK an upstream leaker, and equally
##     does not CLEAN UP after one. Dirt entering this file leaves it.
##   BARRIER (@cowir-music's sound_state.gd, which restores DECLARED DEFAULTS)
##     leaves the autoload clean -> a probe running downstream of it reports clean about a
##     tree that is not, and the real polluter becomes invisible.
##   ORACLE (@cowir-battle's battle_state.dirty_fields(), read-only)
##     diffs against a FRESH INSTANCE, so "default" cannot drift from the code. It restores
##     nothing; battle_state's snapshot()/restore() half is a CONDUIT like this one.
##
## 🔑 THE CONSEQUENCE, from @cowir-battle measuring it the hard way: "this file no longer leaks"
## and "the suite is clean" are INDEPENDENT claims when the helper is a conduit. Their end-of-suite
## surface stayed dirty after the first fix and nothing said why. Do not read a green from a file
## wired to this as evidence about anything upstream of it.
##
## ⚠️ AND ITS POSITION IN after_each IS LOAD-BEARING: restore() must run AFTER every line that
## writes this autoload, because it restores rather than clears. That is the opposite constraint
## from a clearing helper, which can go first and is then immune to an abort above it
## (@cowir-sfx). A GDScript error above this call silently skips it and the file still passes.

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
