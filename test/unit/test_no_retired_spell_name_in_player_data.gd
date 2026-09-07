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
## Deliberately narrow, and the excluded set is named in full rather than gestured at:
##
##   Fire · Cure · Thunder · Shell · Protect · Regen · RAISE
##
## all are ordinary English and appear throughout legitimate prose — boss_dialogue.json's
## "Fire again. Predictable." is element flavour and correct. Sweeping them would bury the
## signal in false positives, which get suppressed, which is how an allowlist rots.
##
## ⚠️ SO THIS LIST IS A FLOOR ON THE DEFECT, NOT A PARTITION OF IT. Concretely:
## data/lore.json's "Raise" -> "Anima Reddita" was fixed by the same commit that added this
## guard, and this guard CANNOT protect it. If that line regresses, nothing here reds.
##
## Found by cowir-deploy's tools/mutation_check.sh on 2026-08-22: mutating the lore.json
## line back to "Raise" left this test GREEN. The author's own hand-mutation had targeted
## autobattle_rule_templates.json, where the name IS covered — a mutation aimed at the
## strong half of the guard. The tool named it VACUOUS and it was right.

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


## Pure scan — split out so the "name is live again" branch can be exercised directly.
func scan_offences(body: String, label: String, current: Array, retired: Array) -> Array[String]:
	var out: Array[String] = []
	for name in retired:
		if current.has(name):
			continue  # the name is live again; prose may legitimately use it
		if body.contains(name):
			out.append("%s names retired spell '%s'" % [label, name])
	return out


func test_no_player_data_names_a_retired_spell() -> void:
	var current := _current_ability_names()
	var offences: Array[String] = []
	var walked: Array[String] = []
	for path in PROSE_DATA_FILES:
		var body := _read(path)
		if body == "":
			continue  # file absent is another test's business, not this one's
		walked.append(path.get_file())
		offences.append_array(scan_offences(body, path.get_file(), current, RETIRED_ARCANE_NAMES))
	assert_true(walked.has("lore.json"),
		"the prose walk never reached lore.json — the scan is dead and the check below is vacuous")
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


func test_a_name_that_comes_back_stops_being_forbidden() -> void:
	# The self-maintaining branch never fires against live data, so exercise it directly.
	var body := "Emergency Firia first, then Curia."
	var retired: Array = ["Firia", "Curia"]

	var both_retired := scan_offences(body, "x.json", [], retired)
	assert_eq(both_retired.size(), 2, "a retired name in prose must be flagged")

	var one_came_back := scan_offences(body, "x.json", ["Firia"], retired)
	assert_eq(one_came_back.size(), 1, "a name abilities.json defines again must NOT be flagged")
	assert_true(str(one_came_back).contains("Curia"), "the still-retired name must survive")
	assert_false(str(one_came_back).contains("Firia"), "the re-rooted name must be suppressed")
