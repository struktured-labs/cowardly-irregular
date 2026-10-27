extends GutTest

## THE DEFAULT AUTOBATTLE SCRIPTS WERE FROZEN AT THEIR LEVEL-1 KIT FOR THE WHOLE GAME.
##
## `AutobattleSystem._resolve_ability_upgrade` has existed and worked for months, and it delegates
## to `knows_ability` so it covers level, PURCHASE and secondary job (struktured 2026-09-06: "just
## have a general guard on if u have the ability or not at all, provenance irrelevant"). It upgrades
## a rule only when that rule authors an `upgrades` list — and ZERO of the 13 ability rows in
## `create_default_character_script` authored one. The resolver was built, delegated correctly, and
## authored on nothing: `learns_from` being read by no code, inverted.
##
## Measured before the fix, balance_harness at level 26 against Chancellor Mordaine:
##   Mage casts thunder for 1446   <- TIER 1, while it has known thundaga since level 13
## The party lost that fight by about one round while holding a third of the damage it owned.
##
## ⛔ THE POPULATION IS DERIVED FROM abilities.json, NOT LISTED HERE. A family's ladder is whatever
## `family` + `tier` say it is, so a fourth tier, a new family, or a new default row cannot land
## unauthored. A hand-listed expectation would have to be edited by the person who broke it.
##
## 🔑 AND IT HAS BOTH DIRECTIONS. A row whose baseline has NO family must author NO upgrades — the
## Fighter's power_strike and the Bard's songs have no ladder, so inventing one for them would be
## the mirror defect. Both populations are asserted non-empty first: a filter with nothing on one
## side of it reports a clean pass about a corpus that could not have failed.

const AB := "res://data/abilities.json"
const STARTER_JOBS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]


func before_each() -> void:
	if AutobattleSystem:
		AutobattleSystem._test_disable_persistence = true


## FLOOR. Named per receiver rather than per file: every arm below drives these two on
## AutobattleSystem, and a rename would otherwise abort each arm after its first assert and score
## the file green (CLAUDE.md's rung-3 silence).
func test_the_subject_exposes_what_every_arm_below_drives() -> void:
	assert_not_null(AutobattleSystem, "AutobattleSystem autoload must exist")
	assert_true(AutobattleSystem.has_method("create_default_character_script"),
		"AutobattleSystem.create_default_character_script is the subject of this whole file")
	assert_true(AutobattleSystem.has_method("validate_rule"),
		"AutobattleSystem.validate_rule is what the fizzle arm reads")
	assert_true(AutobattleSystem.has_method("_resolve_ability_upgrade"),
		"_resolve_ability_upgrade is the consumer that makes an authored `upgrades` list mean anything")


func _abilities() -> Dictionary:
	var f := FileAccess.open(AB, FileAccess.READ)
	assert_not_null(f, "%s must open" % AB)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and (parsed as Dictionary).has("abilities"):
		return (parsed as Dictionary)["abilities"]
	return parsed if parsed is Dictionary else {}


## Every id in `family`, strictly above `tier`, in ascending tier order — which is the order
## _resolve_ability_upgrade requires, because it keeps the LAST learned candidate it sees.
func _ladder_above(abilities: Dictionary, family: String, tier: int) -> Array[String]:
	var rungs: Array = []
	for aid in abilities:
		var a: Variant = abilities[aid]
		if not (a is Dictionary):
			continue
		if str((a as Dictionary).get("family", "")) != family:
			continue
		var t: int = int((a as Dictionary).get("tier", 0))
		if t > tier:
			rungs.append([t, str(aid)])
	rungs.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	var out: Array[String] = []
	for r in rungs:
		out.append(str(r[1]))
	return out


## Each ability action of each starter job's default script, as {job, ability_id, upgrades}.
func _ability_rows() -> Array:
	var rows: Array = []
	for job in STARTER_JOBS:
		var script: Dictionary = AutobattleSystem.create_default_character_script(job)
		for rule in (script.get("rules", []) as Array):
			for action in ((rule as Dictionary).get("actions", []) as Array):
				if str((action as Dictionary).get("type", "")) != "ability":
					continue
				rows.append({
					"job": job,
					"id": str((action as Dictionary).get("id", "")),
					"upgrades": (action as Dictionary).get("upgrades", []),
				})
	return rows


func test_a_row_whose_ability_has_a_family_authors_that_familys_whole_ladder() -> void:
	var abilities: Dictionary = _abilities()
	assert_gt(abilities.size(), 0, "CONTROL: abilities.json parsed, else every derivation below is empty")
	var rows: Array = _ability_rows()
	assert_gt(rows.size(), 0, "CONTROL: the five default scripts contain ability rows at all")

	var laddered: int = 0
	for row in rows:
		var a: Variant = abilities.get(row["id"], null)
		if not (a is Dictionary):
			continue
		var family: String = str((a as Dictionary).get("family", ""))
		if family == "":
			continue
		var want: Array[String] = _ladder_above(abilities, family, int((a as Dictionary).get("tier", 0)))
		if want.is_empty():
			continue
		laddered += 1
		var got: Array = row["upgrades"] as Array
		var got_s: Array[String] = []
		for g in got:
			got_s.append(str(g))
		assert_eq(got_s, want,
			"%s's default script casts '%s' (family %s) — it must author that family's whole ladder %s, got %s" % [
				row["job"], row["id"], family, str(want), str(got_s)])

	## The number that makes the loop above mean something. Derived, not pinned: today it is the
	## Mage's fire and thunder rows plus the Cleric's two cure rows.
	assert_gt(laddered, 0,
		"CONTROL: no default-script row has a family ladder, so the assertions above ran on nothing")


