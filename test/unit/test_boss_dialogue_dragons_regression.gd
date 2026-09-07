extends GutTest

## Wave G regression test — amplifies the signature jailbreak mechanic from one
## boss (Mordaine) to the four elemental dragons (Pyrroth/Glacius/Voltharion/
## Umbraxis) and adds victory_lines/defeat_lines gloat pools to all five bosses.
##
## This test pins the data contract that the runtime would otherwise accept
## silently (the canonical silent-failure class for this project):
##   - each dragon persona section exists and is well-formed
##   - every jailbreak vulnerability references ONLY an allowlisted consequence
##     (no story-flag writes can sneak into combat)
##   - every vulnerability has non-empty trigger_keywords (else it never fires)
##   - each dragon monster's persona id RESOLVES to a real section, following the
##     exact source-priority chain BattleEnemySpawner.spawn_forced_enemies uses:
##     boss_llm_persona_id if present, else the monster's own id (monster_type)
##   - victory_lines and defeat_lines are non-empty arrays of strings for ALL
##     FIVE bosses (the gloat/wipe fallback pools the LLM degrades to)
##
## Loads JSON directly (no BossDialogue autoload dependency) so the check stays
## surgical and runs even when autoloads are absent.

const BOSS_DIALOGUE_PATH: String = "res://data/boss_dialogue.json"
const MONSTERS_PATH: String = "res://data/monsters.json"

# Mirror of BossDialogue.CONSEQUENCE_ALLOWLIST — kept local so the test fails
# loudly if data drifts outside the safe set (story-flag guardrail).
const ALLOWLIST: Array[String] = [
	"skip_turn",
	"lose_buff_or_stagger",
	"enrage_briefly",
	"taunt_softens",
	"none",
]

# The four dragon personas added this wave, plus Mordaine for the gloat pools.
const DRAGON_PERSONAS: Array[String] = ["pyrroth", "glacius", "voltharion", "umbraxis"]
const ALL_BOSS_PERSONAS: Array[String] = ["chancellor_mordaine", "pyrroth", "glacius", "voltharion", "umbraxis"]

# Dragon monster id -> expected persona section key (wired via boss_llm_persona_id).
const DRAGON_MONSTER_TO_PERSONA: Dictionary = {
	"fire_dragon": "pyrroth",
	"ice_dragon": "glacius",
	"lightning_dragon": "voltharion",
	"shadow_dragon": "umbraxis",
}


# ── Helpers ──────────────────────────────────────────────────────────────────

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "could not open %s" % path)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "%s root must be Dictionary" % path)
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary


func _load_boss_dialogue() -> Dictionary:
	return _load_json(BOSS_DIALOGUE_PATH)


func _load_monsters() -> Dictionary:
	return _load_json(MONSTERS_PATH)


## Resolve a monster's persona id exactly as BattleEnemySpawner does:
## boss_llm_persona_id if set, else the monster's own id (monster_type fallback).
func _resolve_persona(monsters: Dictionary, monster_id: String) -> String:
	var entry: Dictionary = monsters.get(monster_id, {})
	var pid: String = str(entry.get("boss_llm_persona_id", "")).strip_edges()
	if pid != "":
		return pid
	return monster_id


# ── Tests ────────────────────────────────────────────────────────────────────

func test_each_dragon_persona_section_exists_and_is_well_formed() -> void:
	var data: Dictionary = _load_boss_dialogue()
	for persona in DRAGON_PERSONAS:
		assert_true(data.has(persona), "boss_dialogue.json missing dragon persona '%s'" % persona)
		if not data.has(persona):
			continue
		var entry: Dictionary = data[persona]
		# Verb set present and non-empty.
		var verbs: Variant = entry.get("verbs", null)
		assert_true(verbs is Array and (verbs as Array).size() > 0,
			"dragon '%s' must have a non-empty verbs array" % persona)
		# Opening taunts (2-3 authored).
		var opens: Variant = entry.get("opening_lines", null)
		assert_true(opens is Array and (opens as Array).size() >= 2,
			"dragon '%s' must have at least 2 opening_lines" % persona)
		# At least one phase transition line.
		var ptl: Dictionary = entry.get("phase_transition_lines", {})
		assert_gt(ptl.size(), 0, "dragon '%s' must have phase_transition_lines" % persona)
		# Intent biases present.
		var intents: Variant = entry.get("scripted_intents", null)
		assert_true(intents is Array and (intents as Array).size() > 0,
			"dragon '%s' must have scripted_intents" % persona)


func test_each_dragon_has_at_least_two_jailbreak_vulnerabilities() -> void:
	var data: Dictionary = _load_boss_dialogue()
	for persona in DRAGON_PERSONAS:
		var entry: Dictionary = data.get(persona, {})
		var vulns: Variant = entry.get("jailbreak_vulnerabilities", null)
		assert_true(vulns is Array, "dragon '%s' must have jailbreak_vulnerabilities array" % persona)
		assert_true(vulns is Array and (vulns as Array).size() >= 2,
			"dragon '%s' must author at least 2 jailbreak vulnerabilities" % persona)


