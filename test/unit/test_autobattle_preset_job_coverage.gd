extends GutTest

## The autobattle preset catalog covers the 5 STARTER jobs only. The other 9 have zero templates,
## so a character in an advanced or meta job gets one profile ("Default") where a starter gets four.
##
## This became reachable on 2026-09-09. _resolve_job_for_character used to answer from a STATIC
## five-entry map, so find_for_job was only ever handed a starter id and always found three
## templates — a Guardian-Mira was served CLERIC presets. Fixing that lookup was right and it
## exposed the gap: correctly zero is more honest than incorrectly three, and now visible.
##
## Autobattle is a design pillar and CLAUDE.md calls the meta jobs "all five REAL", so this is
## authoring debt worth naming rather than a preference. BIDIRECTIONAL: a job losing its templates
## reds, and a listed job GAINING them reds too, so the list cannot outlive its reason.

const COVERED := ["bard", "cleric", "fighter", "mage", "rogue"]

## Jobs with no preset templates today. Authoring, not mechanics — what a Guardian's Defensive
## preset should DO is a design call, routed out rather than invented here.
## 2026-09-12: ninja removed — it has three stances now. It was the hard one of the nine, not the
## easy one: three of its five abilities apply a STATUS to self, and until `not_has_status` shipped
## in .307 a preset using them re-cast forever and buried every rule below it. The remaining eight
## are still authoring debt and still routed out.
const KNOWN_UNCOVERED := [
	"bossbinder", "necromancer", "scriptweaver",
	"skiptrotter", "speculator", "summoner", "time_mage",
]

func _job_ids() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_not_null(parsed, "CONTROL: jobs.json parses")
	var jobs: Dictionary = parsed.get("jobs", parsed)
	var out: Array = jobs.keys()
	out.sort()
	return out

## The catalog keys each template on `job_id`. NOT `jobs`, NOT `job` — my first read of this file
## guessed `jobs` and reported "0 jobs referenced by 15 templates", which is the vacuous shape this
## suite's own control exists to catch.
func _templates_per_job() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/autobattle_rule_templates.json"))
	assert_not_null(parsed, "CONTROL: the template catalog parses")
	var list = parsed.get("templates", parsed)
	var out: Dictionary = {}
	var entries: Array = list.values() if list is Dictionary else list
	for t in entries:
		var jid := str((t as Dictionary).get("job_id", ""))
		if jid == "":
			continue
		out[jid] = int(out.get(jid, 0)) + 1
	return out

func test_the_reader_is_not_vacuous() -> void:
	## If the key is ever renamed this returns {} and every assertion below passes trivially.
	var per := _templates_per_job()
	assert_gt(per.size(), 3, "CONTROL: templates DO declare a job_id (%d jobs)" % per.size())
	assert_gt(int(per.get("fighter", 0)), 0, "CONTROL: a known-covered job is found")
	assert_gt(_job_ids().size(), 10, "CONTROL: read the whole job roster")

func test_every_starter_job_has_presets() -> void:
	## The half that makes the gap a gap: the jobs a player actually reaches are all covered, so
	## zero-for-nine is an omission rather than a convention.
	var per := _templates_per_job()
	for jid in COVERED:
		assert_gt(int(per.get(jid, 0)), 0, "%s is a starter job and must have presets" % jid)

func test_no_new_job_silently_loses_its_presets() -> void:
	var per := _templates_per_job()
	var unlisted: Array = []
	for jid in _job_ids():
		if int(per.get(jid, 0)) > 0:
			continue
		if not (jid in KNOWN_UNCOVERED):
			unlisted.append(jid)
	assert_eq(unlisted.size(), 0,
		"these jobs have no autobattle presets and are undocumented — author templates, or list them: " + str(unlisted))

func test_no_listed_job_has_quietly_gained_presets() -> void:
	var per := _templates_per_job()
	var stale: Array = []
	for jid in KNOWN_UNCOVERED:
		if int(per.get(jid, 0)) > 0:
			stale.append(jid)
	assert_eq(stale.size(), 0,
		"these now have presets — delete them from KNOWN_UNCOVERED so the list keeps meaning what it says: " + str(stale))

func test_the_uncovered_list_names_real_jobs() -> void:
	## A typo in KNOWN_UNCOVERED would silently exempt nothing and permanently pass.
	var ids := _job_ids()
	var bogus: Array = []
	for jid in KNOWN_UNCOVERED:
		if not (jid in ids):
			bogus.append(jid)
	assert_eq(bogus.size(), 0, "KNOWN_UNCOVERED names a job that does not exist: " + str(bogus))
