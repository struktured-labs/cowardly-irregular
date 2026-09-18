extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## _play_sound defaults to the PLAYER'S level, which is right only where the computed level equals
## the player's resting base. Four callers computed something else — a trim, or the death boost —
## and passed it to the manifest call only, so the synth branch silently used the wrong level.
##
## The generic status blip is the reachable one: it is the DESIGNED fallback for an unauthored
## status, and 32 ability effects reach it. Measured 2026-09-18, pre-fix: after corruption_ap_flicker
## it played at -12.00 against a -6.00 channel, inheriting whatever the previous battle cue left.

const TRIMMED_CUE := "corruption_ap_flicker"   # -6.0 in _BATTLE_VOLUME_TRIM_DB
const UNAUTHORED := "zz_no_such_status_at_all"
const DEATH_CUE := "enemy_death"               # in SOUNDS and the manifest, so it can be forced to synth
const BROKEN := "assets/audio/sfx/zz_this_file_does_not_exist.ogg"

var _saved: Dictionary = {}
## cue -> its real manifest entry, for the arms that force the HIT cues to synth.
var _saved_hits: Dictionary = {}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _c(sm: Node, n: String) -> float:
	return float(sm.get_script().get_script_constant_map()[n])


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _c(sm, "SFX_BATTLE_BASE_DB")
	sm._death_player.volume_db = _c(sm, "DEATH_PLAYER_BASE_DB")


func after_each() -> void:
	## FIRST, not last: a GDScript error in the restores below aborts after_each, and a release that
	## sits at the bottom is then skipped. Self-contained, so it needs nothing above it.
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm == null:
		return
	if not _saved.is_empty():
		sm._sfx_manifest[DEATH_CUE] = _saved
		_saved = {}
	sm._sfx_stream_cache.erase(DEATH_CUE)
	for k in _saved_hits.keys():
		sm._sfx_manifest[k] = _saved_hits[k]
		sm._sfx_stream_cache.erase(k)
	_saved_hits = {}
	sm._sfx_cooldowns.clear()
	sm._battle_player.volume_db = _c(sm, "SFX_BATTLE_BASE_DB")
	sm._death_player.volume_db = _c(sm, "DEATH_PLAYER_BASE_DB")
	sm._battle_player.pitch_scale = 1.0
	sm._death_player.pitch_scale = 1.0


func test_the_blip_does_not_inherit_the_previous_cues_trim() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var base: float = _c(sm, "SFX_BATTLE_BASE_DB")
	sm.play_battle(TRIMMED_CUE)
	assert_ne(sm._battle_player.volume_db, base,
		"CONTROL: %s must move the level off the base, or this arm has no stale value to inherit" % TRIMMED_CUE)
	sm._sfx_cooldowns.clear()
	sm.play_status(UNAUTHORED)
	assert_eq(sm._battle_player.volume_db - base, 0.0,
		"the generic status blip sits %+.2f dB off the channel base — it inherited the previous cue's trim instead of carrying its own level" % [
			sm._battle_player.volume_db - base])


func test_the_death_cue_keeps_its_boost_on_the_synth_path() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	var boost: float = _c(sm, "DEATH_CUE_BOOST_DB")
	assert_ne(boost, 0.0, "CONTROL: the boost is zero, so this arm cannot tell the paths apart")
	_saved = (sm._sfx_manifest[DEATH_CUE] as Dictionary).duplicate(true)
	sm._sfx_manifest[DEATH_CUE] = {"file": BROKEN}
	sm._sfx_stream_cache.erase(DEATH_CUE)
	sm._sfx_cooldowns.clear()
	sm.play_death(DEATH_CUE)
	assert_eq(sm._death_player.volume_db - _c(sm, "DEATH_PLAYER_BASE_DB"), boost,
		"the death cue fell to the synth path and sits %+.2f dB off its base instead of its authored %+.2f boost — the boost exists because the cry was being masked" % [
			sm._death_player.volume_db - _c(sm, "DEATH_PLAYER_BASE_DB"), boost])


func test_a_trimmed_cue_still_gets_its_own_trim() -> void:
	## Anti-overcorrection: a fix that forced every synth cue to the bare base would pass both arms
	## above and discard every authored trim.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_battle(TRIMMED_CUE)
	assert_ne(sm._battle_player.volume_db - _c(sm, "SFX_BATTLE_BASE_DB"), 0.0,
		"%s lost its authored trim — every battle cue now plays at the bare base" % TRIMMED_CUE)