func test_every_dragon_vulnerability_is_well_formed_and_allowlisted() -> void:
	var data: Dictionary = _load_boss_dialogue()
	for persona in DRAGON_PERSONAS:
		var entry: Dictionary = data.get(persona, {})
		var vulns: Array = entry.get("jailbreak_vulnerabilities", [])
		var seen_ids: Dictionary = {}
		for v in vulns:
			assert_true(v is Dictionary, "dragon '%s' vulnerability must be Dictionary" % persona)
			var vid: String = str((v as Dictionary).get("id", ""))
			assert_ne(vid, "", "dragon '%s' has a vulnerability with empty id" % persona)
			assert_false(seen_ids.has(vid), "dragon '%s' has duplicate vulnerability id '%s'" % [persona, vid])
			seen_ids[vid] = true
			# Trigger keywords must be a non-empty array of non-empty strings.
			var kws: Variant = (v as Dictionary).get("trigger_keywords", null)
			assert_true(kws is Array and (kws as Array).size() > 0,
				"dragon '%s' vuln '%s' must have non-empty trigger_keywords" % [persona, vid])
			if kws is Array:
				for kw in (kws as Array):
					assert_ne(str(kw).strip_edges(), "",
						"dragon '%s' vuln '%s' has an empty trigger keyword" % [persona, vid])
			# Consequence type must be in the safe allowlist.
			var cons: Dictionary = (v as Dictionary).get("consequence", {})
			var ctype: String = str(cons.get("type", ""))
			assert_true(ALLOWLIST.has(ctype),
				"dragon '%s' vuln '%s' consequence.type '%s' NOT in allowlist %s" % [
					persona, vid, ctype, str(ALLOWLIST)])


func test_dragon_consequences_never_touch_story_flags() -> void:
	# Stakes guardrail: a landed jailbreak may stagger / skip / enrage / soften —
	# NEVER write a canonical story flag. Defensive scan over consequence dicts.
	var data: Dictionary = _load_boss_dialogue()
	var forbidden_keys: Array[String] = [
		"story_flag", "story_flags", "set_flag", "set_story_flag",
		"flag_name", "flag", "world_unlock",
	]
	for persona in DRAGON_PERSONAS:
		var entry: Dictionary = data.get(persona, {})
		var vulns: Array = entry.get("jailbreak_vulnerabilities", [])
		for v in vulns:
			var vid: String = str((v as Dictionary).get("id", "?"))
			var cons: Dictionary = (v as Dictionary).get("consequence", {})
			var params: Dictionary = cons.get("params", {})
			for fk in forbidden_keys:
				assert_false(cons.has(fk),
					"dragon '%s' vuln '%s' consequence has forbidden key '%s'" % [persona, vid, fk])
				assert_false(params.has(fk),
					"dragon '%s' vuln '%s' consequence.params has forbidden key '%s'" % [persona, vid, fk])


func test_each_dragon_monster_persona_id_resolves_to_a_real_section() -> void:
	# This is the wiring contract: the persona id BattleEnemySpawner resolves for
	# each dragon monster MUST key into a real boss_dialogue.json section.
	var monsters: Dictionary = _load_monsters()
	var data: Dictionary = _load_boss_dialogue()
	for monster_id in DRAGON_MONSTER_TO_PERSONA.keys():
		assert_true(monsters.has(monster_id), "monsters.json missing dragon monster '%s'" % monster_id)
		var resolved: String = _resolve_persona(monsters, monster_id)
		var expected: String = DRAGON_MONSTER_TO_PERSONA[monster_id]
		assert_eq(resolved, expected,
			"dragon monster '%s' should resolve to persona '%s' (got '%s')" % [monster_id, expected, resolved])
		assert_true(data.has(resolved),
			"dragon monster '%s' persona '%s' does not resolve to a real boss_dialogue section" % [monster_id, resolved])


func test_mordaine_persona_still_resolves_via_monster_type_fallback() -> void:
	# Mordaine intentionally carries NO boss_llm_persona_id; it relies on the
	# monster_type fallback (its own id == the persona key). Pin that so the
	# fallback chain doesn't silently regress when dragons get explicit ids.
	var monsters: Dictionary = _load_monsters()
	var data: Dictionary = _load_boss_dialogue()
	assert_true(monsters.has("chancellor_mordaine"), "monsters.json missing chancellor_mordaine")
	var resolved: String = _resolve_persona(monsters, "chancellor_mordaine")
	assert_eq(resolved, "chancellor_mordaine", "Mordaine must resolve to its own id via fallback")
	assert_true(data.has(resolved), "Mordaine persona section must exist")


func test_all_five_bosses_have_non_empty_victory_and_defeat_pools() -> void:
	# New this wave: deterministic gloat (victory) and wipe (defeat) fallback
	# pools. The LLM generates a fresh line when available and falls back to a
	# random pick from these — so they MUST be present and non-empty for the
	# scripted floor to work with LLM off (the web ship configuration).
	var data: Dictionary = _load_boss_dialogue()
	for persona in ALL_BOSS_PERSONAS:
		assert_true(data.has(persona), "boss_dialogue.json missing boss '%s'" % persona)
		if not data.has(persona):
			continue
		var entry: Dictionary = data[persona]
		var vics: Variant = entry.get("victory_lines", null)
		assert_true(vics is Array and (vics as Array).size() > 0,
			"boss '%s' must have a non-empty victory_lines pool" % persona)
		if vics is Array:
			for line in (vics as Array):
				assert_ne(str(line).strip_edges(), "",
					"boss '%s' has an empty victory line" % persona)
		var defs: Variant = entry.get("defeat_lines", null)
		assert_true(defs is Array and (defs as Array).size() > 0,
			"boss '%s' must have a non-empty defeat_lines pool" % persona)
		if defs is Array:
			for line in (defs as Array):
				assert_ne(str(line).strip_edges(), "",
					"boss '%s' has an empty defeat line" % persona)


func test_no_dragon_persona_collides_with_a_real_monster_id() -> void:
	# Defensive: the new persona keys (pyrroth/glacius/...) must NOT accidentally
	# equal a monster id, which would make the monster_type fallback ambiguous.
	var monsters: Dictionary = _load_monsters()
	for persona in DRAGON_PERSONAS:
		assert_false(monsters.has(persona),
			"persona key '%s' collides with a real monster id — fallback would be ambiguous" % persona)
