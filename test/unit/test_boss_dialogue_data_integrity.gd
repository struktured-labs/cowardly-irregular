extends GutTest

## Wave F — boss_dialogue.json data-integrity audit.
##
## Mirrors the test_monster_data_integrity pattern: walks every boss entry
## and asserts schema invariants the runtime would otherwise accept silently.
##
## Catches:
##   - duplicate / empty intent IDs
##   - duplicate / empty vulnerability IDs
##   - empty trigger_keywords arrays
##   - any consequence.type outside CONSEQUENCE_ALLOWLIST (story-flag safety)
##   - any consequence shape suspect of mutating story flags (e.g. "flag" key)

const DATA_PATH: String = "res://data/boss_dialogue.json"

const ALLOWLIST: Array[String] = [
	"skip_turn",
	"lose_buff_or_stagger",
	"enrage_briefly",
	"taunt_softens",
	"none",
]


# ── Helpers ──────────────────────────────────────────────────────────────────

func _load_data() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	assert_not_null(f, "could not open boss_dialogue.json")
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "boss_dialogue.json root must be Dictionary")
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary


# ── Tests ────────────────────────────────────────────────────────────────────

func test_data_loads() -> void:
	var data: Dictionary = _load_data()
	assert_gt(data.size(), 0, "boss_dialogue.json must contain at least one entry")


func test_every_intent_id_non_empty_and_unique_per_boss() -> void:
	var data: Dictionary = _load_data()
	for boss_id in data.keys():
		if str(boss_id).begins_with("_"):
			continue
		var entry: Dictionary = data[boss_id]
		var intents: Array = entry.get("scripted_intents", [])
		var seen: Dictionary = {}
		for it in intents:
			assert_true(it is Dictionary, "intent must be Dictionary in boss '%s'" % boss_id)
			var id: String = str((it as Dictionary).get("id", ""))
			assert_ne(id, "", "boss '%s' has an intent with empty id" % boss_id)
			assert_false(seen.has(id), "boss '%s' has duplicate intent id '%s'" % [boss_id, id])
			seen[id] = true


func test_every_vulnerability_id_non_empty_and_unique_per_boss() -> void:
	var data: Dictionary = _load_data()
	for boss_id in data.keys():
		if str(boss_id).begins_with("_"):
			continue
		var entry: Dictionary = data[boss_id]
		var vulns: Array = entry.get("jailbreak_vulnerabilities", [])
		var seen: Dictionary = {}
		for v in vulns:
			assert_true(v is Dictionary, "vulnerability must be Dictionary in boss '%s'" % boss_id)
			var id: String = str((v as Dictionary).get("id", ""))
			assert_ne(id, "", "boss '%s' has a vulnerability with empty id" % boss_id)
			assert_false(seen.has(id), "boss '%s' has duplicate vulnerability id '%s'" % [boss_id, id])
			seen[id] = true


func test_every_vulnerability_has_non_empty_trigger_keywords() -> void:
	var data: Dictionary = _load_data()
	for boss_id in data.keys():
		if str(boss_id).begins_with("_"):
			continue
		var entry: Dictionary = data[boss_id]
		var vulns: Array = entry.get("jailbreak_vulnerabilities", [])
		for v in vulns:
			var vid: String = str((v as Dictionary).get("id", "?"))
			var kws: Variant = (v as Dictionary).get("trigger_keywords", null)
			assert_true(kws is Array, "boss '%s' vulnerability '%s' must have Array trigger_keywords" % [boss_id, vid])
			assert_gt((kws as Array).size(), 0,
				"boss '%s' vulnerability '%s' has empty trigger_keywords (would never fire)" % [boss_id, vid])
			# Every keyword must itself be a non-empty string after trim.
			for kw in (kws as Array):
				assert_ne(str(kw).strip_edges(), "",
					"boss '%s' vulnerability '%s' has an empty trigger keyword" % [boss_id, vid])


func test_every_consequence_type_in_allowlist() -> void:
	var data: Dictionary = _load_data()
	for boss_id in data.keys():
		if str(boss_id).begins_with("_"):
			continue
		var entry: Dictionary = data[boss_id]
		var vulns: Array = entry.get("jailbreak_vulnerabilities", [])
		for v in vulns:
			var vid: String = str((v as Dictionary).get("id", "?"))
			var cons: Dictionary = (v as Dictionary).get("consequence", {})
			var ctype: String = str(cons.get("type", ""))
			assert_true(ALLOWLIST.has(ctype),
				"boss '%s' vulnerability '%s' has consequence.type '%s' NOT in allowlist %s" % [
					boss_id, vid, ctype, str(ALLOWLIST)
				])


func test_no_consequence_references_story_flags() -> void:
	# Stakes guardrail: a landed jailbreak may affect battle outcome / flavor /
	# opt-in meta-currency — NEVER a canonical story flag. Defensive scan that
	# rejects any consequence dictionary mentioning a known story-flag key.
	var data: Dictionary = _load_data()
	var forbidden_keys: Array[String] = [
		"story_flag", "story_flags", "set_flag", "set_story_flag",
		"flag_name", "flag", "world_unlock",
	]
	for boss_id in data.keys():
		if str(boss_id).begins_with("_"):
			continue
		var entry: Dictionary = data[boss_id]
		var vulns: Array = entry.get("jailbreak_vulnerabilities", [])
		for v in vulns:
			var vid: String = str((v as Dictionary).get("id", "?"))
			var cons: Dictionary = (v as Dictionary).get("consequence", {})
			var params: Dictionary = cons.get("params", {})
			for fk in forbidden_keys:
				assert_false(cons.has(fk),
					"boss '%s' vulnerability '%s' consequence has forbidden key '%s'" % [boss_id, vid, fk])
				assert_false(params.has(fk),
					"boss '%s' vulnerability '%s' consequence.params has forbidden key '%s'" % [boss_id, vid, fk])
