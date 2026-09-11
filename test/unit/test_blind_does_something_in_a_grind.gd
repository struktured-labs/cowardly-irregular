extends GutTest

## The headless resolver APPLIED blind and then ignored it. It honours stun, sleep, confuse and
## fear (_check_status_skip) and inflicts statuses from abilities — `blind` appeared ZERO times in
## the file. So the Bard's Riff, whose whole identity is "0-MP strike with a 70% blind — disruption,
## not an MP battery" (struktured's ruling, CLAUDE.md), did its job in a live fight and nothing at
## all in a grind. Autobattle/autogrind is a stated design pillar; a status that works on screen and
## not in the grind is the two-engines-disagree defect, not a missing feature.
##
## ⚠️ TWO OTHER DIVERGENCES ARE MEASURED HERE AND DELIBERATELY NOT CHANGED — they are balance calls,
## not contradictions, and they belong to struktured:
##   speed term   live divides by the target's speed (a RATIO); headless uses the RAW difference,
##                so a fast attacker reaches the 2% floor far sooner in a grind
##   weather      live adds get_weather_miss_bonus(); the headless resolver has no weather at all
## Pinned below so they cannot drift further while nobody is looking.

const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"

func _src(p: String) -> String:
	var s := FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 1000, "CONTROL: read %s" % p)
	return s

func test_the_headless_miss_roll_reads_blind() -> void:
	var r := _src(RESOLVER)
	var i: int = r.find("miss_chance")
	assert_gt(i, -1, "CONTROL: located the headless miss calculation")
	var window: String = r.substr(maxi(0, i - 600), 700)
	assert_true(window.contains("has_status(\"blind\")"),
		"the grind's miss roll must read blind — it is applied by abilities and was ignored here")

func test_both_engines_use_the_same_blind_penalty() -> void:
	## The number, not just the presence. If one engine is retuned and the other is not, a blind
	## build performs differently on screen and in the grind and nothing says so.
	var live := _src(LIVE)
	var head := _src(RESOLVER)
	var re := RegEx.new()
	re.compile("blind\"\\)[^\\n]*\\n\\s*\\w+ *\\+= *(0\\.[0-9]+)")
	var lm := re.search(live)
	var hm := re.search(head)
	assert_not_null(lm, "CONTROL: the live engine's blind penalty is readable")
	assert_not_null(hm, "CONTROL: the headless blind penalty is readable")
	if lm == null or hm == null:
		return
	assert_eq(hm.get_string(1), lm.get_string(1),
		"the two engines disagree on the blind penalty: live %s vs headless %s" % [lm.get_string(1), hm.get_string(1)])

func test_the_bard_still_inflicts_the_status_this_defends() -> void:
	## PREMISE. If Riff stops inflicting blind, this file is defending a path nothing reaches, and
	## the arms above would keep passing while the reason for them evaporated.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	var ab: Dictionary = parsed.get("abilities", parsed)
	var riff: Dictionary = ab.get("riff", {})
	assert_eq(str(riff.get("effect", "")), "blind", "Riff must still inflict blind")
	assert_gt(float(riff.get("effect_chance", 0.0)), 0.0, "and on a real roll, not a zero chance")

func test_the_two_KNOWN_divergences_have_not_grown() -> void:
	## Not a fix — a floor under two balance calls that are struktured's. If either engine changes
	## its speed term or gains/loses weather, this reds and the difference gets decided rather than
	## drifting. Stated as what each engine DOES, so the red names the change.
	var live := _src(LIVE)
	var head := _src(RESOLVER)
	assert_true(live.contains("/ max(actual_target.speed, 1)"),
		"live still normalises the speed difference by the target's speed")
	assert_false(head.contains("/ max(target.speed, 1)"),
		"the headless resolver still uses the RAW speed difference — if this changed, the grind was retuned")
	assert_true(live.contains("get_weather_miss_bonus()"),
		"live still applies a weather miss bonus")
	assert_eq(head.count("weather"), 0,
		"the headless resolver still has no weather concept — if it gained one, the parity note needs rewriting")


