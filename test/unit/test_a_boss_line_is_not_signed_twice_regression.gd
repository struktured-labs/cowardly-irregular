extends GutTest

## Regression 2026-09-29: boss_dialogue.json writes lines as "Pyrroth: 'Feel that?'" and the battle log and bubble also sign them,
## so players read `Pyrroth, the Ember Wyrm: "Pyrroth: 'Feel that?'"`. The data keeps its speaker (BattleDialogue reads it).

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const WRAPPED := "^[^:'\"]{1,40}: ['\"].*['\"]$"


## BattleScene with the two display sinks captured instead of drawn.
class ProbeScene extends "res://src/battle/BattleScene.gd":
	var bubbles: Array = []
	var logged: Array = []
	func _spawn_quip_bubble(_sprite: Node2D, _speaker_name: String, line: String, _border_color: Color = Color(1.0, 0.85, 0.2), _hold_time: float = 1.5, _audio_key: String = "") -> void:
		bubbles.append(line)
	func log_message(message: String) -> void:
		logged.append(message)
	func _gloat_speaker_name(_is_victory: bool) -> String:
		return "Pyrroth, the Ember Wyrm"


func _wrapped() -> RegEx:
	var re := RegEx.new()
	re.compile(WRAPPED)
	return re


func _boss_lines() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_dialogue.json"))
	assert_true(d is Dictionary, "CONTROL: boss_dialogue.json parses")
	var out: Array = []
	var stack: Array = [d]
	while not stack.is_empty():
		var v = stack.pop_back()
		if v is Dictionary:
			stack.append_array((v as Dictionary).values())
		elif v is Array:
			stack.append_array(v)
		elif v is String and _wrapped().search(v) != null:
			out.append(v)
	return out


func test_every_wrapped_boss_line_reads_as_just_its_words() -> void:
	var lines := _boss_lines()
	assert_gt(lines.size(), 100, "CONTROL: boss_dialogue.json should still carry its house-style wrapped lines (%d found)" % lines.size())
	var still: Array[String] = []
	for line in lines:
		var shown := DialoguePrompts.spoken_line(line)
		if _wrapped().search(shown) != null or shown.length() >= str(line).length():
			still.append(str(line).substr(0, 50))
	assert_eq(still, [] as Array[String], "these lines would still be signed twice: %s" % ", ".join(still.slice(0, 5)))


func test_control_an_ordinary_line_is_left_alone() -> void:
	for line in ["Note: the ward holds.", "Stand in the heat.", "", "A: b"]:
		assert_eq(DialoguePrompts.spoken_line(line), line.strip_edges(), "an unwrapped line was changed: %s" % line)


func test_the_battle_log_signs_a_taunt_once() -> void:
	var bm = BattleManagerScript.new()
	add_child_autofree(bm)
	var logged: Array = []
	bm.battle_log_message.connect(func(m): logged.append(str(m)))
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "Pyrroth, the Ember Wyrm"
	boss.max_hp = 100
	boss.current_hp = 100
	boss.set_meta("llm_persona_id", "pyrroth")
	bm._update_boss_dialogue_phase(boss)
	var taunts := logged.filter(func(m): return str(m).contains("Pyrroth, the Ember Wyrm: \""))
	assert_gt(taunts.size(), 0, "CONTROL: Pyrroth's first phase must log a taunt, or this checked nothing: %s" % [logged])
	for m in taunts:
		assert_false(str(m).contains(": \"Pyrroth: '"), "the log signs the taunt twice: %s" % m)


func test_the_bubble_and_the_gloat_sign_a_line_once() -> void:
	var scene = ProbeScene.new()
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "Pyrroth, the Ember Wyrm"
	var sprite := AnimatedSprite2D.new()
	autofree(sprite)
	scene.test_enemies.assign([boss])
	scene.enemy_sprite_nodes.assign([sprite])
	scene._on_boss_taunt(boss, "Pyrroth: 'Stand in the heat.'")
	scene._on_boss_gloat_line("Pyrroth: 'Well fought.'", true)
	assert_eq(scene.bubbles, ["Stand in the heat."], "the taunt bubble carries the authored speaker under the boss's own name")
	assert_eq(scene.logged.size(), 1, "CONTROL: the gloat must reach the log")
	if scene.logged.size() == 1:
		assert_false(str(scene.logged[0]).contains("\"Pyrroth: '"), "the gloat is signed twice: %s" % scene.logged[0])
	scene.free()
