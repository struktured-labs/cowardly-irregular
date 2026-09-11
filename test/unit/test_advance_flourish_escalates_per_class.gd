extends GutTest

## "The more you advance the crazier the animation gets, and it's stylized per char class."
## — struktured 2026-09-10.
##
## Two independent axes, and keeping them independent is the whole design: INTENSITY rides the
## action count (2 is a flicker, 5 is a storm) and IDENTITY rides the job (a Mage's runes are a
## Mage's runes at every volume). If intensity were per-class the classes would read as unequal;
## if identity scaled with count a Bard at 5 would stop looking like a Bard.
##
## Geometric glyphs rather than sprite art on purpose: every job gets an identity today, including
## the five meta jobs that have no bespoke sheets, without blocking on the art lane.

const SCENE := "res://src/battle/BattleScene.gd"
const SceneScript = preload("res://src/battle/BattleScene.gd")

func _jobs() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_not_null(parsed, "CONTROL: jobs.json parses")
	var d: Dictionary = parsed
	return (d.get("jobs", d) as Dictionary).keys()

func test_intensity_rises_monotonically_with_the_action_count() -> void:
	var rings: Array = SceneScript.ADVANCE_FLOURISH_RINGS
	assert_eq(rings.size(), 6, "indices 0..5 — a 1-action queue is not an Advance, so 0 and 1 are unused")
	for n in range(3, rings.size()):
		assert_gt(int(rings[n]), int(rings[n - 1]),
			"%d actions must be visibly bigger than %d — got %d vs %d" % [n, n - 1, int(rings[n]), int(rings[n - 1])])

func test_the_full_bank_step_is_the_largest_jump() -> void:
	## The fifth action is the moment the AP economy builds toward, so the 4→5 step must not be just
	## another increment — otherwise the payoff reads as "one more hit".
	var rings: Array = SceneScript.ADVANCE_FLOURISH_RINGS
	var step_to_five: int = int(rings[5]) - int(rings[4])
	var step_to_four: int = int(rings[4]) - int(rings[3])
	assert_gt(step_to_five, step_to_four,
		"the full-bank step (%d) must exceed the step before it (%d)" % [step_to_five, step_to_four])

func test_every_job_in_the_game_has_a_flourish_shape() -> void:
	## The gap that would otherwise fall on the meta jobs — five jobs with no bespoke art, which is
	## exactly the set that silently defaulted to gray before the quip-colour fix in tick 124.
	var shapes: Dictionary = SceneScript.ADVANCE_FLOURISH_SHAPES
	var missing: Array = []
	for jid in _jobs():
		if not shapes.has(str(jid)):
			missing.append(jid)
	assert_gt(_jobs().size(), 10, "CONTROL: the job roster read non-empty (%d)" % _jobs().size())
	assert_eq(missing.size(), 0, "every job needs a flourish identity: " + str(missing))

func test_the_starter_jobs_do_not_all_share_one_shape() -> void:
	## The discriminator. A table that maps everything to "sparks" satisfies the coverage test above
	## and delivers no identity at all.
	var shapes: Dictionary = SceneScript.ADVANCE_FLOURISH_SHAPES
	var distinct: Dictionary = {}
	for jid in ["fighter", "cleric", "mage", "rogue", "bard"]:
		distinct[str(shapes.get(jid, ""))] = true
	## ⚠️ This said >= 4 and an arm proved it toothless: collapsing the Mage onto the Fighter's
	## sparks still left four distinct and passed. Five starters, five shapes — the whole point is
	## that a player can tell whose turn is flaring without reading the name.
	assert_eq(distinct.size(), 5,
		"each of the five starters needs its OWN shape, got %d distinct: %s" % [distinct.size(), str(distinct.keys())])

func test_the_flourish_is_driven_by_the_action_count_not_a_constant() -> void:
	## Source-level, because the particle spawn itself needs a live scene. Pins that the count is
	## actually threaded through rather than the arm playing one fixed effect.
	var src := FileAccess.get_file_as_string(SCENE)
	assert_gt(src.length(), 1000, "CONTROL: read BattleScene")
	assert_string_contains(src, "_spawn_advance_flourish(combatant, attacker_sprite, (action.get(\"actions\", []) as Array).size()",
		"the advance arm must pass the real action count")
	assert_string_contains(src, "ADVANCE_FLOURISH_RINGS[n]", "and the intensity must read the table by count")

func test_the_sfx_cues_are_named_per_step_for_the_audio_lane() -> void:
	## cowir-sfx needs five escalating cues plus a distinct full-bank hit. Naming them here is the
	## contract; a cue key with no file is silence, which is indistinguishable from "never fires".
	var src := FileAccess.get_file_as_string(SCENE)
	assert_string_contains(src, "advance_flourish_%d", "the escalating cue family must be keyed on the step")
	assert_string_contains(src, "full_bank_unleash", "and the full bank gets its own cue, not a louder fifth")

func test_the_press_ladder_does_not_go_flat_at_the_top() -> void:
	## The per-job press ladder was clamped to THREE rungs while the queue now goes to FIVE, so
	## presses 4 and 5 both replayed rung 3 — flat exactly where Full Bank made it matter.
	##
	## ⚠️ ASSERTS THE PROPERTY, NOT MY MECHANISM, and that distinction cost me the argument. My fix
	## sent presses above rung 3 to the non-job advance_flourish cues; cowir-sfx's walks DOWN to the
	## highest rung each job actually has. Theirs is better — mine lost the per-job voice at exactly
	## the depths that matter most, and a fixed clamp of 5 would drop a short-laddered job to the
	## arcade credit entirely. My first version of this test asserted "advance_flourish_%d is in the
	## function", which would have RED-FLAGGED the better implementation. A guard written around one
	## solution votes against every other one.
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_gt(src.length(), 1000, "CONTROL: read Win98Menu")
	var i: int = src.find("func _play_advance_sound")
	assert_gt(i, -1, "CONTROL: located the press-sound picker")
	var j: int = src.find("\nfunc ", i + 10)
	var body: String = src.substr(i, j - i) if j > i else src.substr(i)
	assert_false(body.contains("clampi(depth, 1, 3)"),
		"a hard clamp at rung 3 makes presses 4 and 5 replay rung 3 — the top of the ladder goes flat")
	assert_string_contains(body, "advance_queue",
		"and whatever it does above rung 3 must still fall back to the arcade credit rather than to silence")

func test_the_full_bank_beat_is_not_spawned_twice() -> void:
	## It rides BattleManager.full_bank_unleashed. An earlier draft ALSO called the handler directly
	## from the flourish, which would have doubled the screen flash and the cue.
	var src := FileAccess.get_file_as_string(SCENE)
	var i: int = src.find("func _spawn_advance_flourish")
	assert_gt(i, -1, "CONTROL: located the flourish")
	var j: int = src.find("\nfunc ", i + 10)
	var body: String = src.substr(i, j - i) if j > i else src.substr(i)
	assert_false(body.contains("_on_full_bank_unleashed("),
		"the flourish must not call the full-bank handler — the signal already does")
