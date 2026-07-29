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
## THE PREMISE IS ASSERTED, NOT ASSUMED. The shadow rule is only valid while
## matching is substring-based and stops at the first hit. Switch to exact
## match and shadowing becomes impossible — this file would then be green
## forever while checking a condition that can no longer occur, which is worse
## than being wrong. test_matcher_is_still_substring_first_match fails in that
## case and sends the reader here.

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

func test_matcher_is_still_substring_first_match() -> void:
	# If this changes, the shadow rule below is no longer the right question.
	var src: String = FileAccess.get_file_as_string(MATCHER_PATH)
	assert_false(src.is_empty(), "BossDialogue must be readable")
	var at: int = src.find("func check_jailbreak")
	assert_gt(at, -1, "check_jailbreak must exist — if renamed, this ratchet measures nothing")
	if at == -1:
		return
	var end: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (end if end != -1 else src.length()) - at)
	assert_true(body.find("lower.find(kw_s) != -1") != -1,
		("check_jailbreak no longer substring-matches keywords. PREMISE BROKEN: this file's shadowing " +
		"rule assumes a shorter earlier keyword can swallow a longer later one. Under exact matching " +
		"that cannot happen and the sweep below would pass forever while checking nothing — re-read it " +
		"before trusting a green result here."))
	assert_true(body.find("break") != -1 and body.find("return {") != -1,
		"check_jailbreak must still stop at the FIRST matching vulnerability — ordering is what creates the shadow")


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
	# Per boss: a later keyword containing an earlier keyword can never fire.
	var by_boss: Dictionary = {}
	for v in _vulns():
		var b: String = str(v["boss"])
		if not by_boss.has(b):
			by_boss[b] = []
		(by_boss[b] as Array).append(v)
	for boss in by_boss.keys():
		var list: Array = by_boss[boss]
		for j in range(list.size()):
			for kj in ((list[j] as Dictionary)["keywords"] as Array):
				for i in range(j):
					for ki in ((list[i] as Dictionary)["keywords"] as Array):
						assert_false(str(kj).find(str(ki)) != -1,
							("[%s] keyword '%s' on vulnerability '%s' can NEVER fire: '%s' on the earlier " +
							"vulnerability '%s' is a substring of it, and check_jailbreak returns at the " +
							"first match. A player typing the longer phrase gets the earlier consequence " +
							"instead — silently. Reorder the vulnerabilities, or narrow the earlier keyword.")
							% [boss, kj, (list[j] as Dictionary)["id"], ki, (list[i] as Dictionary)["id"]])
