extends GutTest

## A boss with a recorded voice speaks every panel line in it; an unrecorded new line plays as blips between voiced ones.
## On 2026-11-24 the Cartographer's new low_hp line landed unrecorded and nothing went red; this names such a line.

const MONSTERS := "res://data/monsters.json"
const BOSS_DIALOGUE := "res://data/boss_dialogue.json"
## The boss_dialogue pools that reach the battle panel as last words (BattleManager's scripted fallback).
const PANEL_POOLS := ["victory_lines", "defeat_lines", "victory_lines_stolen_key"]


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _voiced_speakers() -> Array:
	SoundManager.voiced_line_clip("", "")
	var out: Array = []
	for key in SoundManager._sfx_manifest:
		var e = SoundManager._sfx_manifest[key]
		if str(key).begins_with("boss_line_") and e is Dictionary and e.has("line"):
			var s := str(e.get("speaker", ""))
			if s != "" and not out.has(s):
				out.append(s)
	return out


func _has_voice(speaker: String, voices: Array) -> bool:
	for v in voices:
		if SoundManager.speaks_as(str(v), speaker):
			return true
	return false


## [speaker, text, where] for every line a panel would speak in a voiced boss's name.
func _panel_lines(voices: Array) -> Array:
	var out: Array = []
	var mon: Dictionary = _json(MONSTERS)
	if mon.has("monsters") and mon["monsters"] is Dictionary:
		mon = mon["monsters"]
	for mid in mon:
		var m = mon[mid]
		if not (m is Dictionary) or not (m.get("dialogue") is Dictionary):
			continue
		for trig in m["dialogue"]:
			var lines = m["dialogue"][trig]
			if not (lines is Array):
				continue
			for line in lines:
				var s := str(line)
				if (s.begins_with("*") and s.ends_with("*")) or not (":" in s):
					continue
				var parts := s.split(":", true, 1)
				var spk := parts[0].strip_edges()
				if _has_voice(spk, voices):
					out.append([spk, parts[1].strip_edges(), "monsters.json %s.dialogue.%s" % [mid, trig]])
	var bd: Dictionary = _json(BOSS_DIALOGUE)
	if bd.has("bosses") and bd["bosses"] is Dictionary:
		bd = bd["bosses"]
	for bid in bd:
		var b = bd[bid]
		if not (b is Dictionary):
			continue
		for pool in PANEL_POOLS:
			if not (b.get(pool) is Array):
				continue
			for line in b[pool]:
				var s := str(line).strip_edges()
				var colon := s.find(": ")
				if colon <= 0 or colon > 40 or (s.begins_with("*") and s.ends_with("*")):
					continue
				var spk := s.substr(0, colon).strip_edges()
				if _has_voice(spk, voices):
					out.append([spk, DialoguePrompts.spoken_line(s), "boss_dialogue.json %s.%s" % [bid, pool]])
	return out


func test_every_panel_line_of_a_voiced_boss_has_a_recording() -> void:
	var voices := _voiced_speakers()
	assert_gt(voices.size(), 5, "CONTROL: several bosses have recorded voices")
	var lines := _panel_lines(voices)
	assert_gt(lines.size(), 60, "CONTROL: the voiced bosses' panel lines were read")
	var silent: Array = []
	for l in lines:
		if SoundManager.voiced_line_clip(l[0], l[1]) == "":
			silent.append("%s — %s: \"%s\"" % [l[2], l[0], l[1]])
	assert_eq(silent, [], "these lines would play as blips between voiced ones; record them (cowir-sfx) or make them stage directions: %s" % [silent])


func test_a_line_from_an_unvoiced_speaker_is_not_judged() -> void:
	var voices := _voiced_speakers()
	assert_false(_has_voice("Hero", voices), "CONTROL: the party's interjections are not a boss voice")
	assert_true(_has_voice("Pyrroth, the Ember Wyrm", voices), "a titled panel name reaches the recorded voice")
