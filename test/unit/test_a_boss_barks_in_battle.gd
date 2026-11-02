extends GutTest

## Voiced mid-battle barks (cowir-main 21086: "should the rat talk with voice midbattle?" — yes). Short lines per boss and
## trigger from data/boss_barks.json, each recorded; a per-battle cooldown keeps them flavour, not spam.

const SCENE := "res://src/battle/BattleScene.tscn"

var _guard: RefCounted = null
var _saved_scale: float = 1.0
var _saved_wedged: bool = false


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_wedged = SoundManager._audio_mixer_wedged
	SoundManager._audio_mixer_wedged = false
	SoundManager.stop_voiced_line()
	SoundManager.stop_voice()


func after_each() -> void:
	SoundManager.stop_voiced_line()
	Engine.time_scale = _saved_scale
	SoundManager._audio_mixer_wedged = _saved_wedged
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func test_every_bark_has_a_short_recording() -> void:
	var bosses: Dictionary = BossBarks.data().get("bosses", {})
	assert_true(bosses.has("cave_rat_king"), "PREMISE: the Rat King barks first (cowir-main 21086)")
	var bad: Array = []
	var n := 0
	for mid in bosses:
		var speaker := BossBarks.speaker_for(mid)
		for trig in BossBarks.TRIGGERS:
			var lines := BossBarks.lines_for(mid, trig)
			if lines.size() < 3:
				bad.append("%s.%s has %d lines, wants 3 variants" % [mid, trig, lines.size()])
			for l in lines:
				n += 1
				var key := SoundManager.voiced_line_clip(speaker, str(l))
				var s = load(str(SoundManager._sfx_manifest[key]["file"])) if key != "" else null
				if s == null:
					bad.append("%s %s: no recording for %s" % [mid, trig, l])
				elif s.get_length() > 1.75:
					bad.append("%s runs %.2fs; a bark is short" % [key, s.get_length()])
	assert_gt(n, 11, "PREMISE: at least the Rat King's 12 barks must be authored, found %d" % n)
	assert_eq(bad, [], "barks that cannot play as barks: %s" % [bad])


func test_the_cooldown_holds_and_then_lets_the_next_one_through() -> void:
	var b := BossBarks.new()
	var first := b.pick("cave_rat_king", "big_hit", 10000)
	assert_ne(first, "", "CONTROL: a fresh battle barks")
	assert_eq(b.pick("cave_rat_king", "windup", 10000 + BossBarks.cooldown_ms() - 1), "", "a second bark inside the cooldown is spam")
	assert_ne(b.pick("cave_rat_king", "windup", 10000 + BossBarks.cooldown_ms()), "", "after the cooldown the next one plays")


func test_a_bark_never_repeats_itself_back_to_back() -> void:
	var b := BossBarks.new()
	var t := 0
	var last := ""
	for _i in range(12):
		var line := b.pick("cave_rat_king", "big_hit", t)
		assert_ne(line, last, "the same bark twice in a row reads as a stuck record")
		last = line
		t += BossBarks.cooldown_ms()


func test_low_hp_barks_once_a_battle() -> void:
	var b := BossBarks.new()
	assert_ne(b.pick("cave_rat_king", "low_hp", 0), "", "CONTROL: the first low-HP bark plays")
	assert_eq(b.pick("cave_rat_king", "low_hp", BossBarks.cooldown_ms() * 3), "", "low HP is one moment, not a loop")


func test_barks_play_at_4x_but_respect_turbo_and_whatever_is_already_speaking() -> void:
	assert_true(BossBarks.allowed(1.0, false, false), "CONTROL: an ordinary moment allows a bark")
	assert_true(BossBarks.allowed(4.0, false, false), "he plays at 4x; the barks must be heard there (cowir-main 21194)")
	assert_false(BossBarks.allowed(1.0, true, false), "turbo is silent")
	assert_false(BossBarks.allowed(1.0, false, true), "never over a scripted line or a speech bubble")


func _boss() -> Combatant:
	var boss := Combatant.new()
	boss.combatant_name = "Cave Rat King"
	boss.max_hp = 100
	boss.current_hp = 100
	boss.is_alive = true
	boss.set_meta("is_boss", true)
	boss.set_meta("monster_type", "cave_rat_king")
	autofree(boss)
	return boss


func test_the_battle_scene_voices_a_bark_and_honours_the_cooldown() -> void:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	Engine.time_scale = 1.0
	var boss := _boss()
	scene._boss_bark(boss, "big_hit")
	assert_true(SoundManager.is_voiced_line_playing(), "a boss's bark must actually speak in a real battle scene")
	SoundManager.stop_voiced_line()
	scene._boss_bark(boss, "big_hit")
	assert_false(SoundManager.is_voiced_line_playing(), "the scene's own cooldown must hold the next one")


func test_the_battle_scene_barks_at_4x_and_not_in_the_grind() -> void:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	Engine.time_scale = 4.0
	scene.autogrind_console_mode = true
	scene._boss_bark(_boss(), "big_hit")
	assert_false(SoundManager.is_voiced_line_playing(), "the autogrind console stays silent")
	scene.autogrind_console_mode = false
	scene._boss_bark(_boss(), "big_hit")
	assert_true(SoundManager.is_voiced_line_playing(), "at 4x the boss still barks (cowir-main 21194)")


## cowir-ai 21120: on a wipe the boss's last words take the line player, so the wipe bark must yield to them.
func test_a_wipe_bark_yields_to_the_bosss_last_words() -> void:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	Engine.time_scale = 1.0
	var boss := _boss()
	scene.test_enemies.clear()
	scene.test_enemies.append(boss)
	scene._gloat_line = {}
	BattleManager.boss_gloat_pending = false
	scene._wipe_bark()
	assert_true(SoundManager.is_voiced_line_playing(), "CONTROL: a wipe with no last words to come barks")
	SoundManager.stop_voiced_line()
	scene._boss_barks = BossBarks.new()
	scene._gloat_line = {"text": "Petition denied.", "is_victory": false}
	scene._wipe_bark()
	assert_false(SoundManager.is_voiced_line_playing(), "with last words pending, a wipe bark would be cut or make the boss speak twice")
	scene._gloat_line = {}
