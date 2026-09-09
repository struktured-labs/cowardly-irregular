extends GutTest

## THE BARD PLAYED A SWORD THUMP FOR ITS ENTIRE SPECIALTY.
##
## 2026-09-09, three lanes each found one layer of the same character being broken: songs
## resolved to DARK vfx, the song animations were registered but never requested, and the
## whole song family fell through to `ability_physical` in audio. Nobody was looking for
## "the Bard" — each lane was looking at its own seam, and the character underneath was the
## intersection. No lane-scoped guard could have caught it: each stays green while the
## other two layers are broken.
##
## This is the character-scoped arm, and it asks what no per-seam test asks:
## DOES THIS CLASS HAVE A VOICE FOR THE THINGS THAT ARE NOT WEAPON SWINGS?
##
## The property is deliberately NOT "the whole kit thumps". A Fighter's cleave and
## power_strike SHOULD thump — they are weapon hits, and test_ability_sound_element_
## coverage_regression is right to exclude physical abilities from its derived pass. The
## defect is narrower and sharper: a job with non-physical abilities — songs, summons,
## time manipulation, buffs — where EVERY ONE of them resolves to the melee fallback.
## That class has no voice for its own identity. One ability thumping is usually design;
## every non-weapon ability thumping is the class being mute.
##
## Measured on origin/main ceeedf00: EIGHT of fourteen jobs. The Bard was noticed because
## struktured plays one. The other seven have the identical defect and nobody had looked.
##
## KNOWN BLIND SPOT, stated so this file cannot imply a completeness it does not have:
## the physical exclusion is a real hole. cowir-sfx found `riff` — the Bard's Free Move and
## per struktured 2026-08-29 her ACTUAL attack — carries type=physical while its own shipped
## description reads "a sour, clashing chord struck like a weapon". So an ability can be
## typed physical and still be wrong to thump, and this arm skips exactly those. The type
## field is what the engine keys on; the description is what the player is shown, and when
## they disagree the type field is not automatically right. A check that reconciled the two
## would catch what this one cannot, and it is not built.
##
## RATCHET, both directions:
##   grows   -> a class lost its voice, or a new one shipped without one
##   shrinks -> someone gave a class its voice and left this list defaming the game
## Both fail. Removing a fixed job is a one-line edit; the message names which line.

## job -> the non-physical ability count that is currently mute. Every entry is DEBT, not
## an exemption: a summon, a song, a rewind and a buff all deserve to sound like themselves.
## cowir-sfx's song/summon/revival cues retire bard and summoner when they land.
const BASELINE: Dictionary = {
	"bard": 4,          # battle_hymn lullaby discord inspiring_melody — struktured reported this one
	"fighter": 1,       # provoke — a taunt is not a weapon hit
	"guardian": 3,
	"ninja": 3,
	"rogue": 5,
	"speculator": 6,
	"summoner": 5,      # the summons plus recursive_summon
	"time_mage": 5,     # the entire meta kit
}

## Drawn FROM the measured population, not hoped for: the Mage resolves all eleven of its
## abilities to real cues. If the resolution here ever breaks badly enough that everything
## reads mute, this is the arm that notices.
const KNOWN_VOICED: String = "mage"

const FALLBACK := "ability_physical"
const PHYSICAL_TYPE := "physical"


func _sound_manager() -> Node:
	return get_node_or_null("/root/SoundManager")


func _job_system() -> Node:
	return get_node_or_null("/root/JobSystem")


