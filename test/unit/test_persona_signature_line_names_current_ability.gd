extends GutTest

## A persona voice line that hardcodes an ability's DISPLAY NAME drifts silently when
## that ability is renamed — the line keeps naming a spell the player can no longer see.
##
## 2026-08-22, `7cc20d01` renamed 23 arcane spells to Latin (Cure -> Sanatio). That commit
## carefully synced its two known second sources (JobSystem's fallback table, BattleManager's
## buff labels) and pinned both. It did not reach `data/job_personas.json`, whose Cleric line
## read "Cure is just polite negotiation with the damage formula" — naming an ability that
## no longer exists. The line IS reachable: BattleManager:6849 fires the
## `used_signature_ability` trigger and DialoguePrompts:721 renders it.
##
## Four of the five jobs describe the EFFECT instead of naming the ability
## ("Clean strike. No flourish.") and are drift-proof by construction. Only the Cleric
## names its spell, so only the Cleric needs a pin — and the pin is DERIVED from
## abilities.json rather than hardcoding "Sanatio", so re-rooting the family stays green
## while a stale line reds.
##
## The second test ratchets the other four: if someone later writes an ability name into
## a name-agnostic line, it must be pinned here too rather than becoming the next silent
## drifter.

const PERSONAS_PATH := "res://data/job_personas.json"
const ABILITIES_PATH := "res://data/abilities.json"

## Mirrors BattleManager.SIGNATURE_ABILITIES — the ID that gates each job's trigger.
const SIGNATURE_ABILITY_IDS := {
	"fighter": "power_strike",
	"cleric": "cure",
	"mage": "fire",
	"rogue": "backstab",
	"bard": "inspiring_melody",
}


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "could not open %s" % path)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "%s did not parse to a Dictionary" % path)
	return parsed if parsed is Dictionary else {}


func _jobs() -> Dictionary:
	var root := _load_json(PERSONAS_PATH)
	return root.get("jobs", root)


func _signature_line(job_id: String) -> String:
	var job: Dictionary = _jobs().get(job_id, {})
	var voices: Dictionary = job.get("trigger_voices", {})
	return str(voices.get("used_signature_ability", ""))


## Every display name authored in abilities.json, longest first so a multi-word name
## is matched before any single word inside it.
func _ability_names() -> Array[String]:
	var out: Array[String] = []
	var abilities := _load_json(ABILITIES_PATH)
	for id in abilities:
		var entry: Variant = abilities[id]
		if entry is Dictionary and entry.has("name"):
			out.append(str(entry["name"]))
	out.sort_custom(func(a, b): return a.length() > b.length())
	return out


func _names_referenced_in(line: String) -> Array[String]:
	var found: Array[String] = []
	for n in _ability_names():
		if n.length() >= 4 and line.contains(n):
			found.append(n)
	return found


func test_cleric_signature_line_names_the_current_display_name() -> void:
	var abilities := _load_json(ABILITIES_PATH)
	var sig_id: String = SIGNATURE_ABILITY_IDS["cleric"]
	assert_true(abilities.has(sig_id), "abilities.json must define '%s'" % sig_id)
	var current_name := str((abilities.get(sig_id, {}) as Dictionary).get("name", ""))
	assert_ne(current_name, "", "'%s' must have a display name" % sig_id)

	var line := _signature_line("cleric")
	assert_ne(line, "", "cleric must author a used_signature_ability line")
	assert_true(line.contains(current_name),
		("cleric's used_signature_ability line names a spell the player cannot see. "
		+ "abilities.json calls '%s' \"%s\"; the line reads: %s") % [sig_id, current_name, line])


func test_the_other_four_signature_lines_stay_name_agnostic() -> void:
	# Ratchet: these four describe the effect rather than naming the ability, which is what
	# makes them immune to a rename. If one starts naming an ability, pin it above.
	for job_id in ["fighter", "mage", "rogue", "bard"]:
		var line := _signature_line(job_id)
		assert_ne(line, "", "%s must author a used_signature_ability line" % job_id)
		var referenced := _names_referenced_in(line)
		assert_eq(referenced.size(), 0,
			("%s's used_signature_ability line now names ability %s. Name-agnostic lines "
			+ "cannot drift on a rename; a naming line must be pinned against abilities.json "
			+ "like the cleric's. Line: %s") % [job_id, str(referenced), line])


func test_the_scan_can_see_ability_names_at_all() -> void:
	# Control: a count control would pass on a broken loader. This names a member that
	# must be found, and one that must not.
	var names := _ability_names()
	assert_gt(names.size(), 100, "abilities.json should yield hundreds of display names")
	assert_true(names.has("Power Strike"), "known-present ability name was not found")
	assert_false(names.has("Zzz Not An Ability"), "fabricated ability name was found")
