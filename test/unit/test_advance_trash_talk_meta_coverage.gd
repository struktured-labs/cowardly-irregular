extends GutTest

## tick 292: ADVANCE_TRASH_TALK meta-job coverage + correct fallback.
##
## Pre-fix two issues:
##
## 1. Only 5 starter + 4 advanced jobs were keyed. Missing 5 meta
##    jobs (scriptweaver / time_mage / necromancer / bossbinder /
##    skiptrotter).
##
## 2. The .get() fallback was `ADVANCE_TRASH_TALK["fighter"]` — so
##    any unknown / meta-job PC pulled FIGHTER lines instead of
##    their own voice. Quietly wrong-character dialogue.
##
## Both fixed: meta jobs have entries, fallback now reads
## ADVANCE_TRASH_TALK["_default"].
##
## Mirrors the tick 289-291 meta-job sweep across BattleScene's quip
## dicts. Different file, same content gap.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"

const META_JOB_IDS: Array[String] = [
	"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _dict_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var start: int = src.find("const ADVANCE_TRASH_TALK = {")
	assert_gt(start, -1, "ADVANCE_TRASH_TALK must exist")
	var end: int = src.find("\n}", start)
	return src.substr(start, end - start + 2)


# ── All 5 meta jobs covered ────────────────────────────────────────

func test_each_meta_job_has_entry() -> void:
	var body := _dict_body()
	var missing: Array[String] = []
	for jid in META_JOB_IDS:
		if not body.contains("\"%s\":" % jid):
			missing.append(jid)
	assert_eq(missing.size(), 0,
		"ADVANCE_TRASH_TALK must cover every meta job: %s" % str(missing))


# ── _default fallback present ────────────────────────────────────

func test_default_fallback_present() -> void:
	var body := _dict_body()
	assert_true(body.contains("\"_default\":"),
		"ADVANCE_TRASH_TALK must have a _default array for unknown jobs")


# ── Fallback in _execute_advance now uses _default, not fighter ──

func test_execute_advance_falls_back_to_default_not_fighter() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("ADVANCE_TRASH_TALK.get(job_id, ADVANCE_TRASH_TALK[\"_default\"])"),
		"_execute_advance must fall back to ADVANCE_TRASH_TALK[\"_default\"], not [\"fighter\"]")
	# Negative pin: the old fighter-fallback shape must be gone.
	assert_false(src.contains("ADVANCE_TRASH_TALK.get(job_id, ADVANCE_TRASH_TALK[\"fighter\"])"),
		"old fighter-fallback shape must be replaced (was giving meta-job PCs fighter lines)")


# ── Each meta-job entry has at least 3 quips (parity) ────────────

func test_each_meta_job_entry_has_3_plus_quips() -> void:
	var body := _dict_body()
	var thin: Array[String] = []
	for jid in META_JOB_IDS:
		var key: String = "\"%s\": [" % jid
		var key_idx: int = body.find(key)
		if key_idx < 0:
			continue
		var end_idx: int = body.find("]", key_idx)
		var slice: String = body.substr(key_idx, end_idx - key_idx + 1)
		var string_count: int = (slice.count("\"") - 2) / 2
		if string_count < 3:
			thin.append("%s has %d quips" % [jid, string_count])
	assert_eq(thin.size(), 0,
		"each meta job entry must have ≥3 quips (parity with starters): %s" % str(thin))