## Every ability a job can field: base kit plus every level unlock, deduped.
func _kit_of(job: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw in job.get("abilities", []):
		var id := str(raw)
		if id != "" and not out.has(id):
			out.append(id)
	var unlocks: Variant = job.get("abilities_at_level", {})
	if unlocks is Dictionary:
		for level_key in (unlocks as Dictionary).keys():
			var ids: Variant = (unlocks as Dictionary)[level_key]
			if ids is Array:
				for raw2 in (ids as Array):
					var id2 := str(raw2)
					if id2 != "" and not out.has(id2):
						out.append(id2)
	return out


## job -> count of its non-physical abilities, when EVERY one of them is mute.
func _mute_identities() -> Dictionary:
	var sm := _sound_manager()
	var js := _job_system()
	var out: Dictionary = {}
	if sm == null or js == null:
		return out
	for jid in js.jobs.keys():
		var job: Variant = js.jobs[jid]
		if not (job is Dictionary):
			continue
		var non_physical: int = 0
		var voiced: int = 0
		for aid in _kit_of(job as Dictionary):
			var ability: Dictionary = js.get_ability(aid)
			if str(ability.get("type", "")) == PHYSICAL_TYPE:
				continue
			non_physical += 1
			if str(sm._ability_sounds.get(aid, FALLBACK)) != FALLBACK:
				voiced += 1
		if non_physical > 0 and voiced == 0:
			out[str(jid)] = non_physical
	return out


## PREMISE. Everything below reads _ability_sounds; if the derived pass has not run, the
## map holds only the 24 hand entries and nearly every class reads mute for a reason that
## has nothing to do with this test.
func test_premise_the_resolver_is_populated() -> void:
	var sm := _sound_manager()
	assert_not_null(sm, "SoundManager autoload must exist")
	var js := _job_system()
	assert_not_null(js, "JobSystem autoload must exist")
	assert_gt(sm._ability_sounds.size(), 24,
		"PREMISE BROKEN: _ability_sounds holds %d entries; the hand map alone is 24, so the derived pass added nothing and every class below would read mute for the wrong reason" % sm._ability_sounds.size())
	assert_gt(js.jobs.size(), 0, "JobSystem loaded no jobs — the walk below would be vacuous")


## Without this the whole file is hollow: a broken _kit_of or a get_ability that returns {}
## makes non_physical zero everywhere, _mute_identities returns {}, and the ratchet compares
## an empty set to an empty set and passes having measured nothing.
func test_the_walk_examined_a_real_population() -> void:
	var js := _job_system()
	assert_not_null(js, "JobSystem autoload required")
	var jobs_walked: int = 0
	var non_physical_seen: int = 0
	var typed_seen: int = 0
	for jid in js.jobs.keys():
		var job: Variant = js.jobs[jid]
		if not (job is Dictionary):
			continue
		var kit := _kit_of(job as Dictionary)
		if kit.is_empty():
			continue
		jobs_walked += 1
		for aid in kit:
			var ability: Dictionary = js.get_ability(aid)
			if not ability.is_empty():
				typed_seen += 1
			if str(ability.get("type", "")) != PHYSICAL_TYPE:
				non_physical_seen += 1
	assert_gt(jobs_walked, 10,
		"only %d jobs had a non-empty kit — the kit walk is not reading the base list or abilities_at_level" % jobs_walked)
	assert_gt(typed_seen, 50,
		"get_ability returned data for only %d abilities — the type test below cannot discriminate, so every ability would count as non-physical" % typed_seen)
	assert_gt(non_physical_seen, 20,
		"only %d non-physical abilities across all jobs — the type filter is eating the population" % non_physical_seen)


## The resolution must be able to report a class WITH a voice, or "everything is mute" is
## not a reading. Seeded from the measured set, not fabricated.
func test_the_resolver_can_report_a_voiced_class() -> void:
	var mute := _mute_identities()
	assert_false(mute.has(KNOWN_VOICED),
		"%s resolves every one of its abilities to a real cue, so finding it mute means the resolution in THIS FILE is broken, not the game" % KNOWN_VOICED)


func test_no_class_beyond_the_known_debt_is_mute() -> void:
	var mute := _mute_identities()
	var found: Array[String] = []
	for jid in mute.keys():
		found.append(str(jid))
	found.sort()

	var newly: Array[String] = []
	for jid in found:
		if not BASELINE.has(jid):
			newly.append("%s (%d non-physical abilities, every one silent)" % [jid, int(mute[jid])])
	assert_eq(newly.size(), 0,
		"a class lost its voice: %s — every ability it has that is NOT a weapon swing resolves to '%s'" % [", ".join(newly), FALLBACK])

	var fixed: Array[String] = []
	for jid in BASELINE.keys():
		if not found.has(str(jid)):
			fixed.append(str(jid))
	fixed.sort()
	assert_eq(fixed.size(), 0,
		"GOOD NEWS, STALE LIST: %s now sound(s) like themselves. Delete those key(s) from BASELINE at the top of this file so it stops claiming the game is worse than it is." % ", ".join(fixed))
