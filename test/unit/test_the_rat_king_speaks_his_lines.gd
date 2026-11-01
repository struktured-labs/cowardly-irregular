extends GutTest

## The Cave Rat King's authored lines are recorded (struktured 2026-10-31: "i want a text2voice for the rat. badly").
## A recording is found by (speaker, on-screen text), so these arms derive the lines the way each panel shows them.

const SPEAKER := "Cave Rat King"
const UNVOICED := "This line was never recorded by anyone."

var _saved_wedged: bool = false


func before_each() -> void:
	_saved_wedged = SoundManager._audio_mixer_wedged
	SoundManager._audio_mixer_wedged = false
	SoundManager.stop_voiced_line()
	SoundManager.stop_voice()


func after_each() -> void:
	SoundManager.stop_voiced_line()
	SoundManager.stop_voice()
	SoundManager._audio_mixer_wedged = _saved_wedged


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cutscene_lines(node: Variant, out: Array) -> void:
	if node is Dictionary:
		if str(node.get("speaker", "")) == SPEAKER:
			out.append(str(node.get("text", "")))
		for v in node.values():
			_cutscene_lines(v, out)
	elif node is Array:
		for v in node:
			_cutscene_lines(v, out)


## Every Rat King line a panel can show, as the panel shows it.
func _authored_lines() -> Array:
	var out: Array = []
	var mon: Dictionary = _json("res://data/monsters.json")["cave_rat_king"]["dialogue"]
	for part in ["intro", "low_hp", "defeat"]:
		for l in mon.get(part, []):
			if str(l).begins_with(SPEAKER + ":"):
				out.append(str(l).split(":", true, 1)[1].strip_edges())
	for f in ["world1_rat_king_intro", "world1_rat_king_defeat"]:
		_cutscene_lines(_json("res://data/cutscenes/%s.json" % f), out)
	var bd: Dictionary = _json("res://data/boss_dialogue.json")["cave_rat_king"]
	for pool in ["opening_lines", "victory_lines", "defeat_lines"]:
		for l in bd.get(pool, []):
			if str(l).begins_with(SPEAKER + ":"):
				out.append(DialoguePrompts.spoken_line(str(l)))
	for it in bd.get("scripted_intents", []):
		for l in it.get("taunt_lines", []):
			out.append(DialoguePrompts.spoken_line(str(l)))
	return out


func _a_line() -> String:
	return str(_authored_lines()[0])


func test_every_authored_line_has_a_recording_on_disk() -> void:
	var lines := _authored_lines()
	assert_gt(lines.size(), 30, "PREMISE: the derivation must find the Rat King's ~37 lines, found %d" % lines.size())
	var missing: Array = []
	for l in lines:
		var key := SoundManager.voiced_line_clip(SPEAKER, l)
		if key == "" or not FileAccess.file_exists(str(SoundManager._sfx_manifest[key]["file"])):
			missing.append(l)
	assert_eq(missing, [], "a Rat King line was edited or added without a recording; re-render it (cowir-sfx): %s" % [missing])


func test_every_recording_belongs_to_a_line_that_still_exists() -> void:
	var wanted: Dictionary = {}
	for l in _authored_lines():
		wanted[SoundManager.voiced_line_key(SPEAKER, l)] = true
	var orphans: Array = []
	var seen := 0
	for key in SoundManager._sfx_manifest:
		var e = SoundManager._sfx_manifest[key]
		if e is Dictionary and str(e.get("speaker", "")) == SPEAKER and e.has("line"):
			seen += 1
			if not wanted.has(SoundManager.voiced_line_key(SPEAKER, str(e["line"]))):
				orphans.append(key)
	assert_gt(seen, 30, "PREMISE: the manifest must carry the Rat King's recordings, found %d" % seen)
	assert_eq(orphans, [], "these recordings speak a line no panel shows any more: %s" % [orphans])


func test_a_recorded_line_plays_on_its_own_player_and_says_how_long() -> void:
	var sec := SoundManager.play_voiced_line(SPEAKER, _a_line(), self)
	assert_gt(sec, 0.5, "a recorded line must report its length")
	assert_true(SoundManager.is_voiced_line_playing(), "and must be playing")
	assert_ne(SoundManager._line_player, SoundManager._voice_player, "a dialogue line must never share the party voice player the victory slam uses")
	assert_false(SoundManager._voice_player.playing, "the party voice player must stay free")


func test_a_recorded_line_ducks_the_music_and_hands_it_back() -> void:
	SoundManager.duck_music_for_dialogue(false)
	assert_false(SoundManager.is_music_ducked_for_dialogue(), "PREMISE: nothing ducks the music before the line")
	SoundManager.play_voiced_line(SPEAKER, _a_line(), self)
	assert_true(SoundManager.is_music_ducked_for_dialogue(), "a boss speaking over full-level music is the line nobody hears")
	SoundManager.stop_voiced_line(self)
	assert_false(SoundManager.is_music_ducked_for_dialogue(), "a stopped line must hand the music back")


