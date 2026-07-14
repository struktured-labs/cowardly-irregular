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
##   - scripted_intent.id outside the widened 9-tag allowlist (migrated bosses only)
##   - learned_patterns_counter condition referencing an invalid counter_strategy string
##   - any of the 5 W1 opt-in bosses missing one of the 6 widened counter tags

const DATA_PATH: String = "res://data/boss_dialogue.json"

const ALLOWLIST: Array[String] = [
	"skip_turn",
	"lose_buff_or_stagger",
	"enrage_briefly",
	"taunt_softens",
	"none",
]

# 3 original + 6 counter-strategy tags (Task 6/15 plan).
const _ALLOWED_INTENT_TAGS: Array[String] = [
	"aggress", "turtle", "exploit_pattern",
	"fire_resist", "ice_resist", "lightning_resist",
	"focus_healer", "defense_boost", "rotate_aggro",
]

# Valid AutogrindSystem.get_counter_strategy() return values, incl. "no counter".
const _ALLOWED_COUNTER_STRATEGY_STRINGS: Array[String] = [
	"fire_resist", "ice_resist", "lightning_resist",
	"focus_healer", "defense_boost", "rotate_aggro",
	"generic_counter", "",
]

# Fully-migrated bosses only (dragons keep legacy ids; see _OPT_IN_BOSSES for their coverage-only check).
const _WIDENED_VOCAB_BOSSES: Array[String] = ["chancellor_mordaine"]

# All 5 W1 opt-in bosses (Mordaine + 4 dragons) — coverage-only, not exclusivity (Task 15).
const _OPT_IN_BOSSES: Array[String] = ["chancellor_mordaine", "pyrroth", "glacius", "voltharion", "umbraxis"]

const _REQUIRED_WIDENED_TAGS: Array[String] = [
	"fire_resist", "ice_resist", "lightning_resist",
	"focus_healer", "defense_boost", "rotate_aggro",
]