func test_the_synth_level_has_one_owner() -> void:
	## Four callers had to remember this and one already had. Pins that they go through the helper,
	## so the next caller cannot forget it the way these did.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	assert_ne(code, "", "CONTROL: SoundManager code must survive the comment strip")
	assert_true(code.contains("func _synth_params("),
		"the synth-level owner is gone — every caller is folding its own level in again")
	## ⛔ DERIVED, NOT A RECEIVER LIST. This counted three named receivers and its MESSAGE claimed the
	## population — so three more raw passes (_flourish_player, _pickup_player, _ability_player) sat
	## uncounted while the arm read as green about all of them. A predicate narrower than the sentence
	## it supports; the regex matches ANY receiver, so a new player is covered when it is written.
	var offenders: Array = []
	for m in RegEx.create_from_string("_play_sound\\(\\s*(\\w+)\\s*,\\s*SOUNDS\\[").search_all(code):
		offenders.append(m.get_string(1))
	assert_eq(offenders, [],
		"%d synth call(s) still pass the RAW SOUNDS entry, so they take the player's resting level rather than the one their caller computed: %s" % [offenders.size(), offenders])


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen.
	for m in ["play_battle", "play_status", "play_death", "_battle_level", "_synth_params"]:
		assert_true(sm.has_method(m), "SoundManager has no method %s — this file CALLS it" % m)
	for n in ["_battle_player", "_death_player", "_sfx_cooldowns", "_sfx_manifest", "_sfx_stream_cache"]:
		assert_true(sm.get(n) != null, "SoundManager has no %s — this file reaches for it directly" % n)
	for c in ["SFX_BATTLE_BASE_DB", "DEATH_PLAYER_BASE_DB", "DEATH_CUE_BOOST_DB", "_BATTLE_VOLUME_TRIM_DB"]:
		assert_true((sm.get_script().get_script_constant_map() as Dictionary).has(c),
			"%s is gone — this file's arms read it directly" % c)


## Points a hit cue's manifest entry at a file that is not there, forcing its procedural branch.
## Both cues resolve normally in a real build, so that branch is a FALLBACK and the defect it
## carried was latent — exactly like the three sibling callers fixed alongside it.
func _force_synth(sm: Node, cue: String) -> void:
	if not sm._sfx_manifest.has(cue):
		return
	_saved_hits[cue] = (sm._sfx_manifest[cue] as Dictionary).duplicate(true)
	sm._sfx_manifest[cue] = {"file": BROKEN}
	sm._sfx_stream_cache.erase(cue)
	sm._sfx_cooldowns.clear()


func test_the_procedural_crit_is_a_boost_on_the_channel_not_an_absolute() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has("critical_hit"),
		"CONTROL: critical_hit must be in the manifest, or _force_synth measures nothing")
	sm.reset_hit_chain()
	_force_synth(sm, "critical_hit")
	sm.play_attack_hit("", true)
	var expected: float = float(sm._battle_level("critical_hit")) + _c(sm, "CRIT_SYNTH_BOOST_DB")
	assert_eq(sm._battle_player.volume_db, expected,
		"the procedural crit played at %.2f, not %.2f — a bare `volume_db = 2.0` is an ABSOLUTE level, while its own manifest sibling plays at _battle_level" % [sm._battle_player.volume_db, expected])


func test_a_plain_hit_after_a_procedural_crit_does_not_inherit_its_boost() -> void:
	## The other half: the non-crit branch carried no level at all, so it took whatever the player was
	## left at, and a procedural crit immediately before it is the reachable way to leave that non-base.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.reset_hit_chain()
	_force_synth(sm, "critical_hit")
	_force_synth(sm, "attack_hit")
	sm.play_attack_hit("", true)
	assert_gt(sm._battle_player.volume_db, float(sm._battle_level("attack_hit")),
		"CONTROL: the crit must leave the player ABOVE the plain level, or this arm measures nothing")
	sm._sfx_cooldowns.clear()
	sm.reset_hit_chain()
	sm.play_attack_hit("", false)
	assert_eq(sm._battle_player.volume_db, float(sm._battle_level("attack_hit")),
		"a plain hit after a procedural crit played at %.2f, inheriting the crit's boost instead of its own channel level" % sm._battle_player.volume_db)
