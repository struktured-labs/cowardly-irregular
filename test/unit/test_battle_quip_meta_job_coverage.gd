extends GutTest

## tick 290: meta-job coverage swept across the major quip dicts.
##
## Tick 289 added meta-job entries to VICTORY_QUIPS. The other quip
## dicts in BattleScene had the same gap — 5 meta jobs missing and
## (worse) no `_default` fallback either, so a meta-job PC starting
## a battle / first-encountering a monster / pooling AP into a brave
## simply got no flavor quip.
##
## Closed gaps:
##   BATTLE_START_QUIPS
##   NEW_MONSTER_QUIPS
##   BRAVE_QUIPS
##
## VICTORY_QUIPS already covered (tick 289).
##
## Smaller dicts (CRIT/OVERKILL/TAKE_BIG_DAMAGE/DODGE/LOW_HP/ALLY_KO)
## use `_default` fallbacks already; leaving those for content polish
## passes — the silent-fail isn't there.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"

const META_JOB_IDS: Array[String] = [
	"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter",
]

## Tick 291 extended the audit list to include the 6 reaction-quip
## dicts as well. All 10 now have meta-job coverage.
const DICTS_TO_AUDIT: Array[String] = [
	"BATTLE_START_QUIPS",
	"NEW_MONSTER_QUIPS",
	"BRAVE_QUIPS",
	"VICTORY_QUIPS",
	# Tick 291 additions:
	"CRIT_QUIPS",
	"OVERKILL_QUIPS",
	"TAKE_BIG_DAMAGE_QUIPS",
	"DODGE_QUIPS",
	"LOW_HP_QUIPS",
	"ALLY_KO_QUIPS",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# Extract a dict's body from the source.
func _dict_body(dict_name: String) -> String:
	var src := _read(BATTLE_SCENE)
	var start: int = src.find("const " + dict_name + ": Dictionary = {")
	if start < 0:
		return ""
	# Find the matching close brace at indentation 0.
	var end: int = src.find("\n}", start)
	return src.substr(start, end - start + 2)


# ── Each audited dict has all 5 meta jobs ─────────────────────────

func test_each_dict_has_all_meta_jobs() -> void:
	for dict_name in DICTS_TO_AUDIT:
		var body := _dict_body(dict_name)
		assert_ne(body, "", "%s must exist" % dict_name)
		var missing: Array[String] = []
		for jid in META_JOB_IDS:
			if not body.contains("\"%s\":" % jid):
				missing.append(jid)
		assert_eq(missing.size(), 0,
			"%s missing meta jobs: %s" % [dict_name, str(missing)])


# ── Each audited dict has a `_default` fallback ───────────────────

func test_each_dict_has_default_fallback() -> void:
	var no_default: Array[String] = []
	for dict_name in DICTS_TO_AUDIT:
		var body := _dict_body(dict_name)
		if not body.contains("\"_default\":"):
			no_default.append(dict_name)
	assert_eq(no_default.size(), 0,
		"each quip dict must have a \"_default\" fallback for unknown jobs: %s" % str(no_default))


# ── Each meta-job entry has at least 3 quips ─────────────────────

func test_each_meta_job_entry_has_3_plus_quips() -> void:
	var thin: Array[String] = []
	for dict_name in DICTS_TO_AUDIT:
		var body := _dict_body(dict_name)
		for jid in META_JOB_IDS:
			var key: String = "\"%s\": [" % jid
			var key_idx: int = body.find(key)
			if key_idx < 0:
				continue
			var end_idx: int = body.find("]", key_idx)
			var slice: String = body.substr(key_idx, end_idx - key_idx + 1)
			# Count quoted-string lits (each = 2 quote chars). Subtract
			# 2 for the key itself.
			var string_count: int = (slice.count("\"") - 2) / 2
			if string_count < 3:
				thin.append("%s[%s] has %d quips" % [dict_name, jid, string_count])
	assert_eq(thin.size(), 0,
		"each meta job entry must have ≥3 quips (parity with VICTORY_QUIPS tick 289): %s" % str(thin))


# ── Cross-pin: tick 289 VICTORY_QUIPS coverage preserved ──────────

func test_tick_289_victory_quips_meta_coverage_preserved() -> void:
	var body := _dict_body("VICTORY_QUIPS")
	for jid in META_JOB_IDS:
		assert_true(body.contains("\"%s\":" % jid),
			"VICTORY_QUIPS must still have %s entry (tick 289 fix)" % jid)
