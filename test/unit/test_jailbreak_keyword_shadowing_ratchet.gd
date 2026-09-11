extends GutTest

## No authored jailbreak keyword may be unreachable behind an earlier one.
##
## THE MATCHER IS SUBSTRING + FIRST-MATCH-WINS. `BossDialogue.check_jailbreak`
## walks `jailbreak_vulnerabilities` in order and returns the first whose
## trigger_keywords appear anywhere in the player's directive. So if an EARLIER
## vulnerability lists "fear" and a LATER one lists "fear of the dark", the
## longer phrase can never fire — any directive containing it also contains
## "fear", and the earlier vulnerability answers first.
##
## The player types the exact phrase the writer intended and nothing happens.
## No error, no warning, no log line — the other consequence just plays.
##
## CURRENTLY CLEAN: 99 keywords, 0 shadowed (measured 2026-07-29). This exists
## because nothing was keeping it clean and the corpus grows by hand. Same
## reason as the arm-order pin on _detect_playstyle: shadowing is invisible at
## authoring time, because each keyword reads perfectly well on its own line.
##
## THE PREMISE IS ASSERTED, NOT ASSUMED — and it is now asserted by
## DEMONSTRATION rather than by reading the matcher's source.
##
## 2026-09-10: the matcher changed. It was substring-matching, which fired 'king'
## inside asking/thinking/making and made the W1 final boss skip her turn on
## almost any sentence (11 of 12 ordinary directives triggered a jailbreak). It
## now matches single words whole and phrases as phrases. This file's original
## premise test pinned the literal source `lower.find(kw_s) != -1` and correctly
## went red on that change — it did its job and sent the reader here.
##
## Shadowing SURVIVES the change, so the rule is still the right question: an
## earlier single word still swallows a later phrase that contains it, because
## the phrase contains that whole word ('fear' still shadows 'fear of the dark').
## What changed is the RELATION — it is no longer plain string containment, since
## 'king' no longer shadows 'kingdom'.
##
## So the sweep below now ASKS THE REAL MATCHER instead of re-deriving its rule,
## which makes it immune to the next matcher change, and
## test_shadowing_is_still_possible_under_the_current_matcher proves the question
## is live by constructing a shadow and watching it happen. A source-string pin
## could only detect that something changed; a demonstration shows the sweep is
## still capable of failing, which is the property that actually matters.

const DIALOGUE_PATH: String = "res://data/boss_dialogue.json"
const MATCHER_PATH: String = "res://src/llm/BossDialogue.gd"


func _entries() -> Dictionary:
	var j := JSON.new()
	assert_eq(j.parse(FileAccess.get_file_as_string(DIALOGUE_PATH)), OK, "boss_dialogue.json must parse")
	return j.data as Dictionary if j.data is Dictionary else {}


## [{boss, id, keywords:[...]}] in authored order.
func _vulns() -> Array:
	var out: Array = []
	for boss in _entries().keys():
		var v: Variant = _entries()[boss]
		if not (v is Dictionary):
			continue
		for raw in ((v as Dictionary).get("jailbreak_vulnerabilities", []) as Array):
			if not (raw is Dictionary):
				continue
			var kws: Array = []
			for k in ((raw as Dictionary).get("trigger_keywords", []) as Array):
				var s: String = str(k).to_lower().strip_edges()
				if s != "":
					kws.append(s)
			out.append({"boss": str(boss), "id": str((raw as Dictionary).get("id", "?")), "keywords": kws})
	return out


# ── The premise this file's rule depends on ─────────────────────────────────

var _saved_data: Dictionary = {}


func before_each() -> void:
	_saved_data = BossDialogue._data.duplicate(true)


func after_each() -> void:
	## BossDialogue is an autoload; a leaked _data edit corrupts every later test.
	BossDialogue._data = _saved_data


func test_shadowing_is_still_possible_under_the_current_matcher() -> void:
	## Non-vacuity, shown rather than argued. If a future matcher makes shadowing
	## impossible, this fails and the sweep below is no longer worth running.
	BossDialogue._data["chancellor_mordaine"]["jailbreak_vulnerabilities"] = [
		{"id": "earlier_short", "trigger_keywords": ["fear"],
		 "consequence": {"type": "skip_turn"}},
		{"id": "later_phrase", "trigger_keywords": ["fear of the dark"],
		 "consequence": {"type": "taunt_softens"}},
	]
	var got = BossDialogue.check_jailbreak("chancellor_mordaine", "fear of the dark")
	assert_not_null(got, "CONTROL: the constructed directive must match something")
	assert_eq(str((got as Dictionary)["vulnerability_id"]), "earlier_short",
		("shadowing must still be POSSIBLE, or this file checks a condition that cannot occur " +
		"and would stay green forever. If this fails, re-read the header before trusting the sweep."))


# ── Positive controls ────────────────────────────────────────────────────────

func test_scan_finds_the_authored_corpus() -> void:
	var vulns: Array = _vulns()
	assert_gt(vulns.size(), 5,
		"found only %d vulnerabilities — the JSON walk has broken, so 0 shadows would prove nothing" % vulns.size())
	var total: int = 0
	for v in vulns:
		total += (v["keywords"] as Array).size()
	assert_gt(total, 10, "found only %d keywords — the walk has broken" % total)


# ── The guard ────────────────────────────────────────────────────────────────

func test_no_keyword_is_shadowed_by_an_earlier_one() -> void:
	## Behavioural: type each authored keyword as the directive and require its own
	## vulnerability to answer. Asking the matcher rather than re-implementing its
	## rule is what keeps this correct across matcher changes — the previous
	## version encoded substring-containment and would have reported 'kingdom' as
	## shadowed by 'king' the moment whole-word matching landed.
	var checked: int = 0
	for v in _vulns():
		var boss: String = str(v["boss"])
		var vid: String = str(v["id"])
		for kw in (v["keywords"] as Array):
			var got = BossDialogue.check_jailbreak(boss, str(kw))
			checked += 1
			assert_not_null(got,
				"[%s] keyword '%s' on '%s' matches NOTHING — it can never fire" % [boss, kw, vid])
			if got == null:
				continue
			assert_eq(str((got as Dictionary)["vulnerability_id"]), vid,
				("[%s] keyword '%s' on vulnerability '%s' can NEVER fire: an earlier vulnerability " +
				"('%s') answers first. A player typing it gets the earlier consequence instead — " +
				"silently. Reorder the vulnerabilities, or narrow the earlier keyword.")
				% [boss, kw, vid, str((got as Dictionary)["vulnerability_id"])])
	assert_gt(checked, 10,
		"CONTROL: only %d keywords exercised — the corpus walk has broken, so 0 shadows proves nothing" % checked)
