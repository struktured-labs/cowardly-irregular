extends GutTest

## ⛔ A COMMENT PROMISED A STAGGER AND THE CODE FIRED EVERY LUNGE IN THE SAME FRAME.
## `_on_group_attack_executing`'s limit_break arm carried "# Stagger lunges slightly for visual
## impact" — no delay, no offset, no timer — while four lines above, the outer comment said
## "simultaneously". The file asserted both, and the code did the second.
##
## Found by cowir-sfx (11864) asking rather than assuming, while chasing an unrelated audio null.
##
## ⚠️ THE AUDIO NULL WAS DOWNSTREAM OF THIS. `play_attack_hit` keys on `attack_hit_<weapon_type>`
## and drops a repeat inside SFX_MIN_INTERVAL_MS (80). Two same-weapon members striking in one frame
## lose a cue — and the +3%/hit pitch ramp, which exists to make a chain read as a chain, had nothing
## to ramp across. A real stagger fixes the visual AND turns on an authored audio feature that has
## shipped unheard.
##
## ⚠️ WHY 0.12 AND NOT THE ANIMATOR'S 0.08, rejected twice for unrelated reasons:
##   cowir-cutscenes  0.08 paces phases WITHIN a lunge; this spaces lunges BETWEEN members. Different
##                    quantities that would look coupled and drift apart.
##   cowir-sfx        0.08 s IS SFX_MIN_INTERVAL_MS. `80 < 80` is false by one millisecond, so a
##                    frame landing 79 ms apart eats the second strike — a threshold that reads as a
##                    flake.
## The value is the smallest that makes the collision impossible. Whether the cascade should be that
## LONG is struktured's call and the constant exists to be turned.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const SCENE_PATH := "res://src/battle/BattleScene.gd"
const SceneScript = preload("res://src/battle/BattleScene.gd")


func test_the_interval_clears_the_audio_threshold_it_has_to_clear() -> void:
	## The LOWER BOUND is measured, not chosen — so it gets an arm, and the arm names the coupling
	## rather than restating the number.
	var min_interval_ms: float = float(SoundManager.SFX_MIN_INTERVAL_MS)
	assert_gt(min_interval_ms, 0.0, "CONTROL: the cue cooldown is a real, positive threshold")
	assert_gt(SceneScript.LIMIT_BREAK_LUNGE_STAGGER_SEC * 1000.0, min_interval_ms,
		"the stagger must be STRICTLY longer than the same-key cue cooldown (%d ms), or same-weapon members silently lose a strike sound" % int(min_interval_ms))
	assert_gt(SceneScript.LIMIT_BREAK_LUNGE_STAGGER_SEC * 1000.0, min_interval_ms * 1.25,
		"with headroom, because the stagger is wall-clock through a timer and a frame boundary can land under an exact match")


func test_the_stagger_is_not_the_animators_phase_constant() -> void:
	## Two quantities that would look related and drift independently. If someone ever makes them
	## equal, this says why that is wrong rather than leaving the next reader to infer a coupling.
	assert_ne(SceneScript.LIMIT_BREAK_LUNGE_STAGGER_SEC, 0.08,
		"the stagger spaces lunges BETWEEN members; 0.08 paces phases WITHIN one — and it is also exactly the cue cooldown")


func test_each_lunge_is_offset_by_its_position_in_the_cascade() -> void:
	## The arithmetic the loop performs, pinned independently of the scene: member N starts N
	## intervals in, so the cascade is even and the first member is not delayed at all.
	for n in 5:
		var lead_in: float = float(n) * SceneScript.LIMIT_BREAK_LUNGE_STAGGER_SEC
		assert_almost_eq(lead_in, SceneScript.LIMIT_BREAK_LUNGE_STAGGER_SEC * n, 0.0001,
			"member %d leads in by %d intervals" % [n, n])
		if n == 0:
			assert_eq(lead_in, 0.0, "the first lunge is not delayed — a stagger adds nothing to the front")
	var five_span: float = 4.0 * SceneScript.LIMIT_BREAK_LUNGE_STAGGER_SEC
	assert_gt(five_span, float(SoundManager.SFX_MIN_INTERVAL_MS) / 1000.0 * 4.0,
		"a five-member cascade spans four intervals, every one clear of the cue cooldown")


func test_the_loop_staggers_and_does_not_await() -> void:
	## ⚠️ SOURCE PIN, and the await half is the load-bearing one. CLAUDE.md: "`await` in a loop
	## SERIALIZES what should be simultaneous" — inverted here, an await would turn a 5-member
	## cascade into five sequential FULL lunges, which is far worse than the simultaneity it replaced.
	var code: String = GdSourceHelper.code_of(SCENE_PATH)
	var at: int = code.find("func _on_group_attack_executing(")
	assert_gt(at, -1, "CONTROL: the group-attack handler survives stripping")
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, (nxt - at) if nxt > at else 9000)
	assert_true(body.contains("float(lunges_started) * LIMIT_BREAK_LUNGE_STAGGER_SEC"),
		"the lead-in scales with the member's place in the cascade")
	assert_true(body.contains("_animate_melee_attack(sprite, target_sprite, anim, target_anim, lead_in)"),
		"and is handed to the lunge")
	assert_false(body.contains("await"),
		"the participant loop must not await — that is the serialisation trap, pointed the other way")
	assert_false(body.contains("# Stagger lunges slightly for visual impact"),
		"the comment that described a stagger nobody implemented is gone")


func test_the_lunge_applies_the_lead_in_as_a_tween_interval() -> void:
	var code: String = GdSourceHelper.code_of(SCENE_PATH)
	var at: int = code.find("func _animate_melee_attack(")
	assert_gt(at, -1, "CONTROL: the lunge survives stripping")
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, (nxt - at) if nxt > at else 6000)
	assert_true(body.contains("lead_in: float = 0.0"),
		"the lead-in defaults to zero, so every OTHER caller is unchanged")
	assert_true(body.contains("tween.tween_interval(lead_in)"),
		"and is applied to the tween rather than to the caller")


func test_the_impact_travels_with_its_own_lunge() -> void:
	## The effect used to spawn immediately for every member. Shifted by the same lead-in, or five
	## impacts land while only the first sprite has moved.
	var code: String = GdSourceHelper.code_of(SCENE_PATH)
	assert_true(code.contains("_spawn_impact_after(lead_in, target_sprite, _weapon_type_for(participant))"),
		"the impact is shifted by the same lead-in as its lunge")
	var at: int = code.find("func _spawn_impact_after(")
	assert_gt(at, -1, "CONTROL: the helper survives stripping")
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, (nxt - at) if nxt > at else 1200)
	assert_true(body.contains("create_timer(delay).timeout.connect("),
		"timer-and-connect, the idiom this file already uses — never an await")
	assert_true(body.contains("if delay <= 0.0:"),
		"and a zero delay spawns immediately rather than waiting a frame, so non-staggered callers are unchanged")