## ── the rest of the gap, enumerated so it cannot grow quietly ─────────────────────────────────
## Blind was one of ELEVEN. The live engine reads 22 statuses; the grind reads 5. Seventeen are
## live-only, and eleven of those can be INFLICTED BY AN ABILITY — applied to a combatant in a grind
## and then read by nobody, exactly the shape blind had.
##
## ⚠️ NOT FIXED HERE, and the reason is scope rather than doubt. Blind had ONE consumer — the miss
## roll — so honouring it was four lines. `barrier` nullifies a hit at two live sites and the grind
## has six-plus take_damage paths; doing it properly is a change to the core damage loop with
## balance consequences for every grind, which is struktured's call and not an hour's work.
##
## What this arm does is hold the LIST. Implement one and it reds, so the note gets updated instead
## of the list quietly meaning less than it says. A new ignored status also reds.

const GRIND_IGNORES_BUT_ABILITIES_INFLICT := [
	"barrier",             # guardian_wall — and all three GUARDIAN PRESETS cast it in rule 0
	"charm",               # puppy_eyes
	"evasion",             # burrow
	"invisible",           # vanish
	"magic_block",         # access_denied
	"pacify",              # peace_sign
	"physical_reflect",    # port_block
	"prismatic_reflect",   # prismatic_reflect
	"reflect",             # magic_reflect
	"shadow_step",         # shadow_step
	"silence",             # void_pulse
]

func test_the_ignored_status_list_is_still_exactly_this() -> void:
	## Derived from both engines, not from the list above — the list is the CLAIM and the scan is
	## the measurement. They must agree, so implementing one or adding one both red.
	var live := _src(LIVE)
	var head := _src(RESOLVER)
	var re := RegEx.new()
	re.compile("has_status\\(\"([a-z_]+)\"\\)")
	var live_reads: Dictionary = {}
	for m in re.search_all(live):
		live_reads[m.get_string(1)] = true
	var head_reads: Dictionary = {}
	for m in re.search_all(head):
		head_reads[m.get_string(1)] = true
	assert_gt(live_reads.size(), 15, "CONTROL: the live engine's status reads are findable (%d)" % live_reads.size())
	assert_gt(head_reads.size(), 4, "CONTROL: the grind reads some statuses (%d)" % head_reads.size())
	assert_true(head_reads.has("blind"), "CONTROL: the fix above is in this measurement")

	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	var ab: Dictionary = parsed.get("abilities", parsed)
	var inflictable: Dictionary = {}
	for aid in ab:
		var a: Dictionary = ab[aid]
		for key in ["effect", "secondary_effect"]:
			var e: String = str(a.get(key, ""))
			if e != "" and live_reads.has(e) and not head_reads.has(e):
				inflictable[e] = true
	var found: Array = inflictable.keys()
	found.sort()
	var claimed: Array = GRIND_IGNORES_BUT_ABILITIES_INFLICT.duplicate()
	claimed.sort()
	assert_eq(found, claimed,
		"the set of statuses an ability can inflict and the grind ignores has CHANGED — if one was implemented, drop it from the list and say so; if one appeared, it is a new instance of the blind defect: " + str(found))

func test_the_guardian_presets_still_cast_the_inert_one() -> void:
	## The reason this is not a curiosity. I shipped three Guardian presets whose rule 0 casts
	## guardian_wall for 15 MP; it inflicts `barrier`, which the grind ignores — so the presets spend
	## a turn and the MP on nothing, in the mode the presets exist for. If barrier is ever honoured,
	## this arm reds and the note above it stops being true, which is the outcome to want.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/autobattle_rule_templates.json"))
	assert_not_null(parsed, "CONTROL: the template catalog parses")
	var casters: Array = []
	for t in (parsed.get("templates", []) as Array):
		if str((t as Dictionary).get("job_id", "")) != "guardian":
			continue
		for r in ((t as Dictionary).get("rules", []) as Array):
			for a in ((r as Dictionary).get("actions", []) as Array):
				if str((a as Dictionary).get("id", "")) == "guardian_wall":
					casters.append(str((t as Dictionary).get("id", "")))
	assert_eq(casters.size(), 3,
		"all three Guardian presets cast guardian_wall; if that changed, revisit why: " + str(casters))
