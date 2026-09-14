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

func _l1(a: Color, b: Color) -> float:
	return abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)

## The floor is DERIVED, not chosen: the closest two DISTINCT job colours are the smallest gap this
## game already treats as two different identities, so the enemy tint must clear at least that. My
## first version hardcoded 0.25 — and the tint I was defending sat 0.280 from the Fighter, CLOSER to
## a job than any two jobs are to each other, passing a threshold picked to let it pass. A one-sided
## threshold with no known-good residual behind it is a vote, not a check.
func test_the_enemy_tint_clears_the_palettes_own_separation() -> void:
	var palette: Dictionary = BattleSceneScript.JOB_QUIP_COLORS
	assert_gt(palette.size(), 4, "CONTROL: the palette is populated (%d)" % palette.size())
	var jobs: Array = palette.keys()

	var residual: float = 99.0
	for i in jobs.size():
		for j in range(i + 1, jobs.size()):
			residual = minf(residual, _l1(palette[jobs[i]], palette[jobs[j]]))
	assert_gt(residual, 0.0, "CONTROL: the palette holds distinct colours (residual %.3f)" % residual)

	var enemy: Color = BattleSceneScript.ADVANCE_FLOURISH_ENEMY_COLOR
	var too_close: Array = []
	for jid in jobs:
		var dist: float = _l1(palette[jid], enemy)
		if dist < residual:
			too_close.append("%s (%.3f < %.3f)" % [jid, dist, residual])
	assert_eq(too_close.size(), 0,
		"the enemy tint sits closer to a job than the two closest jobs sit to each other, so it reads as that job: " + str(too_close))

func test_the_enemy_tint_carries_no_class_identity() -> void:
	## The other half of "neutral". A saturated tint far from every job in RGB would clear the test
	## above and still read as AN identity — just an unassigned one. A monster has no class, so its
	## flourish should be near-grey rather than a fourteenth hue.
	var e: Color = BattleSceneScript.ADVANCE_FLOURISH_ENEMY_COLOR
	var chroma: float = maxf(e.r, maxf(e.g, e.b)) - minf(e.r, minf(e.g, e.b))
	assert_lt(chroma, 0.2, "the enemy tint must be near-grey, not a new job colour (chroma %.3f)" % chroma)
	assert_gt(e.r + e.g + e.b, 1.2, "and still bright enough to read against a dark battle background")

func test_both_flourish_sites_use_the_chooser() -> void:
	## EXECUTION is not SELECTION: the helper being correct says nothing about the flourish reaching
	## it. Two sites feed the flourish — the per-action aura and the full-bank flash — and a fix
	## applied to one of them looks complete while the other still tints an enemy Fighter-red.
	##
	## ⛔ This pinned the chooser's call COUNT at exactly 2, and the queue aura (2026-09-14) redded it
	## by adding two more correct sites — the count could not tell a new routed site from a dropped
	## one. It now names every site that colours an Advance flourish and requires the chooser in each,
	## which catches a dropped site exactly as the count did and lets a correct one through.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var chooser := "advance_flourish_color(combatant, _get_job_quip_color(combatant))"
	var bypassed: Array = []
	for fn in ["_spawn_advance_flourish", "_on_full_bank_unleashed", "_on_advance_queue_changed", "_spawn_advance_queue_pop"]:
		var at: int = src.find("func %s(" % fn)
		assert_gt(at, -1, "CONTROL: flourish site %s exists" % fn)
		var end: int = src.find("\nfunc ", at + 5)
		if not src.substr(at, (end - at) if end > at else 3000).contains(chooser):
			bypassed.append(fn)
	assert_eq(bypassed.size(), 0,
		"every Advance flourish site must pick its colour through the chooser, or an enemy flares Fighter-red: " + str(bypassed))
