extends Node
class_name NPCDialogue

## NPCDialogue — lightweight wrapper for in-world NPC conversations.
## Reuses CutsceneDialogue for rendering, but without the full CutsceneDirector
## orchestration (no letterboxing, no screen effects, no flag setting).
##
## Usage:
##   var npc_dlg = NPCDialogue.new()
##   add_child(npc_dlg)
##   await npc_dlg.say("Elder Theron", "The cave is to the northwest.", "elder", "elder")
##   await npc_dlg.say_lines([
##       {"speaker": "Theron", "text": "Be careful.", "theme": "elder", "portrait": "elder"},
##       {"speaker": "Fighter", "text": "Always.", "theme": "fighter", "portrait": "fighter"},
##   ])

signal conversation_finished()

var _dialogue: Node = null
var _active: bool = false


func say(speaker: String, text: String, theme: String = "narrator", portrait: String = "narrator") -> void:
	"""Show a single line of NPC dialogue and wait for player to advance."""
	await say_lines([{
		"speaker": speaker,
		"text": text,
		"theme": theme,
		"portrait": portrait,
	}])


func say_lines(lines: Array) -> void:
	"""Show multiple lines of dialogue and wait for player to advance through all."""
	if _active:
		return
	_active = true

	_ensure_dialogue()
	_dialogue.show_dialogue(lines)
	await _dialogue.dialogue_finished

	_active = false
	conversation_finished.emit()


func is_active() -> bool:
	return _active


func _ensure_dialogue() -> void:
	if _dialogue and is_instance_valid(_dialogue):
		return
	var CutsceneDialogueClass = load("res://src/cutscene/CutsceneDialogue.gd")
	_dialogue = CutsceneDialogueClass.new()
	add_child(_dialogue)
