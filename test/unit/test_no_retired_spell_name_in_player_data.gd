extends GutTest

## A spell rename lands in abilities.json; every OTHER data file that spelled the old name
## in prose keeps saying it, and the player reads a spell that no longer exists.
##
## 2026-08-22, `7cc20d01` renamed 23 arcane spells to Latin. It synced the two second
## sources that were CODE (JobSystem's fallback table, BattleManager's buff labels) and
## pinned both. Three more lived in DATA and were missed, because they are a different
## capability — code that STORES a name versus data that PRINTS one:
##
##   data/job_personas.json              "Cure is just polite negotiation…"   (Cleric quip)
##   data/autobattle_rule_templates.json "Emergency Curia first…"  "Firia spam…"
##   data/lore.json                      "Raise is not a reward."  "…in a Firia."
##
## This guard is SELF-MAINTAINING rather than a pinned list of corrections: a name is only
## forbidden while abilities.json does not define it. Re-rooting a family — bringing
## "Firia" back as a real ability — makes the check stop flagging it automatically,
## because the name is then current and a data file may legitimately say it.
##
## Deliberately narrow: only names that are UNAMBIGUOUS spell references. `Fire`, `Cure`,
## `Thunder`, `Shell` and `Protect` are ordinary English and appear all over legitimate
## prose — boss_dialogue.json's "Fire again. Predictable." is element flavour and correct.
## Including them would bury the signal, so this list is a FLOOR on the defect, not a
## partition of it.

const ABILITIES_PATH := "res://data/abilities.json"

## Display names retired by the Latin rebranding. Checked against abilities.json at run
## time — a name that comes back is no longer forbidden.
const RETIRED_ARCANE_NAMES: Array[String] = [
	"Curia", "Firia", "Blizzardia", "Thunderia",
	"Firia Ex", "Blizzardia Ex", "Thunderia Ex",
	"Esuna", "Drain Life", "Death Sentence", "Necro Blast", "Chain Lightning",
]

## Player-facing data files that carry prose naming abilities.
const PROSE_DATA_FILES: Array[String] = [
	"res://data/job_personas.json",
	"res://data/autobattle_rule_templates.json",
	"res://data/lore.json",
	"res://data/boss_dialogue.json",
	"res://data/inn_dialogue.json",
	"res://data/shopkeeper_dialogue.json",
]


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _current_ability_names() -> Array[String]:
	var out: Array[String] = []
	var parsed: Variant = JSON.parse_string(_read(ABILITIES_PATH))
	if not (parsed is Dictionary):
		return out
	for id in (parsed as Dictionary):
		var entry: Variant = (parsed as Dictionary)[id]
		if entry is Dictionary and entry.has("name"):
			out.append(str(entry["name"]))
	return out


func test_no_player_data_names_a_retired_spell() -> void:
	var current := _current_ability_names()
	var offences: Array[String] = []
	for path in PROSE_DATA_FILES:
		var body := _read(path)
		if body == "":
			continue  # file absent is another test's business, not this one's
		for retired in RETIRED_ARCANE_NAMES:
			if current.has(retired):
				continue  # the name is live again; prose may legitimately use it
			if body.contains(retired):
				offences.append("%s names retired spell '%s'" % [path.get_file(), retired])
	assert_eq(offences.size(), 0,
		("player-facing prose names a spell abilities.json no longer defines — the player "
		+ "reads a spell that does not exist: %s") % str(offences))


func test_the_scan_can_see_these_files_and_names() -> void:
	# Controls: a count-only check passes on a broken reader. Name members that must be
	# found, and one that must not.
	var current := _current_ability_names()
	assert_gt(current.size(), 100, "abilities.json should yield hundreds of display names")
	assert_true(current.has("Ignis Maior"), "known-present replacement name was not found")
	assert_false(current.has("Firia"), "retired name is unexpectedly live in abilities.json")

	var personas := _read("res://data/job_personas.json")
	assert_true(personas.contains("Sanatio"), "reader could not see job_personas.json content")
	assert_false(personas.contains("Zzznotaspell"), "fabricated token was found")
