extends GutTest

## The audio tier gates read the WRONG time_scale (found by cowir-autogrind, 2026-08-15).
##
## Engine.time_scale has TWO writers with different meanings:
##   the speed ladder  -> the player's chosen speed          (INTENT)
##   _begin_hitlag     -> 0.1 for ~80ms after a crit         (a presentation EFFECT)
##
## presentation_tier() asks "how much presentation does the player want", so reading the
## live global answers with whatever the last writer meant. _crit_visual_burst() calls
## _begin_hitlag() at BattleScene:4433, and the crit-thud gate sat at :4490 — same function,
## burst first. So the gate read 0.1 and returned FULL at every ladder speed: inert exactly
## on the event it gates.
##
## My original tests asserted the gate's SOURCE TEXT contained "Tier.FULL". That is true of
## an inert gate, which is why they passed. These assert the VALUE instead.

const SCENE_SRC: String = "res://src/battle/BattleScene.gd"


func test_premise_hitlag_LOOKS_like_full_presentation() -> void:
	## The hazard itself. 0.1 is below the FULL boundary, so any live read during hitlag
	## reports maximum presentation regardless of what the player selected.
	assert_eq(BattleJuice.presentation_tier(0.1, false, false), BattleJuice.Tier.FULL,
		"PREMISE: the hitlag scale must land in FULL, else this whole regression is moot")
	assert_eq(BattleJuice.presentation_tier(1.0, false, false), BattleJuice.Tier.REDUCED,
		"PREMISE: 4x (engine 1.0) must be REDUCED — that is the tier hitlag was masking")


func test_the_ladder_speed_and_the_hitlag_speed_DISAGREE() -> void:
	## If these ever agree the bug is unreproducible and the guard below means nothing.
	var ladder: int = BattleJuice.presentation_tier(1.0, false, false)
	var during_hitlag: int = BattleJuice.presentation_tier(0.1, false, false)
	assert_ne(ladder, during_hitlag,
		"control: the two readings must differ at 4x, or this test cannot detect the defect")


func test_intent_tier_holds_across_EVERY_SHIPPED_LADDER_RUNG_during_a_hitlag() -> void:
	## THE LOAD-BEARING GUARD, asserted as a VALUE on a real instance, driven by the SHIPPED
	## ladder rather than hand-picked speeds. Two lanes disagreed about which tiers the ladder
	## can even reach — one enumerated 3 of 7 rungs and concluded MINIMAL was unreachable. A
	## hand-written speed list here would inherit exactly that error, so iterate the const.
	var scene = load(SCENE_SRC).new()
	assert_not_null(scene, "control: BattleScene script must instantiate")
	scene.turbo_mode = false
	scene.autogrind_console_mode = false

	var ladder: Array = scene.BATTLE_SPEEDS
	assert_gt(ladder.size(), 4, "control: read %d ladder rungs — the const did not resolve" % ladder.size())

	var saved: float = Engine.time_scale
	var tiers_seen: Dictionary = {}
	var broken: Array[String] = []
	for speed in ladder:
		scene._hitlag_depth = 0
		Engine.time_scale = speed
		var want: int = scene._intent_tier()
		tiers_seen[want] = true
		# Enter a hitlag exactly as _hitlag_enter does: stash the base, stamp the global.
		scene._hitlag_base_scale = speed
		scene._hitlag_depth = 1
		Engine.time_scale = scene.HITLAG_SCALE
		var during: int = scene._intent_tier()
		if during != want:
			broken.append("engine %s: %d outside vs %d during hitlag" % [speed, want, during])
	Engine.time_scale = saved
	scene.free()

	assert_gt(tiers_seen.size(), 2,
		"control: the ladder produced only %d distinct tiers — if it cannot reach a non-FULL tier this test proves nothing" % tiers_seen.size())
	assert_eq(broken.size(), 0,
		"the intent tier CHANGED during a hitlag on %d rung(s): %s. It is reading the 80ms crit effect instead of the player's chosen speed, so every `== Tier.FULL` audio gate fires at speeds where the player asked for less." % [broken.size(), broken])


func test_the_audio_gates_do_NOT_use_the_live_tier() -> void:
	## Pins that both gates route through the intent-aware helper. A source check is weak on
	## its own, which is how the defect shipped — it is here only to catch a regression back
	## to _tier(), with the VALUE test above carrying the real weight.
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	assert_gt(src.length(), 1000, "SCOPE control: BattleScene.gd read back empty")
	for gate in ["audio_kill_duck", "audio_crit_thud"]:
		var at: int = src.find(gate)
		assert_gt(at, 0, "gate %s is missing" % gate)
		var line_start: int = src.rfind("\n", at) + 1
		var line: String = src.substr(line_start, at - line_start + gate.length() + 2)
		assert_true(line.contains("_intent_tier()"),
			"the %s gate reads the live tier. A crit sets Engine.time_scale to 0.1 before this line runs, so == Tier.FULL is satisfied at every ladder speed: %s" % [gate, line.strip_edges()])
		assert_false(line.contains("_tier()") and not line.contains("_intent_tier()"),
			"the %s gate still calls _tier() directly" % gate)


func test_hitlag_is_NOT_itself_tier_gated_which_is_why_this_is_reachable() -> void:
	## Documents why the interaction exists at all: hitlag fires regardless of tier, so it
	## can raise the apparent tier on any speed. If hitlag ever becomes tier-gated this
	## regression narrows and the note above should be revisited rather than deleted.
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	var at: int = src.find("func _hitlag_enter")
	assert_gt(at, 0, "control: _hitlag_enter must exist")
	var rest: String = src.substr(at)
	var stop: int = rest.find("\nfunc ")
	var body: String = rest.substr(0, stop) if stop > 0 else rest
	assert_false(body.contains("presentation_tier") or body.contains("_tier()"),
		"_hitlag_enter now consults the tier — the two-writer hazard may have changed shape; re-read this file's header before trusting it")
