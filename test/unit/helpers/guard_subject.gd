extends RefCounted
## A guard that drives its subject BY NAME goes silent when the name changes.
##
## Measured across this lane 2026-09-16. Rename the method each guard drives and the run reports:
##
##   test_a_roaming_monster_reads_its_declared_sheet   EC=0 · Passing 5 · Asserts 73 -> 67
##   test_monster_facing_decoupled_from_scale          EC=0 · Passing 10 · Asserts 32 -> 26
##   test_bestiary_stat_panel_regression               EC=0 · Passing 3 · Asserts 12 -> 11
##   test_bestiary_defeated_ui_and_save_roundtrip      EC=0 · Passing 7 · Asserts 41 -> 24
##
## Every cardinal clean in all four. The arms assert FIRST and abort LATER, so GUT scores them
## Passing — cowir-ai's RUNG 3. `run_tests.sh`'s exit 4 fires when a test asserted NOTHING, so it
## structurally cannot see this rung; only a per-file floor can.
##
## 🔑 THE RUNG IS DECIDED BY HOW THE GUARD REACHES ITS SUBJECT, not by care (cowir-controller):
##
##   static on a preloaded script   parse-time   the script is DROPPED, EC=3   loud, needs no floor
##   instance method via .call()    runtime      rungs 1/2/3                   needs this
##   property via .get()/.set()     runtime      rungs 1/2/3                   needs a floor too
##
## ⚠️ AND THE PREDICTION IS ONLY STATIC FOR AN UNCONDITIONAL REACH (cowir-sfx). A call behind an
## `if`, a `continue` or a loop that may not run has no static rung — it is 1, 2, 3, or nothing,
## decided by data. cowir-cutscenes narrowed that usefully: a conditional reach PRECEDED BY AN
## ASSERT on the same condition is static again, because the branch cannot be skipped silently.
## This helper does not try to classify; it asserts existence, which is correct at every rung.
##
## 📌 WHY THIS IS SHARED AND THE TWO INLINE COPIES ARE GONE: they carried a retirement condition
## reading "if a THIRD guard needs this, promote it to a shared helper and delete both copies."
## A derived sweep then found two more in the same lane, so the condition fired within the hour.
## It is recorded because this fleet measured SIX private comment-strippers today and the lesson
## was that nobody writes the second copy on purpose.
##
## ⛔ `has_method` and `get_method_list` ANSWER rather than raising. An existence arm built on a
## direct reference aborts alongside the arms it exists to catch (cowir-sfx), which makes it
## decoration.


## Every `.call("name")` literal in a guard's OWN source, paired with whether the subject has it.
##
## Returns {"found": int, "missing": Array[String]}. `found` is the FLOOR: a caller must assert it
## is non-zero, because an extraction that matched nothing reports an empty `missing` and reads
## exactly like a clean subject.
static func audit_calls(own_source_path: String, subject: Object) -> Dictionary:
	var out := {"found": 0, "missing": [] as Array}
	var src := FileAccess.get_file_as_string(own_source_path)
	if src.length() < 200:
		return out
	var re := RegEx.new()
	re.compile('\\.call\\("([a-zA-Z_][a-zA-Z_0-9]*)"')
	var names := {}
	for m in re.search_all(src):
		names[m.get_string(1)] = true
	out["found"] = names.size()
	if subject == null:
		out["missing"] = names.keys()
		return out
	var missing: Array = []
	for n in names:
		if not subject.has_method(str(n)):
			missing.append(str(n))
	missing.sort()
	out["missing"] = missing
	return out


## The same question for properties reached by `.get("name")` / `.set("name", …)`.
##
## `Object.get()` returns null for an absent property AND for a property that is legitimately null,
## so existence is read off the property list rather than off the value.
static func audit_properties(own_source_path: String, subject: Object) -> Dictionary:
	var out := {"found": 0, "missing": [] as Array}
	var src := FileAccess.get_file_as_string(own_source_path)
	if src.length() < 200:
		return out
	var re := RegEx.new()
	re.compile('\\.(?:get|set)\\("(_[a-zA-Z_0-9]*)"')
	var names := {}
	for m in re.search_all(src):
		names[m.get_string(1)] = true
	out["found"] = names.size()
	if subject == null:
		out["missing"] = names.keys()
		return out
	var present := {}
	for p in subject.get_property_list():
		present[str(p.get("name", ""))] = true
	var missing: Array = []
	for n in names:
		if not present.has(str(n)):
			missing.append(str(n))
	missing.sort()
	out["missing"] = missing
	return out
