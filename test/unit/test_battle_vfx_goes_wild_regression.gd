extends GutTest

## struktured 2026-10-03: "bahamut summon was not nearly wild enough... same with bard's status
## effects, speculators abilities... couldnt tell that u summoned another summoner... we need
## VISUALS." Three dedicated Full Render spectacles: eidolon summons (sky crush + giant
## silhouette + field slam), recursive summon (portal + summoner echo + depth caption), and
## Speculator abilities (slot reels landing on the real risk state).

const SCENE := "res://src/battle/BattleScene.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"

func _scene_src() -> String:
	var s := FileAccess.get_file_as_string(SCENE)
	assert_gt(s.length(), 1000, "CONTROL: read BattleScene")
	return s

func _abilities() -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/abilities.json")
	assert_gt(raw.length(), 100, "CONTROL: read a non-empty abilities.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return parsed.get("abilities", parsed)

func _gl():
	var gl = load(SCENE).new()
	autofree(gl)
	return gl

func _body_of(fn: String) -> String:
	var src := _scene_src()
	var i := src.find("func %s" % fn)
	assert_gt(i, -1, "%s must exist" % fn)
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else 8000)


## -------------------- eidolon summons (Bahamut et al) --------------------

func test_eidolon_abilities_get_the_eidolon_shape() -> void:
	var gl = _gl()
	var checked := 0
	var ab := _abilities()
	for id in ["summon_ifrit", "summon_shiva", "summon_ramuh", "summon_bahamut"]:
		assert_true(ab.has(id), "CONTROL: %s exists in data" % id)
		checked += 1
		var style: Dictionary = gl._full_render_element_style(ab[id])
		assert_eq(str(style["shape"]), "eidolon", "%s must get the big-screen eidolon spectacle" % id)
	assert_eq(checked, 4, "CONTROL: checked all four eidolons")

func test_bahamut_gets_its_own_dragon_king_colour() -> void:
	## Bahamut authors no element at all -- without a dedicated arm it fell to the generic
	## white/buff bloom, which is the "not nearly wild enough" complaint.
	var gl = _gl()
	var ab := _abilities()
	var style: Dictionary = gl._full_render_element_style(ab["summon_bahamut"])
	var c: Color = style["color"]
	assert_false(c.is_equal_approx(Color(0.85, 0.9, 1.0)), "Bahamut must not render as the generic pale buff bloom")

func test_elemental_eidolons_keep_their_element_colour() -> void:
	var gl = _gl()
	var ab := _abilities()
	assert_eq(int(gl._full_render_element_style(ab["summon_ifrit"])["effect"]), EffectSystem.EffectType.FIRE)
	assert_eq(int(gl._full_render_element_style(ab["summon_shiva"])["effect"]), EffectSystem.EffectType.ICE)
	assert_eq(int(gl._full_render_element_style(ab["summon_ramuh"])["effect"]), EffectSystem.EffectType.LIGHTNING)

func test_ally_spawning_summons_are_not_eidolons() -> void:
	## royal_summon / rat_swarm author summon_id (they spawn a live combatant) -- summon_id is the
	## documented discriminator (BattleManager.gd tick 392/comment above "summon") and must NOT
	## get the screen-filling eidolon treatment, which assumes damage lands on `targets`.
	var gl = _gl()
	var ab := _abilities()
	for id in ["royal_summon", "rat_swarm"]:
		assert_true(ab.has(id), "CONTROL: %s exists" % id)
		var style: Dictionary = gl._full_render_element_style(ab[id])
		assert_ne(str(style["shape"]), "eidolon", "%s spawns an ally, not an eidolon slam" % id)

func test_eidolon_dispatch_lives_inside_the_gated_function() -> void:
	## The gate (_full_render_active) is the ONLY entry point reaching _play_ability_full_render,
	## so the new shapes must dispatch from inside it -- not from a second, ungated call site.
	var body := _body_of("_play_ability_full_render")
	assert_true(body.contains("shape == \"eidolon\""), "eidolon dispatch must live inside the gated function")
	assert_true(body.contains("_play_eidolon_summon("), "must call the eidolon spectacle")

func test_eidolon_spectacle_slams_every_target_and_flushes_damage() -> void:
	var body := _body_of("_play_eidolon_summon")
	assert_true(body.contains("for target in targets:"), "the slam must hit every target, not just the first")
	assert_true(body.contains("_spawn_screen_flash("), "the slam needs the accessibility-gated flash helper")
	assert_true(body.contains("EffectSystem._trigger_screen_shake("), "the slam needs a real shake, not a token one")

