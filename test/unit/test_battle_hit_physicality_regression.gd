extends GutTest

## Crit thud + combo pitch ramp (cowir-main slate items 2-3).
##
## Two properties carry the whole feature:
##   1. the ramp bias is EXACTLY 1.0 at rest, so an unchained hit is bit-identical to the
##      pre-ramp path — that is what "OFF reproduces current behavior" means here
##   2. the thud plays on a DIFFERENT player than the hit, so it layers under it. Same
##      player would replace the hit cue and the crit would get quieter, not heavier.

const SCENE_SRC: String = "res://src/battle/BattleScene.gd"
const SM_SRC: String = "res://src/audio/SoundManager.gd"


func before_each() -> void:
	SoundManager.reset_hit_chain()


func after_each() -> void:
	SoundManager.reset_hit_chain()


func test_the_ramp_is_INERT_at_rest() -> void:
	## The byte-for-byte claim. If this drifts off 1.0, every non-chained hit in the game
	## changes pitch and no other test here would notice.
	assert_eq(SoundManager.get_combo_pitch_bias(), 1.0,
		"a reset chain must yield EXACTLY 1.0 — anything else re-pitches every ordinary hit")


func test_the_ramp_rises_per_consecutive_hit_and_CAPS() -> void:
	## The cooldown is cleared between hits so each one is genuinely HEARD. This loop used to
	## fire 12 same-frame calls: since af8434fe0 the ramp counts audible plays, not calls, so
	## an uncleared loop measures one step and twelve suppressions — it tested the defect.
	var seen: Array[float] = []
	for i in range(12):
		seen.append(SoundManager.get_combo_pitch_bias())
		SoundManager._sfx_cooldowns.clear()
		SoundManager.play_attack_hit("", false)
	assert_eq(seen[0], 1.0, "first hit of a chain must be unbiased")
	assert_gt(seen[1], seen[0], "the second hit must ramp above the first")
	assert_gt(seen[3], seen[2], "the ramp must still be rising mid-chain")
	var top: float = SoundManager.get_combo_pitch_bias()
	assert_almost_eq(top, 1.0 + SoundManager.COMBO_PITCH_CAP, 0.001,
		"the ramp must CAP at +%0.0f%%; measured %0.4f — an uncapped ramp turns a long chain into a chipmunk" % [SoundManager.COMBO_PITCH_CAP * 100.0, top])


func test_the_step_and_cap_match_the_specified_envelope() -> void:
	## Pins VALUES against cowir-main's brief (+2-4% per step, cap ~+12%), not just presence.
	assert_between(SoundManager.COMBO_PITCH_STEP, 0.02, 0.04,
		"step %0.3f is outside the specified +2-4%% per consecutive hit" % SoundManager.COMBO_PITCH_STEP)
	assert_almost_eq(SoundManager.COMBO_PITCH_CAP, 0.12, 0.02,
		"cap %0.3f is not the specified ~+12%%" % SoundManager.COMBO_PITCH_CAP)
	assert_gt(SoundManager.COMBO_PITCH_CAP, SoundManager.COMBO_PITCH_STEP,
		"a cap at or below one step makes the ramp a constant")


func test_reset_returns_the_chain_to_inert() -> void:
	## Cooldown cleared per hit for the same reason as the ramp arm above: since af8434fe0 a
	## same-frame repeat is suppressed and does not advance the chain, so this control needs
	## hits that are actually HEARD before it can assert the chain ramped.
	for i in range(5):
		SoundManager._sfx_cooldowns.clear()
		SoundManager.play_attack_hit("", false)
	assert_gt(SoundManager.get_combo_pitch_bias(), 1.0, "control: the chain must actually have ramped")
	SoundManager.reset_hit_chain()
	assert_eq(SoundManager.get_combo_pitch_bias(), 1.0, "reset_hit_chain() must return the bias to exactly 1.0")


