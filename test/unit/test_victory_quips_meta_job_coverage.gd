extends GutTest

## tick 289: VICTORY_QUIPS now has lines for all 5 meta jobs.
##
## Pre-fix VICTORY_QUIPS covered the 5 starter jobs + the 4 advanced
## jobs but NOT the 5 meta jobs (scriptweaver / time_mage /
## necromancer / bossbinder / skiptrotter). _show_victory_quip's
## fallback to "_default" served bland "Victory!" / "We did it!"
## lines for any meta-job PC who finished a battle in their job slot.
##
## Mirrors the tick-124 JOB_QUIP_COLORS extension that fixed the
## per-job bubble color story for the same 5 meta jobs (colors were
## fixed there; the lines themselves were missed).
##
## Coverage pin so a future content drop doesn't drop a job without
## quips.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


# All job ids that must have at least one quip entry in VICTORY_QUIPS.
# Starter (5) + Advanced (4) + Meta (5) = 14 jobs total per CLAUDE.md.
const ALL_JOB_IDS: Array[String] = [
	# Starter
	"fighter", "cleric", "mage", "rogue", "bard",
	# Advanced
	"guardian", "ninja", "summoner", "speculator",
	# Meta
	"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _quips_dict() -> Dictionary:
	# Parse the VICTORY_QUIPS const out of the source file. Simpler
	# than loading + instantiating BattleScene.
	var src := _read(BATTLE_SCENE)
	var start: int = src.find("const VICTORY_QUIPS: Dictionary = {")
	assert_gt(start, -1, "VICTORY_QUIPS const must exist")
	var rx := RegEx.new()
	# Match "<id>": [array] entries inside the dict.
	rx.compile("\"([a-z_]+)\":\\s*\\[")
	var out: Dictionary = {}
	for m in rx.search_all(src.substr(start, src.find("\n}", start) - start)):
		out[m.get_string(1)] = true
	return out


# ── Every job (incl. meta) has a quip array ───────────────────────

func test_every_job_id_has_quips() -> void:
	var quips: Dictionary = _quips_dict()
	var missing: Array[String] = []
	for jid in ALL_JOB_IDS:
		if not quips.has(jid):
			missing.append(jid)
	assert_eq(missing.size(), 0,
		"VICTORY_QUIPS must cover every job id: %s" % str(missing))


# ── Default fallback still present ────────────────────────────────

func test_default_fallback_present() -> void:
	var quips: Dictionary = _quips_dict()
	assert_true(quips.has("_default"),
		"_default fallback array must remain for unknown/custom jobs")


# ── Meta jobs each have at least 3 quips (parity with others) ────

func test_meta_jobs_have_multiple_quips() -> void:
	var src := _read(BATTLE_SCENE)
	# Spot-check each meta job by counting quoted strings between
	# its key and the next "]" — should be ≥3 (parity with starter
	# jobs which have 4 quips each).
	const META_JOBS := ["scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"]
	var thin: Array[String] = []
	for jid in META_JOBS:
		var key: String = "\"%s\": [" % jid
		var key_idx: int = src.find(key)
		assert_gt(key_idx, -1, "%s key must be present" % jid)
		var end_idx: int = src.find("]", key_idx)
		var slice: String = src.substr(key_idx, end_idx - key_idx + 1)
		# Count comma-separated string literals (rough heuristic).
		var quote_count: int = slice.count("\"")
		# Each string contributes 2 quotes. Subtract 2 for the key name.
		var string_count: int = (quote_count - 2) / 2
		if string_count < 3:
			thin.append("%s has only %d quips" % [jid, string_count])
	assert_eq(thin.size(), 0,
		"meta jobs should have at least 3 quips each (parity with starter jobs): %s" % str(thin))


# ── Cross-pin: JOB_QUIP_COLORS still has the 5 meta jobs ─────────

func test_job_quip_colors_meta_jobs_preserved() -> void:
	# Tick 124 fixed the colors. This test catches a regression if
	# anyone removes the meta job color entries.
	var src := _read(BATTLE_SCENE)
	for jid in ["scriptweaver", "time_mage", "necromancer", "bossbinder"]:
		assert_true(src.contains("\"%s\": Color(" % jid),
			"JOB_QUIP_COLORS must still have entry for %s (tick 124 fix)" % jid)