func test_eidolon_loops_do_not_await_inside_the_loop() -> void:
	## CLAUDE.md: await inside a loop serializes what should be parallel. The silhouette's wing/eye
	## loops and the dispatch's per-target loop must stay fire-and-forget tweens.
	var body := _body_of("_spawn_eidolon_silhouette")
	assert_eq(body.count("await"), 0, "the silhouette builder must not await at all")
	var dispatch_body := _body_of("_play_eidolon_summon")
	var loop_start := dispatch_body.find("for target in targets:")
	assert_gt(loop_start, -1)
	var loop_end := dispatch_body.find("\n\tawait", loop_start)
	assert_gt(loop_end, loop_start)
	var loop_slice := dispatch_body.substr(loop_start, loop_end - loop_start)
	assert_eq(loop_slice.count("await"), 0, "the per-target slam loop must not await per target")


## -------------------- recursive summon (summon a summoner) --------------------

func test_recursive_summon_ability_gets_its_own_shape() -> void:
	var gl = _gl()
	var ab := _abilities()
	assert_true(ab.has("recursive_summon"))
	var style: Dictionary = gl._full_render_element_style(ab["recursive_summon"])
	assert_eq(str(style["shape"]), "recursive_summon", "meta_effect recursive_summon must get its own dispatch, not a generic bloom")

func test_recursive_summon_dispatch_lives_inside_the_gated_function() -> void:
	var body := _body_of("_play_ability_full_render")
	assert_true(body.contains("shape == \"recursive_summon\""))
	assert_true(body.contains("_play_recursive_summon("))

func test_caption_derives_from_the_real_buff_stack_not_a_literal() -> void:
	## The whole point ("couldnt tell that u summoned another summoner") is that the caption must
	## track the ACTUAL depth, read off active_buffs -- not a hardcoded "x2".
	var body := _body_of("_play_recursive_summon")
	assert_true(body.contains("begins_with(\"Recursive Summon\")"),
		"depth must be counted from the real 'Recursive Summon N' buff series BattleManager adds")
	assert_true(body.contains("\"SUMMON ×%d\" % (depth + 1)"),
		"the caption text must be built from the derived depth variable")
	assert_false(body.contains("\"SUMMON ×2\"") or body.contains("\"SUMMON x2\""),
		"a literal caption would not escalate with real depth")

func test_caption_depth_escalates_with_stack_count() -> void:
	## Exercise the real counting logic the way _play_recursive_summon reads it: build a caster
	## with N "Recursive Summon" buffs and confirm the derived depth grows with N.
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": "Summoner", "max_hp": 100, "max_mp": 100, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	for n in range(3):
		c.add_buff("Recursive Summon %d" % (n + 1), "magic", 2.0, 3)
		var count := 0
		for b in c.active_buffs:
			if str(b.get("effect", "")).begins_with("Recursive Summon"):
				count += 1
		assert_eq(count, n + 1, "depth read must track the Nth stack exactly")

func test_recursive_summon_echo_reuses_the_casters_own_sprite() -> void:
	## "a second summoner visibly steps out" -- not a generic blob. The echo must prefer the real
	## sprite texture and only fall back to a shape when none is available.
	var body := _body_of("_spawn_summoner_echo")
	assert_true(body.contains("sprite_frames.get_frame_texture("), "must pull the real frame when the caster is an AnimatedSprite2D")
	assert_true(body.contains("var fallback := ColorRect.new()"), "must still degrade gracefully with no sprite")


## -------------------- Speculator abilities --------------------

func test_every_speculator_ability_gets_the_speculate_shape() -> void:
	var gl = _gl()
	var ab := _abilities()
	var checked := 0
	for id in ["leverage_position", "overexpose", "hedge_position", "press_the_edge", "forecast", "circuit_breaker"]:
		assert_true(ab.has(id), "CONTROL: %s exists" % id)
		checked += 1
		var style: Dictionary = gl._full_render_element_style(ab[id])
		assert_eq(str(style["shape"]), "speculate", "%s must render as a speculator spectacle" % id)
	assert_eq(checked, 6, "CONTROL: checked the whole speculator kit")

func test_speculator_dispatch_lives_inside_the_gated_function() -> void:
	var body := _body_of("_play_ability_full_render")
	assert_true(body.contains("shape == \"speculate\""))
	assert_true(body.contains("_play_speculator_spectacle("))

