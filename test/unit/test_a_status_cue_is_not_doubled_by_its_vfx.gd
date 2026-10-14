extends GutTest

## An authored status cue played WITH a generic polarity sting on top (2026-10-14).
##
## Two audio paths serve one ability and neither knows about the other:
##   BattleScene._on_action_executed  matches ability.effect   -> play_status("sleep") -> status_sleep
##   EffectSystem._play_effect_sound  matches the VFX enum     -> play_battle_scaled("debuff")
## `SFX_MIN_INTERVAL_MS` is PER KEY, so two DIFFERENT keys both land and the player hears both.
##
## Evidence, struktured's 10-13 session on v3.33.684-alpha, three times:
##     569 Clockwork Sentinel gained status: sleep (3 turns)
##     570 [SFX] status_sleep -> status_sleep      <- authored, correct
##     571 [SFX] debuff -> debuff_v2               <- generic sting layered on it
##
## Five abilities qualify (effect has an authored status_* cue, is in no explicit BattleScene arm,
## and the VFX layer calls it BUFF/DEBUFF): infinite_loop · lullaby · peace_sign · puppy_eyes ·
## smoke_bomb. Battle Hymn does NOT, and that is the proof of the mechanism — `attack_up` makes both
## layers pick `buff`, one key, so the cooldown already collapses it.
##
## ⛔ NOT a deletion of those two arms, which was the obvious fix and is wrong: `BattleScene:6702`
## spawns a BUFF effect for a monster's "X appears!" flash and `:2704` for the group-attack impact.
## Neither is an ability action and neither has a status cue before it, so deleting the sound would
## silence them. Arm 3 is that case and it must stay GREEN.

const WINDOW_MS: int = 120
var _sm = null
var _es = null


func before_each() -> void:
	_sm = SoundManager
	_es = EffectSystem
	if _sm != null:
		_sm._sfx_cooldowns.clear()


func after_each() -> void:
	if _sm != null:
		_sm._sfx_cooldowns.clear()


func test_the_members_this_file_drives_exist() -> void:
	assert_not_null(_sm, "SoundManager autoload missing")
	assert_not_null(_es, "EffectSystem autoload missing")
	assert_true(_sm.has_method("status_cue_just_played"), "the seam this guard asserts is gone")
	assert_true(_es.has_method("_play_effect_sound"), "EffectSystem._play_effect_sound is gone")
	assert_true("_sfx_cooldowns" in _sm, "the serve-stamp seam is gone")
	for k in ["debuff", "buff", "status_sleep"]:
		assert_true(_sm._sfx_manifest.has(k), "%s must be authored for this guard to mean anything" % k)


## The seam itself: a status_* serve is visible, anything else is not.
func test_the_seam_sees_only_a_status_cue() -> void:
	_sm._sfx_cooldowns.clear()
	assert_false(_sm.status_cue_just_played(WINDOW_MS), "nothing played — the seam must be false")
	_sm.play_battle("debuff")
	assert_false(_sm.status_cue_just_played(WINDOW_MS), "a generic cue is not a status cue")
	_sm._sfx_cooldowns.clear()
	_sm.play_status("sleep")
	assert_true(_sm.status_cue_just_played(WINDOW_MS), "status_sleep was served and the seam did not see it")


## THE DEFECT: after an authored status cue, the generic sting must stand off.
func test_the_generic_sting_stands_off_an_authored_status_cue() -> void:
	_sm._sfx_cooldowns.clear()
	_sm.play_status("sleep")
	assert_true(_sm._sfx_cooldowns.has("status_sleep"), "CONTROL: the authored cue must have been served")
	_es._play_effect_sound(_es.EffectType.DEBUFF, 1.0, "")
	assert_false(_sm._sfx_cooldowns.has("debuff"),
		"the generic debuff sting played on top of status_sleep — different keys, so the per-key cooldown cannot collapse them and the player hears both")


## CONTROL, and it is the reason this is a guard and not a deletion: with NO status cue before it the
## sting is the ONLY audio for that event (monster spawn flash, group-attack impact) and must still play.
func test_the_sting_still_plays_when_it_is_the_only_cue() -> void:
	for t in [[_es.EffectType.DEBUFF, "debuff"], [_es.EffectType.BUFF, "buff"]]:
		_sm._sfx_cooldowns.clear()
		_es._play_effect_sound(t[0], 1.0, "")
		assert_true(_sm._sfx_cooldowns.has(str(t[1])),
			"%s was suppressed with no status cue before it — a monster spawn flash would go silent" % str(t[1]))


## The non-polarity arms are untouched: a specific cue is never a duplicate of anything.
func test_a_specific_arm_is_not_gated_by_the_seam() -> void:
	_sm._sfx_cooldowns.clear()
	_sm.play_status("sleep")
	_es._play_effect_sound(_es.EffectType.FIRE, 1.0, "")
	assert_true(_sm._sfx_cooldowns.has("strike_fire"),
		"strike_fire was gated — only the generic buff/debuff stings may stand off")
