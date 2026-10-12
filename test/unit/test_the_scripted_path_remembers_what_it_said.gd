extends GutTest

## The LLM path has excluded a half-pool window of recently spoken lines since it was written; the
## SCRIPTED path — the one a player gets by DEFAULT, party_llm_dialogue_enabled being off — only
## avoided the single previous line. Simulated over 4,000 runs of 40 turns (2026-10-12), the Fighter's
## 10-line pool repeated a line heard in the last three turns on 19.8% of turns against the window's
## 0.0%, and his pool is the smallest in the pack (10 per trigger where the others carry 20-50).
##
## So the scripted pick now reads the same `recent_spoken` window. It does NOT write it: the scripted
## line is picked on EVERY party line and spoken on only some, so marking it at the pick would record
## lines nobody said — which is what `mark_spoken`'s own note forbids, and what broke two tests when
## this was first written that way. BattleManager marks it at each of the six sites that emit it.

const JOB := "rogue"
const TRIG := "turn_start"

var _saved: Variant = null


func before_each() -> void:
	_saved = PartyPersonas._data[JOB]["trigger_voices"].get(TRIG, null) if PartyPersonas._data.has(JOB) else null
	PartyPersonas._recent_spoken.clear()
	PartyPersonas._last_variant.clear()


func after_each() -> void:
	if _saved != null:
		PartyPersonas._data[JOB]["trigger_voices"][TRIG] = _saved
	PartyPersonas._recent_spoken.clear()
	PartyPersonas._last_variant.clear()


func _pool_of(n: int) -> void:
	var lines: Array = []
	for i in n:
		lines.append("line %d" % i)
	PartyPersonas._data[JOB]["trigger_voices"][TRIG] = lines


## Picking never records — only speaking does. Drives the pick directly and marks what it "spoke",
## the way BattleManager does, then measures what the window actually buys.
func _repeats_within_three(n: int, turns: int, mark: bool) -> int:
	_pool_of(n)
	PartyPersonas._recent_spoken.clear()
	PartyPersonas._last_variant.clear()
	var spoken: Array = []
	var near := 0
	for t in turns:
		var p: Dictionary = PartyPersonas.pick_trigger_voice(JOB, TRIG)
		var idx: int = int(p.get("index", -1))
		if idx in spoken.slice(maxi(0, spoken.size() - 3)):
			near += 1
		spoken.append(idx)
		if mark:
			PartyPersonas.mark_spoken(JOB, TRIG, idx)
	return near


func test_the_pick_reports_the_index_the_caller_must_mark() -> void:
	_pool_of(6)
	var p: Dictionary = PartyPersonas.pick_trigger_voice(JOB, TRIG)
	assert_true(p.has("index"), "the pick must name its index, or no caller can record what it spoke")
	var idx: int = int(p["index"])
	assert_between(idx, 0, 5, "index must be an ORIGINAL index into the authored list")
	assert_eq(p.get("voice_key"), VoiceLines.variant_key(TRIG, idx),
		"the clip key must name the same variant the index does")


func test_a_marked_pool_stops_repeating_inside_three_turns() -> void:
	## The claim, on the Fighter's pool size. Unmarked is the old behaviour and is the control: if it
	## also came back 0 this arm would prove nothing, because the window would not be what changed it.
	var marked: int = _repeats_within_three(10, 120, true)
	var unmarked: int = _repeats_within_three(10, 120, false)
	assert_eq(marked, 0, "a 10-line pool repeated a line heard in the last 3 turns %d times despite the window" % marked)
	assert_gt(unmarked, 0,
		"CONTROL: without marking, a 10-line pool must still repeat inside three turns — it did not, so the window is not what the arm above measured")


func test_nothing_is_ever_said_back_to_back_even_unmarked() -> void:
	## The guarantee pick_trigger_voice owes on its own: a caller that never marks still never hears
	## the same line twice running. This is why the 1-deep memory stays beside the window.
	_pool_of(3)
	var last := -1
	var btb := 0
	for i in 200:
		var idx: int = int(PartyPersonas.pick_trigger_voice(JOB, TRIG).get("index", -1))
		if idx == last:
			btb += 1
		last = idx
	assert_eq(btb, 0, "the same line came back to back %d times in 200 unmarked picks" % btb)


func test_a_two_line_pool_still_alternates() -> void:
	## The window is floor(n/2) = 1 here, so the deeper memory must not starve a tiny pool: both lines
	## must stay reachable, and neither may repeat.
	_pool_of(2)
	var seen := {}
	var last := -1
	var btb := 0
	for i in 40:
		var idx: int = int(PartyPersonas.pick_trigger_voice(JOB, TRIG).get("index", -1))
		seen[idx] = true
		if idx == last:
			btb += 1
		last = idx
		PartyPersonas.mark_spoken(JOB, TRIG, idx)
	assert_eq(seen.size(), 2, "a 2-line pool must use both lines, saw %s" % [seen.keys()])
	assert_eq(btb, 0, "a 2-line pool said the same line twice running %d times" % btb)


func test_the_emit_sites_are_the_ones_that_record() -> void:
	## Derived from BattleManager's own source: every place the scripted fallback is EMITTED must mark
	## it, and the pick must not. A new emit site added without marking goes silent, not wrong, so
	## nothing else would catch it.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_gt(src.length(), 0, "VOID: BattleManager.gd read empty")
	var emits := src.count("_emit_party_line(combatant, fallback, fallback_key)")
	var marks := src.count("_mark_scripted_spoken(pp, job_id, event_kind, fallback_index)")
	assert_gt(emits, 0, "VOID: no scripted-fallback emit found, so this arm checked nothing")
	assert_eq(marks, emits + 1,
		"%d scripted emits but %d marks: every fallback emit needs one, plus the late path where the LLM returned nothing usable" % [emits, marks])
	var ps := FileAccess.get_file_as_string("res://src/llm/PartyPersonas.gd")
	assert_false(ps.contains("mark_spoken(job_id, event_kind"),
		"pick_trigger_voice must not record: it is picked on every party line and spoken on only some")