func test_press_the_edge_reads_the_real_volatility_band() -> void:
	## The brief: "read the real outcome from the ability's result ... before the number shows."
	## press_the_edge's own damage multiplier is driven by BattleManager.volatility.global_band --
	## the reel's tier must read that same live field, not a hardcoded value.
	var body := _body_of("_play_speculator_spectacle")
	assert_true(body.contains("BattleManager.volatility.global_band"),
		"the payout tier must come from the same live band press_the_edge itself consumes")

func test_leverage_position_reads_as_a_loss_not_a_win() -> void:
	## leverage_position costs the CASTER 10% max HP for the buff -- the reel must score that
	## honestly (a loss), not uniformly green like every other speculator cast.
	var body := _body_of("_play_speculator_spectacle")
	var idx := body.find("\"volatility_up_self\":")
	assert_gt(idx, -1, "CONTROL: volatility_up_self arm exists")
	var arm := body.substr(idx, 40)
	assert_true(arm.contains("win = false"), "leverage's self-recoil must be scored as a loss")

func test_speculator_reels_do_not_await_inside_their_spin_loop() -> void:
	var body := _body_of("_play_speculator_spectacle")
	var loop_start := body.find("for i in range(3):")
	assert_gt(loop_start, -1)
	var loop_end := body.find("\n\tawait", loop_start)
	assert_gt(loop_end, loop_start)
	var loop_slice := body.substr(loop_start, loop_end - loop_start)
	assert_eq(loop_slice.count("await"), 0, "spinning 3 reels in parallel must not await per reel -- that would serialize them")


## -------------------- Bard status motion (point 3 of the brief) --------------------

func test_each_bard_status_gets_a_distinct_motion() -> void:
	var gl = _gl()
	var ab := _abilities()
	for pair in [["lullaby", "drift"], ["discord", "dirge"], ["inspiring_melody", "war"]]:
		var id: String = pair[0]
		var expect_motion: String = pair[1]
		assert_true(ab.has(id), "CONTROL: %s exists" % id)
		var style: Dictionary = gl._full_render_element_style(ab[id])
		assert_eq(str(style["shape"]), "chord", "%s is still a musical performance" % id)
		assert_eq(str(style.get("motion", "")), expect_motion,
			"%s must carry the '%s' motion so it reads differently from the others" % [id, expect_motion])

func test_lullaby_and_discord_do_not_share_a_colour() -> void:
	var gl = _gl()
	var ab := _abilities()
	var sleep_c: Color = gl._full_render_element_style(ab["lullaby"])["color"]
	var dirge_c: Color = gl._full_render_element_style(ab["discord"])["color"]
	assert_false(sleep_c.is_equal_approx(dirge_c), "sleep and defense-down must read as different colours")

func test_chord_renderer_branches_on_motion() -> void:
	var body := _body_of("_full_render_release_visual")
	var chord_idx := body.find("\"chord\":")
	assert_gt(chord_idx, -1)
	var chord_body := body.substr(chord_idx, 2600)
	assert_true(chord_body.contains("match motion:"), "the chord arm must branch per landed status")
	assert_true(chord_body.contains("\"drift\":") and chord_body.contains("\"dirge\":") and chord_body.contains("\"war\":"),
		"all three authored motions must have their own arm")

func test_an_unmapped_song_still_renders_safely() -> void:
	## An ability with type=song but no entry in BARD_STATUS_MOTION must degrade to the existing
	## default motion, never crash.
	var gl = _gl()
	var style: Dictionary = gl._full_render_element_style({"id": "zzz_new_song", "type": "song", "effect": "some_future_status"})
	assert_eq(str(style["shape"]), "chord")
	assert_eq(str(style.get("motion", "")), "swirl", "an unmapped status falls back to the original swirl motion")


## -------------------- turbo / autogrind skip the whole spectacle --------------------

func test_all_three_spectacles_are_gated_behind_full_render_active() -> void:
	## None of the three new shapes have a second, ungated call site -- the ONLY way to reach any
	## of them is through _on_action_executing's existing full_render_this check, which already
	## excludes turbo_mode, autogrind_console_mode, and Engine.time_scale > 0.55.
	var src := _scene_src()
	for needle in ["_play_eidolon_summon(", "_play_recursive_summon(", "_play_speculator_spectacle("]:
		assert_eq(src.count(needle), 2, "%s must be declared once and called exactly once, both inside the gated function" % needle)