func test_a_row_with_no_ladder_does_not_invent_one() -> void:
	var abilities: Dictionary = _abilities()
	var rows: Array = _ability_rows()
	var unladdered: int = 0
	for row in rows:
		var a: Variant = abilities.get(row["id"], null)
		var family: String = ""
		var tier: int = 0
		if a is Dictionary:
			family = str((a as Dictionary).get("family", ""))
			tier = int((a as Dictionary).get("tier", 0))
		if family != "" and not _ladder_above(abilities, family, tier).is_empty():
			continue
		unladdered += 1
		assert_eq((row["upgrades"] as Array).size(), 0,
			"%s's '%s' has no authored family ladder — an `upgrades` list on it points at a tier that does not exist" % [
				row["job"], row["id"]])
	assert_gt(unladdered, 0,
		"CONTROL: every row has a ladder, so this arm's filter passed nothing and proves nothing")


## THE FIZZLE CONTRACT, SCOPED TO WHAT THIS CHANGE TOUCHED. `validate_rule`'s MP check takes the
## WORST CASE across baseline and upgrades, so authoring a 32 MP tier-3 upgrade onto an 8 MP row
## RAISES that row's required `mp_percent` guard. firaga is 32 MP of the Mage's base 80 pool, so the
## guard has to clear 40%; cura is 12 of the Cleric's 70, so 18%. Getting either wrong burns the
## character's turn on a spell it cannot pay for -- worse than casting the tier-1 spell.
##
## The corpus is the rows that AUTHOR a ladder, derived, with a non-empty control. Said plainly
## because the arm below exists: the default scripts carry fizzle violations that PREDATE this
## change, and a broad arm here would have reported their failure as this change's.
func test_no_row_with_an_authored_ladder_can_fizzle_its_turn() -> void:
	var checked: int = 0
	for job in STARTER_JOBS:
		var script: Dictionary = AutobattleSystem.create_default_character_script(job)
		var rules: Array = script.get("rules", []) as Array
		assert_gt(rules.size(), 0, "%s's default script must have rules" % job)
		for i in range(rules.size()):
			var authored: bool = false
			for action in ((rules[i] as Dictionary).get("actions", []) as Array):
				if ((action as Dictionary).get("upgrades", []) as Array).size() > 0:
					authored = true
			if not authored:
				continue
			checked += 1
			var errors: Array = AutobattleSystem.validate_rule(rules[i] as Dictionary, job)
			assert_eq(errors.size(), 0, "%s default rule %d authors a ladder: %s" % [job, i, ", ".join(errors)])
	assert_gt(checked, 0, "CONTROL: no default-script rule authors a ladder, so this arm judged nothing")


## A SEPARATE, PRE-EXISTING DEFECT, RATCHETED RATHER THAN FIXED HERE. Driving `validate_rule` over
## EVERY default rule reds on seven rows this change never touched -- measured on the tree before it:
##   fighter 2     power_strike 8 MP (27% of base) unguarded
##   cleric 0/1/2  `esuna` is not in the Cleric's level-1 kit
##   rogue 2/3     steal 4 MP, backstab 14 MP (35%) unguarded
##   bard 3        `inspiring_melody` not in the level-1 kit, and 15 MP unguarded
## `test_autobattle_rule_templates_regression` enforces this exact contract on the PRESET CATALOG in
## `data/`, and nothing enforced it on the built-in defaults in code -- so the defect that lint
## exists to prevent sat in the scripts every fresh character actually gets.
##
## MEMBERSHIP, NOT A COUNT. A pinned 7 says nothing about WHICH seven, and right-count-wrong-
## membership is the shape of my own retractions. A subset check lets a fix pass for free, reds with
## the offender's name when a new one lands, and leaves the debt readable.
const KNOWN_FIZZLE_DEBT: Array[String] = [
	"fighter:2", "cleric:0", "cleric:1", "cleric:2", "rogue:2", "rogue:3", "bard:3",
]


func test_the_default_scripts_fizzle_debt_does_not_grow() -> void:
	var offenders: Array[String] = []
	for job in STARTER_JOBS:
		var script: Dictionary = AutobattleSystem.create_default_character_script(job)
		var rules: Array = script.get("rules", []) as Array
		for i in range(rules.size()):
			if AutobattleSystem.validate_rule(rules[i] as Dictionary, job).size() > 0:
				offenders.append("%s:%d" % [job, i])
	for o in offenders:
		assert_true(o in KNOWN_FIZZLE_DEBT,
			"NEW fizzle violation at %s -- a default rule that cannot pay for itself burns the turn" % o)
	## The other direction, so the list cannot quietly describe rules that no longer exist.
	assert_gt(offenders.size(), 0,
		"CONTROL: validate_rule found nothing anywhere, so the subset check above passed vacuously")
