extends GutTest

## struktured 2026-11-02 (preview, via cowir-main 21305): "Elder Theron's portrait is messed up on my 2nd or 3rd time
## chatting with him (I think it's the LLM prompts now)". The first talk is scripted and asks the NPC for its face
## (OverworldNPC._portrait_key); later talks go through DynamicConversation, which passed a hardcoded "villager".

const STUB_SRC := "extends Node\nvar said: Array = []\nfunc say(speaker: String, text: String, theme: String = \"narrator\", portrait: String = \"narrator\") -> void:\n\tsaid.append({\"speaker\": speaker, \"text\": text, \"theme\": theme, \"portrait\": portrait})\n"


func _stub() -> Node:
	var s := GDScript.new()
	s.source_code = STUB_SRC
	s.reload()
	var n: Node = s.new()
	return n


func _conv(portrait: String, theme: String) -> Array:
	var conv := DynamicConversation.new()
	add_child_autofree(conv)
	var stub := _stub()
	conv.add_child(stub)
	conv._npc_dialogue = stub
	conv.setup("Elder Theron", "a wise elder", "Harmonia", null, [])
	if portrait != "":
		conv.portrait_key = portrait
		conv.theme_key = theme
	await conv._show_npc_line("The crystals stir.")
	return stub.said


func test_an_llm_line_wears_the_face_it_was_given() -> void:
	var said: Array = await _conv("elder", "elder")
	assert_eq(said.size(), 1, "CONTROL: the line reached the dialogue box")
	if said.is_empty():
		return
	assert_eq(said[0]["portrait"], "elder", "the generated line shows the speaker's own portrait")
	assert_eq(said[0]["theme"], "elder", "and the speaker's own box colours")
	assert_eq(said[0]["speaker"], "Elder Theron")


func test_a_conversation_nobody_configured_still_has_a_face() -> void:
	var said: Array = await _conv("", "")
	assert_eq(said.size(), 1)
	if said.is_empty():
		return
	assert_eq(said[0]["portrait"], "villager", "an unconfigured conversation keeps the old generic face, never an empty one")


func _body(src: String, fn: String) -> String:
	var i := src.find("func " + fn)
	assert_gt(i, -1, "%s exists" % fn)
	var j := src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > -1 else 4000)


## The NPC hands over the SAME keys its scripted lines use, so both paths draw one face.
func test_the_npc_hands_its_scripted_face_to_the_llm_path() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldNPC.gd")
	var run := _body(src, "_run_dynamic_conversation")
	assert_true(run.contains("_dynamic_conv.portrait_key = _portrait_key()"), "the LLM path gets the NPC's own portrait key")
	assert_true(run.contains("_dynamic_conv.theme_key = npc_type"), "and its own theme")
	assert_lt(run.find("_dynamic_conv.portrait_key"), run.find("await _dynamic_conv.run(player)"), "set before the conversation runs")
	assert_true(src.contains("\"portrait\": _portrait_key(),"), "CONTROL: the scripted path reads the same key")


func test_theron_is_why_the_generic_face_was_wrong() -> void:
	var npc := OverworldNPC.new()
	npc.npc_name = "Elder Theron"
	npc.npc_type = "elder"
	autofree(npc)
	assert_ne(npc._portrait_key(), "villager", "Theron's own face is not the villager's — the hardcode showed him a stranger's (got %s)" % npc._portrait_key())
