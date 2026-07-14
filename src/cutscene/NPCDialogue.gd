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
	if _active or lines.is_empty():
		return
	_active = true

	_ensure_dialogue()
	if not _dialogue or not is_instance_valid(_dialogue):
		_active = false
		return
	_dialogue.show_dialogue(lines)
	await _dialogue.dialogue_finished

	_active = false
	conversation_finished.emit()


func is_active() -> bool:
	return _active


## Wave C: pass-through for the LLM "thinking" indicator. DynamicConversation
## toggles this on before each awaited LLM call (opening / reply / choices)
## and off when the call resolves (success, fallback, or 6s client timeout)
## so the player sees animated dots instead of a frozen blank panel.
##
## Lazy-instantiates the underlying CutsceneDialogue so callers don't have to
## pre-warm the visual stack just to flash the indicator. If the load fails
## (e.g. unit-test context without the resource pipeline), the call is a no-op.
func set_thinking(active: bool) -> void:
	_ensure_dialogue()
	if _dialogue == null or not is_instance_valid(_dialogue):
		return
	if _dialogue.has_method("set_thinking"):
		_dialogue.set_thinking(active)


func is_thinking() -> bool:
	if _dialogue == null or not is_instance_valid(_dialogue):
		return false
	if _dialogue.has_method("is_thinking"):
		return _dialogue.is_thinking()
	return false


func _ensure_dialogue() -> void:
	if _dialogue and is_instance_valid(_dialogue):
		return
	var CutsceneDialogueClass = load("res://src/cutscene/CutsceneDialogue.gd")
	if CutsceneDialogueClass == null:
		return
	_dialogue = CutsceneDialogueClass.new()
	add_child(_dialogue)