func test_the_ramp_is_a_BIAS_so_the_existing_jitter_survives() -> void:
	## The variation is applied as `pitch_scale * <a draw across the authored band>`. If someone
	## reworks the ramp into an assignment rather than a multiply, the jitter silently dies
	## and hits become mechanically uniform — audible, and invisible to a value test.
	## ⛔ THE BAND IS READ FROM THE CONSTANT, NOT MATCHED AS A LITERAL. This arm pinned the exact
	## text `randf_range(0.95, 1.05)` and went red on 2026-09-18 when that band was named
	## SFX_PITCH_JITTER so play_voice could opt out of it — the jitter was intact, composing
	## exactly as this arm defends, and the only thing that moved was the spelling. A literal in
	## an assertion where the relationship is the subject reds on a correct change.
	var src: String = FileAccess.get_file_as_string(SM_SRC)
	assert_gt(src.length(), 1000, "SCOPE control: SoundManager.gd read back empty")
	var band: float = float(SoundManager.get_script().get_script_constant_map().get("SFX_PITCH_JITTER", 0.0))
	assert_gt(band, 0.0,
		"the jitter band is gone or zero — the ramp was meant to ride on top of it, not replace it")
	assert_true(src.contains("pitch_scale * pitch_variation"),
		"final pitch is no longer the PRODUCT of the passed scale and the jitter, so the ramp is not composing with it")
	## And the same claim behaviourally, which no rename can move: divide the pitch the player was
	## actually set to by the bias that hit carried, and the quotient must land inside the authored
	## band. An assignment in place of the multiply leaves it at 1/bias, outside it.
	## ⛔ THE BIAS IS READ BEFORE THE MEASURED HIT, not after. _advance_hit_chain runs at the END of
	## play_attack_hit, so reading it afterwards is one step too high — and one step (0.03) is
	## smaller than the band (0.05), which makes the error a FLAKE rather than a failure.
	SoundManager.reset_hit_chain()
	for i in range(4):
		SoundManager._sfx_cooldowns.clear()
		SoundManager.play_attack_hit("", false)
	var bias: float = SoundManager.get_combo_pitch_bias()
	assert_gt(bias, 1.0, "control: the chain must actually have ramped, or the product is unobservable")
	SoundManager._sfx_cooldowns.clear()
	SoundManager.play_attack_hit("", false)
	var drawn: float = SoundManager._battle_player.pitch_scale / bias
	assert_between(drawn, 1.0 - band, 1.0 + band,
		"the hit sounded at %.4f against a bias of %.4f — the jitter is not riding on the ramp" % [
			SoundManager._battle_player.pitch_scale, bias])
	SoundManager.reset_hit_chain()


func test_the_chain_is_reset_at_the_action_boundary() -> void:
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	assert_true(src.contains("SoundManager.reset_hit_chain()"),
		"nothing resets the chain — the ramp would accumulate across a whole battle and cap permanently")


func test_the_thud_uses_a_SEPARATE_player_so_it_LAYERS() -> void:
	## THE LOAD-BEARING GUARD for item 2. Same player = replacement, not layering.
	var battle: AudioStreamPlayer = SoundManager._battle_player
	var sub: AudioStreamPlayer = SoundManager._sub_player
	assert_not_null(sub, "_sub_player was never created — play_crit_thud() would no-op")
	assert_not_null(battle, "control: _battle_player must exist")
	assert_ne(sub.get_instance_id(), battle.get_instance_id(),
		"the crit thud shares _battle_player, so it REPLACES the hit cue instead of layering under it")
	assert_eq(sub.bus, battle.bus,
		"the sub layer must sit on the same bus as the hit, else volume/mute settings diverge")


func test_the_thud_is_LOW_and_trimmed_UNDER_the_hit() -> void:
	assert_lt(SoundManager.CRIT_THUD_FREQ, 120.0,
		"a 'sub' layer at %0.0f Hz is not sub-bass — it would compete with the hit rather than sit under it" % SoundManager.CRIT_THUD_FREQ)
	assert_lt(SoundManager.CRIT_THUD_TRIM_DB, 0.0,
		"the sub layer must be trimmed BELOW the hit, or it doubles the transient cowir-main asked not to double")
	assert_lt(SoundManager.CRIT_THUD_DURATION, 0.4,
		"a long thud smears into the next action instead of punctuating this one")


func test_the_thud_only_fires_on_CRITS_at_FULL_behind_its_flag() -> void:
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	var at: int = src.find("play_crit_thud")
	assert_gt(at, 0, "the crit thud is never called from BattleScene")
	var window: String = src.substr(maxi(0, at - 300), 300)
	assert_true(window.contains("is_crit"), "the thud is not gated on is_crit — it would fire on every ordinary hit")
	assert_true(window.contains("Tier.FULL"), "the thud is not gated on Tier.FULL")
	assert_true(window.contains("audio_crit_thud"), "the thud is not behind its feature flag")


func test_the_thud_type_is_one_the_generator_actually_HANDLES() -> void:
	## An unhandled type would fall through the generator's match and emit nothing — shipped,
	## reachable, and silent, which no listening test would catch in a muted headless run.
	var src: String = FileAccess.get_file_as_string(SM_SRC)
	var arms: PackedStringArray = src.split("\n")
	var handled: bool = false
	for line in arms:
		if line.strip_edges() == "\"thud\":":
			handled = true
			break
	assert_true(handled,
		"play_crit_thud() requests type 'thud' but the procedural generator has no such match arm — it would emit silence")