func test_an_unrecorded_line_plays_nothing_and_ducks_nothing() -> void:
	SoundManager.duck_music_for_dialogue(false)
	assert_eq(SoundManager.play_voiced_line(SPEAKER, UNVOICED, self), 0.0, "a line with no recording returns 0, so the blips carry it")
	assert_false(SoundManager.is_voiced_line_playing(), "and plays nothing")
	assert_false(SoundManager.is_music_ducked_for_dialogue(), "and ducks nothing")


func test_the_same_words_from_someone_else_are_not_the_rat_king() -> void:
	assert_eq(SoundManager.voiced_line_clip("Theron", _a_line()), "", "NPCDialogue shares the panel; the key is (speaker, text), not text alone")


func test_only_the_panel_that_started_a_line_can_stop_it() -> void:
	var other := Node.new()
	add_child_autofree(other)
	SoundManager.play_voiced_line(SPEAKER, _a_line(), self)
	SoundManager.stop_voiced_line(other)
	assert_true(SoundManager.is_voiced_line_playing(), "one panel closing must not silence another panel's line")
	SoundManager.stop_voiced_line(self)
	assert_false(SoundManager.is_voiced_line_playing(), "its own panel stops it")


func test_the_battle_panel_voices_the_last_words_and_stops_on_close() -> void:
	var box := BattleDialogue.new()
	add_child_autofree(box)
	box.show_boss_last_words(SPEAKER, _a_line(), "cave_rat_king")
	assert_gt(box.line_voice_seconds(), 0.0, "the boss's last words must speak, and say for how long so the hold can wait")
	assert_true(SoundManager.is_voiced_line_playing(), "the recording must be playing")
	box.dismiss()
	assert_false(SoundManager.is_voiced_line_playing(), "closing the panel must stop the voice")


func test_the_battle_panel_stops_a_line_when_the_next_one_shows() -> void:
	var box := BattleDialogue.new()
	add_child_autofree(box)
	box.show_dialogue([{"speaker": SPEAKER, "text": _a_line()}, {"speaker": SPEAKER, "text": UNVOICED}])
	assert_true(SoundManager.is_voiced_line_playing(), "PREMISE: the first line speaks")
	box._advance_dialogue()
	box._advance_dialogue()
	assert_eq(box._current_index, 1, "PREMISE: the panel moved on to the second line")
	assert_false(SoundManager.is_voiced_line_playing(), "advancing must stop the voice; it never talks over the next line")
	assert_eq(box.line_voice_seconds(), 0.0, "and the unrecorded line goes back to blips")


func test_the_battle_panel_does_not_outlive_its_voice() -> void:
	var box := BattleDialogue.new()
	add_child(box)
	box.show_boss_last_words(SPEAKER, _a_line(), "cave_rat_king")
	assert_true(SoundManager.is_voiced_line_playing(), "PREMISE: the line speaks")
	box.free()
	assert_false(SoundManager.is_voiced_line_playing(), "a battle freed mid-line must not leave the boss talking")


func test_the_cutscene_panel_voices_a_line_and_a_skip_stops_it() -> void:
	var box := CutsceneDialogue.new()
	add_child_autofree(box)
	box.show_dialogue([{"speaker": SPEAKER, "text": _a_line(), "theme": "enemy"}])
	assert_gt(box._line_voice_sec, 0.0, "a cutscene line with a recording must speak")
	assert_true(SoundManager.is_voiced_line_playing(), "the recording must be playing")
	box.skip_all()
	assert_false(SoundManager.is_voiced_line_playing(), "skipping the cutscene must stop the voice")


## Blips that start while one line types; the helper keeps an abort from reaching the caller's asserts.
func _blips(text: String) -> int:
	var box := CutsceneDialogue.new()
	add_child_autofree(box)
	box.show_dialogue([{"speaker": SPEAKER, "text": text, "theme": "enemy", "portrait": "boss_rat_king"}])
	var n := 0
	for i in range(text.length()):
		box._voice_blip_player.stop()
		box._on_typing_tick()
		if box._voice_blip_player.playing:
			n += 1
	return n


func test_a_voiced_cutscene_line_plays_no_blips() -> void:
	assert_gt(_blips(UNVOICED), 0, "CONTROL: an unrecorded line must blip, or a zero below proves nothing")
	assert_eq(_blips(_a_line()), 0, "one source per line: a recorded line must not also blip")


func test_no_line_outlasts_the_boss_line_watchdog_grace() -> void:
	var grace_sec: float = float(load("res://src/battle/BattleScene.gd").get_script_constant_map().get("BOSS_LINE_GRACE_MS", 0)) / 1000.0
	assert_gt(grace_sec, 0.0, "PREMISE: BattleScene.BOSS_LINE_GRACE_MS must still exist")
	var longest := 0.0
	for l in _authored_lines():
		var key := SoundManager.voiced_line_clip(SPEAKER, l)
		var s = load(str(SoundManager._sfx_manifest[key]["file"])) if key != "" else null
		if s:
			longest = maxf(longest, s.get_length())
	assert_gt(longest, 0.0, "PREMISE: at least one recording must load")
	assert_lt(longest, grace_sec * 0.8, "a line longer than the menu watchdog's grace would hit the watchdog")
