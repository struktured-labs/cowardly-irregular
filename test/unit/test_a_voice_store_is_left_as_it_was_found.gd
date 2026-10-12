extends GutTest

## `PartyPersonas._recent_spoken` became a READ source on 2026-10-12 (the scripted pick now uses the
## same half-pool window the LLM path had), and it is autoload state, so it outlives a test FILE.
## cowir-ai measured the consequence on main: test_a_trigger_can_speak_many_lines passes alone and
## reds after a file that drives the battle path, because a leaked `rogue|turn_start` index is excluded
## from the window and one of three variants becomes unreachable. Reproduced here before fixing:
## `run_tests.sh a_line_asked_for_in_battle_never_lands_after_it a_trigger_can_speak_many_lines`
## gave Failing 2 ("every variant must be reachable, saw [turn_start_2, turn_start]"); alone, 6/6.
##
## Full-suite order happened to pass that day, so nothing would have caught the next reordering.
##
## This guard DERIVES the population rather than listing it, because the symbol grep misses the files
## that matter most: the leaker names no store API at all — it drives `_run_party_line_async`, whose
## emit sites call `mark_spoken` transitively. A grep for `pick_trigger_voice|mark_spoken` found 7
## files of which 2 were false hits (one scans BattleManager's source text for the string, one has it
## in a comment); the real set is 10, via the battle entry points as well.

const STORE := "_recent_spoken"
## The runtime calls that can WRITE it. The battle entry points are here because the file that caused
## the measured red names no store API at all — its emit sites call mark_spoken transitively.
const CALLS := ["pick_trigger_voice(", "mark_spoken(", "_run_party_line_async(",
		"_dispatch_victory_party_line(", "maybe_fire_party_line("]
const DIR := "res://test/unit"

var _restore_job := ""
var _restore_trig := ""
var _restore_lines: Variant = null


## This file drives the store too, so it obeys the rule it enforces.
func after_each() -> void:
	if _restore_job != "" and _restore_lines != null:
		PartyPersonas._data[_restore_job]["trigger_voices"][_restore_trig] = _restore_lines
		_restore_job = ""
	PartyPersonas._recent_spoken.clear()
	PartyPersonas._last_variant.clear()


## A call named inside a double-quoted string is a SOURCE SCAN, not a call: three of this corpus's
## files read BattleManager.gd as text and would otherwise be required to isolate state they never touch.
func _runtime_call_count(src: String) -> int:
	var n := 0
	for raw in src.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			continue
		var bare := ""
		var in_str := false
		for i in raw.length():
			var c := raw[i]
			if c == "\"":
				in_str = not in_str
				continue
			if not in_str:
				bare += c
		for c in CALLS:
			if bare.contains(c):
				n += 1
	return n


## MENTIONING the store is not restoring it — a file that WRITES it contains the name too, and an
## earlier version of this guard passed on that basis (it survived its own mutation, because deleting
## the reset left the planting line behind). So require an emptying write INSIDE before_each or
## after_each: that is the behaviour, where the name is only the spelling.
func _resets_in_a_fixture(src: String, store: String) -> bool:
	for fn in ["before_each", "after_each"]:
		var at: int = src.find("func %s(" % fn)
		if at < 0:
			continue
		var end: int = src.find("\nfunc ", at + 1)
		var body: String = src.substr(at, (end - at) if end > at else -1)
		if body.contains("%s.clear()" % store) or body.contains("%s = {}" % store) \
				or body.contains("%s = " % store):          # snapshot/restore is equally valid
			return true
	return false


func _test_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	assert_not_null(d, "VOID: cannot open %s, so nothing below is derived" % DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func test_every_file_that_can_write_the_store_puts_it_back() -> void:
	var drivers: Array = []
	var leaking: Array = []
	for name in _test_files():
		var src := FileAccess.get_file_as_string("%s/%s" % [DIR, name])
		if _runtime_call_count(src) == 0:
			continue
		drivers.append(name)
		if not _resets_in_a_fixture(src, STORE):
			leaking.append(name)
	## Without this a renamed entry point would empty the corpus and the arm would pass checking nothing.
	assert_gt(drivers.size(), 5,
		"VOID: only %d files derived as store writers — the entry-point names in CALLS have drifted, so this arm is no longer checking the corpus it describes" % drivers.size())
	assert_eq(leaking, [],
		"these test files can write PartyPersonas.%s and never put it back in a fixture, so they leak the pick window into whatever file GUT runs next (%d of %d drivers): %s" % [STORE, leaking.size(), drivers.size(), leaking])


func test_the_store_is_actually_read_by_the_pick() -> void:
	## The guard above is only worth running while the store is load-bearing. If the pick stops reading
	## it, this says so instead of silently defending dead state.
	var src := FileAccess.get_file_as_string("res://src/llm/PartyPersonas.gd")
	assert_gt(src.length(), 0, "VOID: PartyPersonas.gd read empty")
	assert_true(src.contains("VoiceLines.choice_pool(entries, recent_spoken("),
		"the scripted pick no longer reads the recent window — if that was deliberate, this whole guard can go")


func test_a_leaked_index_really_does_hide_a_variant() -> void:
	## The mechanism, driven rather than described: with an index in the store, a 2-line pool can only
	## return the other one. This is why the victim file saw 2 of 3 variants.
	var job := "rogue"
	var trig := "turn_start"
	var saved: Variant = PartyPersonas._data[job]["trigger_voices"].get(trig, null)
	var saved_recent: Dictionary = PartyPersonas._recent_spoken.duplicate(true)
	var saved_last: Dictionary = PartyPersonas._last_variant.duplicate(true)
	_restore_job = job
	_restore_trig = trig
	_restore_lines = saved
	PartyPersonas._data[job]["trigger_voices"][trig] = ["zero", "one"]
	PartyPersonas._recent_spoken.clear()
	PartyPersonas._last_variant.clear()
	PartyPersonas.mark_spoken(job, trig, 1)          # what a previous FILE would have left behind
	var seen := {}
	for i in 20:
		seen[int(PartyPersonas.pick_trigger_voice(job, trig).get("index", -1))] = true
	var leaked_seen: Array = seen.keys()
	PartyPersonas._recent_spoken.clear()
	PartyPersonas._last_variant.clear()
	seen = {}
	for i in 20:
		seen[int(PartyPersonas.pick_trigger_voice(job, trig).get("index", -1))] = true
	var clean_seen: int = seen.size()
	if saved != null:
		PartyPersonas._data[job]["trigger_voices"][trig] = saved
	PartyPersonas._recent_spoken = saved_recent
	PartyPersonas._last_variant = saved_last
	assert_eq(leaked_seen, [0],
		"a leaked index must hide its variant — saw %s, so the exclusion this guard defends against is not happening" % [leaked_seen])
	assert_eq(clean_seen, 2, "CONTROL: with the store clear, both variants must be reachable, saw %d" % clean_seen)
