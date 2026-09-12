extends GutTest

## Every job's default autobattle script should only use abilities that job can actually have.
##
## ⚠️ CORRECTED 2026-09-09, same day: I first wrote that every one of Guardian's rules "can never
## fire". That was a PROPERTY (not in the job's own kit) asserted as an OUTCOME (unfirable), which
## is the substitution cowir-overworld named while committing it inside the commit documenting it.
## Measured, the six split two ways and both are defects for different reasons:
##   iron_guard · taunt        MONSTER abilities (brass_golem, spiteful_crow). No player job has
##                             them. Genuinely unfirable — my original claim, true for these two.
##   protect · backstab ·      other JOBS' kit (cleric, rogue). knows_ability covers a SECONDARY
##   steal · cure              job, so these fire IF the player happens to have picked that exact
##                             secondary. A default script cannot assume one, so it is still wrong
##                             — but "can never fire" was overstated for four of the six.
## Three do not — and nobody had ever seen them run: the ladder that builds them was gated on a
## GameState method declared nowhere in src/, so it was UNREACHABLE until 2026-09-09. Fixing that
## dead lookup did not just restore behaviour, it exposed authoring nothing had ever executed
## (cowir-overworld's rule, same day, from the AFRAID tuning that could not fire).
##
## BIDIRECTIONAL: a NEW mismatch reds (fix the script), and a LISTED one that gets fixed ALSO reds
## (delete the entry), so the exemption cannot outlive its reason.

const SRC := "res://src/autobattle/AutobattleSystem.gd"

## job_id -> ability ids its default script uses that the job cannot know.
## Authoring, not mechanics: which in-kit ability replaces each is a design call, routed out.
## EMPTY, 2026-09-12 — all six are fixed. Kept as a const rather than deleted because the
## bidirectional check below is the point: an entry added here must be REMOVED the day it is fixed,
## and an empty map is the strongest form of that statement. The six were:
##   guardian  iron_guard (brass_golem) · taunt (spiteful_crow) · protect (cleric)
##   ninja     backstab · steal (both rogue)
##   summoner  cure (cleric — the Summoner has no healing in its kit at all)
## Replaced with in-kit equivalents, not deleted: guardian_wall and shield_bash, smoke_bomb, and a
## potion aimed at the wounded ally. "Which in-kit ability replaces each" was routed out as a design
## call for months; it stopped being one once four preset catalogs made the same calls and shipped.
const KNOWN_MISMATCHED := {}

const ALIAS := {"black_mage": "mage", "white_mage": "cleric", "thief": "rogue"}

func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "CONTROL: %s parses" % path)
	return parsed

func _kit(jid: String) -> Dictionary:
	var jobs: Dictionary = _json("res://data/jobs.json")
	jobs = jobs.get("jobs", jobs)
	var j: Dictionary = jobs.get(jid, {})
	var out: Dictionary = {}
	for a in (j.get("abilities", []) as Array):
		out[str(a)] = true
	var at_level = j.get("abilities_at_level", {})
	if at_level is Dictionary:
		for lv in (at_level as Dictionary).keys():
			for a in ((at_level as Dictionary)[lv] as Array):
				out[str(a)] = true
	var fm = j.get("free_move", {})
	if fm is Dictionary and str((fm as Dictionary).get("ability_id", "")) != "":
		out[str((fm as Dictionary)["ability_id"])] = true
	return out

## Actions are {"type": "ability", "id": "x"} — the key is `id`, NOT `ability_id` (free moves) and
## NOT `ability`. Three spellings for one concept in this codebase; scoping to ability-typed
## actions is what stops `{"type":"item","id":"potion"}` being counted as an ability.
func _mismatches() -> Dictionary:
	var s := FileAccess.get_file_as_string(SRC)
	assert_gt(s.length(), 1000, "CONTROL: read AutobattleSystem")
	var abilities: Dictionary = _json("res://data/abilities.json")
	abilities = abilities.get("abilities", abilities)
	var fn_re := RegEx.new()
	fn_re.compile("func _create_([a-z_]+)_default_script\\(")
	var act_re := RegEx.new()
	act_re.compile("\\{\\s*\"type\"\\s*:\\s*\"ability\"\\s*,\\s*\"id\"\\s*:\\s*\"([a-z_]+)\"")
	var out: Dictionary = {}
	for m in fn_re.search_all(s):
		var name := m.get_string(1)
		var jid: String = ALIAS.get(name, name)
		var i := m.get_start()
		var j := s.find("\nfunc ", i + 10)
		var body := s.substr(i, j - i)
		var kit := _kit(jid)
		if kit.is_empty():
			continue
		var bad: Array = []
		for a in act_re.search_all(body):
			var aid := a.get_string(1)
			if abilities.has(aid) and not kit.has(aid) and not (aid in bad):
				bad.append(aid)
		bad.sort()
		if not bad.is_empty():
			out[jid] = bad
	return out