# 5 spotlight-duel minibosses — teach-the-kit taunt entries, keyed by monster_type
# so BattleManager._update_boss_dialogue_phase fires them. NOT persuade bosses:
# empty verbs (suppresses the 'Address' menu action) + empty jailbreak_vulnerabilities.
const _MINIBOSSES: Array[String] = [
	"fighter_skeleton_knight", "cleric_survive_target", "rogue_lockward",
	"mage_prismatic_construct", "bard_hostile_courtier",
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


func test_every_scripted_intent_id_is_in_widened_allowlist() -> void:
	var data: Dictionary = _load_data()
	for boss_id in data.keys():
		if not _WIDENED_VOCAB_BOSSES.has(str(boss_id)):
			continue
		if not (data[boss_id] is Dictionary):
			continue
		var boss: Dictionary = data[boss_id]
		for intent in boss.get("scripted_intents", []):
			var intent_id: String = str(intent.get("id", ""))
			assert_true(intent_id in _ALLOWED_INTENT_TAGS,
				"%s.scripted_intents.id='%s' not in widened allowlist" % [boss_id, intent_id])


func test_every_optin_boss_has_all_six_widened_tags() -> void:
	var data: Dictionary = _load_data()
	for boss_id in _OPT_IN_BOSSES:
		assert_true(data.has(boss_id), "boss_dialogue.json missing '%s'" % boss_id)
		if not data.has(boss_id):
			continue
		var ids: Array = []
		for intent in data[boss_id].get("scripted_intents", []):
			ids.append(str(intent.get("id", "")))
		for tag in _REQUIRED_WIDENED_TAGS:
			assert_true(tag in ids, "%s must include scripted_intent '%s'" % [boss_id, tag])


func test_learned_patterns_counter_conditions_reference_valid_strategies() -> void:
	# conditions is a Dictionary (schema norm) or an Array of them; normalize both.
	var data: Dictionary = _load_data()
	for boss_id in data.keys():
		if str(boss_id).begins_with("_"):
			continue
		var boss: Dictionary = data[boss_id]
		for intent in boss.get("scripted_intents", []):
			var raw_cond: Variant = intent.get("conditions", {})
			var cond_list: Array = raw_cond if raw_cond is Array else [raw_cond]
			for cond in cond_list:
				if typeof(cond) != TYPE_DICTIONARY:
					continue
				if cond.has("learned_patterns_counter"):
					var val: String = str(cond["learned_patterns_counter"])
					assert_true(val in _ALLOWED_COUNTER_STRATEGY_STRINGS,
						"%s.scripted_intents.conditions.learned_patterns_counter='%s' is not a valid counter_strategy value" % [boss_id, val])


func test_mordaine_covers_all_six_widened_tags() -> void:
	var data: Dictionary = _load_data()
	var mordaine: Dictionary = data.get("chancellor_mordaine", {})
	var ids: Array = []
	for intent in mordaine.get("scripted_intents", []):
		ids.append(str(intent.get("id", "")))
	for tag in ["fire_resist", "ice_resist", "lightning_resist",
			"focus_healer", "defense_boost", "rotate_aggro"]:
		assert_true(tag in ids,
			"chancellor_mordaine.scripted_intents must include '%s'" % tag)


# ── Spotlight-duel miniboss coverage ─────────────────────────────────────────

func test_all_minibosses_present() -> void:
	var data: Dictionary = _load_data()
	for mid in _MINIBOSSES:
		assert_true(data.has(mid), "boss_dialogue.json missing spotlight miniboss '%s'" % mid)


func test_minibosses_are_teach_not_persuade() -> void:
	# verbs:[] suppresses the 'Address the Boss' battle action (BattleCommandMenu
	# gate needs non-empty get_verbs); jailbreak_vulnerabilities:[] means no
	# persuade path. Spotlight duels teach the kit — they are not talked down.
	var data: Dictionary = _load_data()
	for mid in _MINIBOSSES:
		if not data.has(mid):
			continue
		var entry: Dictionary = data[mid]
		var verbs: Array = entry.get("verbs", [])
		assert_eq(verbs.size(), 0, "miniboss '%s' must have empty verbs (no Address action)" % mid)
		var vulns: Array = entry.get("jailbreak_vulnerabilities", [])
		assert_eq(vulns.size(), 0, "miniboss '%s' must have empty jailbreak_vulnerabilities (teach-not-persuade)" % mid)


func test_minibosses_have_scripted_intents_with_taunts() -> void:
	var data: Dictionary = _load_data()
	for mid in _MINIBOSSES:
		if not data.has(mid):
			continue
		var intents: Array = data[mid].get("scripted_intents", [])
		assert_gt(intents.size(), 0, "miniboss '%s' must author at least one scripted_intent (the taunt-as-teach hook)" % mid)
		for it in intents:
			var iid: String = str((it as Dictionary).get("id", "?"))
			var taunts: Array = (it as Dictionary).get("taunt_lines", [])
			assert_gt(taunts.size(), 0, "miniboss '%s' intent '%s' has no taunt_lines" % [mid, iid])


func test_prismatic_construct_taunts_teach_the_weakness_read() -> void:
	# The mage duel's whole lesson is reading the live elemental aspect; its
	# taunts must surface that cue diegetically (not a generic gloat).
	var data: Dictionary = _load_data()
	var pc: Dictionary = data.get("mage_prismatic_construct", {})
	var blob: String = ""
	for line in pc.get("opening_lines", []):
		blob += str(line).to_lower() + " "
	for it in pc.get("scripted_intents", []):
		for t in (it as Dictionary).get("taunt_lines", []):
			blob += str(t).to_lower() + " "
	var cue_hit := false
	for cue in ["fire", "ice", "frost", "lightning", "storm", "aspect", "color", "element"]:
		if blob.find(cue) != -1:
			cue_hit = true
			break
	assert_true(cue_hit, "mage_prismatic_construct taunts must teach the read-the-weakness cue (fire/ice/lightning/aspect/color)")
