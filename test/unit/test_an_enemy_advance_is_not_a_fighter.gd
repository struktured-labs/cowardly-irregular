extends GutTest

## The Advance flourish is per-class BY DESIGN (struktured 2026-09-10: "stylized per char class").
## Enemies Advance too — measured at ~13% of duel-opponent turns — and a monster Combatant carries
## no `job`, so `_get_job_quip_color` fell through to its "fighter" default and every enemy Advance
## came out in the FIGHTER'S red.
##
## Worth saying why nothing caught it: the six combat-quip sites are each guarded by
## `in BattleManager.player_party`, so that "fighter" default was unreachable for a monster until
## the flourish became the palette's first non-party caller. The defect arrived with MY caller, not
## with the helper — checking the call sites is what separated the two.
##
## Fixed by choosing the colour in one place rather than by widening the palette, so the quip
## helper — pinned by five other test files — keeps meaning exactly what it meant.

const BattleSceneScript = preload("res://src/battle/BattleScene.gd")
const PARTY_COLOR := Color(0.2, 0.4, 0.9)

func _combatant(job_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Subject"
	if job_id != "":
		c.job = {"id": job_id}
	return c

func test_an_enemy_does_not_borrow_the_party_palette() -> void:
	var got: Color = BattleSceneScript.advance_flourish_color(_combatant(""), PARTY_COLOR)
	assert_ne(got, PARTY_COLOR,
		"a jobless combatant is a monster — its Advance must not wear a party job's colour")

func test_a_party_member_keeps_its_own_class_colour() -> void:
	## The half that must NOT change: the whole point of the flourish is per-class identity.
	assert_eq(BattleSceneScript.advance_flourish_color(_combatant("mage"), PARTY_COLOR), PARTY_COLOR,
		"a real job must pass its colour through untouched")

func test_every_job_passes_through() -> void:
	## Guards against a fix that special-cases one job: the pass-through must be about HAVING a job,
	## not about which one. A jobs.json entry the helper had never seen must behave like the rest.
	for jid in ["fighter", "cleric", "mage", "rogue", "bard", "necromancer", "bossbinder"]:
		assert_eq(BattleSceneScript.advance_flourish_color(_combatant(jid), PARTY_COLOR), PARTY_COLOR,
			"%s must keep its own colour" % jid)

func test_a_null_combatant_is_treated_as_an_enemy_not_a_crash() -> void:
	## `_on_full_bank_unleashed` takes its combatant off a signal; a freed one arrives as null.
	assert_eq(BattleSceneScript.advance_flourish_color(null, PARTY_COLOR),
		BattleSceneScript.ADVANCE_FLOURISH_ENEMY_COLOR,
		"null must land on the neutral tint rather than reaching the palette at all")

func test_the_enemy_tint_is_distinguishable_from_every_job_colour() -> void:
	## The fix is only a fix if the result READS as different on a TV. A neutral that happens to
	## equal a job's colour would pass every assertion above and change nothing on screen.
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(scene_src.contains("JOB_QUIP_COLORS"), "CONTROL: the palette still exists")
	var enemy: Color = BattleSceneScript.ADVANCE_FLOURISH_ENEMY_COLOR
	var palette: Dictionary = BattleSceneScript.JOB_QUIP_COLORS
	assert_gt(palette.size(), 4, "CONTROL: the palette is populated (%d)" % palette.size())
	var too_close: Array = []
	for jid in palette:
		var c: Color = palette[jid]
		var dist: float = abs(c.r - enemy.r) + abs(c.g - enemy.g) + abs(c.b - enemy.b)
		if dist < 0.25:
			too_close.append("%s (%.2f)" % [jid, dist])
	assert_eq(too_close.size(), 0,
		"the enemy tint must be visibly apart from every job colour, or the fix is invisible: " + str(too_close))

func test_both_flourish_sites_use_the_chooser() -> void:
	## EXECUTION is not SELECTION: the helper being correct says nothing about the flourish reaching
	## it. Two sites feed the flourish — the per-action aura and the full-bank flash — and a fix
	## applied to one of them looks complete while the other still tints an enemy Fighter-red.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_eq(src.count("advance_flourish_color(combatant, _get_job_quip_color(combatant))"), 2,
		"both the Advance aura and the full-bank flash must pick their colour through the chooser")