## Added 2026-09-11 after cowir-sfx found a loop guard whose corpus was `begins_with("ambient_")`
## while the six keys breaking the contract were named `weather_*` — the guard could not see exactly
## the members that were broken, and passed green throughout. My scan picks its corpus the same
## way: by the NAME `_create_<x>_default_script`. That is true today and nothing enforces it, so a
## builder reached through any other name would be silently exempt from every assertion in this file.
## This pins the two corpora together — defined-by-name and dispatched-by-reference must be the same
## set — so the name-derived scan cannot quietly stop covering the thing it claims to cover.
## The reference corpus is EVERY callable the dispatch returns, matched with no name pattern at all
## — `return (_[a-z_]+)\(` inside create_default_character_script's body. That is the whole point:
## a corpus derived with the same pattern the scan uses would agree with it by construction and
## prove nothing. A builder named `_build_bard_script` shows up here and fails the pattern check.
func test_the_scan_covers_every_builder_the_dispatch_ACTUALLY_REACHES() -> void:
	var s := FileAccess.get_file_as_string(SRC)
	var i: int = s.find("func create_default_character_script(")
	assert_gt(i, -1, "CONTROL: located the dispatch")
	var j: int = s.find("\nfunc ", i + 10)
	var body: String = s.substr(i, (j - i) if j > -1 else s.length() - i)
	assert_true(body.contains("_create_fighter_default_script"),
		"CONTROL: the sliced body really is the dispatch, not a window past it")

	var any_re := RegEx.new()
	any_re.compile("return (_[a-z_]+)\\(")
	var reached: Dictionary = {}
	for m in any_re.search_all(body):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 5, "CONTROL: the dispatch returns builders at all (%d)" % reached.size())

	var pat_re := RegEx.new()
	pat_re.compile("^_create_[a-z_]+_default_script$")
	var invisible: Array = []
	for f in reached:
		if pat_re.search(f) == null:
			invisible.append(f)
	assert_eq(invisible.size(), 0,
		"the dispatch reaches a builder whose name this file's scan cannot match, so its rules are exempt from every kit check here: " + str(invisible))

	## The other direction: a builder defined under the pattern that nothing dispatches is dead
	## authoring, and a kit check that passes on it is passing on code no player can reach.
	var def_re := RegEx.new()
	def_re.compile("func (_create_[a-z_]+_default_script)\\(")
	var orphans: Array = []
	for m in def_re.search_all(s):
		if not reached.has(m.get_string(1)):
			orphans.append(m.get_string(1))
	assert_eq(orphans.size(), 0,
		"a default-script builder the dispatch never returns is unreachable: " + str(orphans))

func test_the_scan_is_not_vacuous() -> void:
	## The whole file rests on the action regex matching. If it stops matching, every assertion
	## below passes trivially — which is how my first version of this scan reported zero.
	var s := FileAccess.get_file_as_string(SRC)
	var act_re := RegEx.new()
	act_re.compile("\\{\\s*\"type\"\\s*:\\s*\"ability\"\\s*,\\s*\"id\"\\s*:\\s*\"([a-z_]+)\"")
	assert_gt(act_re.search_all(s).size(), 20,
		"CONTROL: the extractor finds real ability actions (%d)" % act_re.search_all(s).size())
	assert_gt(_kit("fighter").size(), 2, "CONTROL: a known job's kit reads non-empty")

func test_no_new_default_script_references_an_ability_its_job_lacks() -> void:
	var unlisted: Array = []
	for jid in _mismatches():
		var listed: Array = KNOWN_MISMATCHED.get(jid, [])
		for aid in _mismatches()[jid]:
			if not (aid in listed):
				unlisted.append("%s/%s" % [jid, aid])
	assert_eq(unlisted.size(), 0,
		"a default script uses an ability outside its job's own kit — unfirable, or firable only if the player picked a specific secondary job, which a default cannot assume: " + str(unlisted))

func test_no_listed_mismatch_has_quietly_been_fixed() -> void:
	var found := _mismatches()
	var stale: Array = []
	for jid in KNOWN_MISMATCHED:
		var live: Array = found.get(jid, [])
		for aid in KNOWN_MISMATCHED[jid]:
			if not (aid in live):
				stale.append("%s/%s" % [jid, aid])
	assert_eq(stale.size(), 0,
		"these now use in-kit abilities — delete them from KNOWN_MISMATCHED so the list keeps meaning what it says: " + str(stale))

func test_the_starter_jobs_are_all_clean() -> void:
	## The contrast that makes the three a defect rather than a convention: every job a player
	## actually reaches today authors its script against its own kit.
	var found := _mismatches()
	for jid in ["fighter", "cleric", "mage", "rogue", "bard"]:
		assert_false(found.has(jid), "%s's default script must only use its own kit" % jid)
