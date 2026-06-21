extends GutTest

## Theron's LLM-dynamic dialogue must be gated behind cutscene_flag_chapter1_complete
## so the scripted plot beats land first; LLM persona kicks in on revisits only.

const HARMONIA_PATH := "res://src/maps/villages/HarmoniaVillage.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func test_theron_dynamic_flag_is_gated_on_chapter1_complete() -> void:
	var text := _read(HARMONIA_PATH)
	var idx := text.find("Elder Theron")
	assert_gt(idx, -1, "Elder Theron must exist in HarmoniaVillage setup")
	var rest := text.substr(idx, 600)
	assert_true(rest.contains("elder.dynamic = _is_chapter1_complete()"),
		"Theron's dynamic flag must be gated on _is_chapter1_complete() — pre-chapter1 he uses scripted lines so the plot cutscene doesn't collide with LLM-generated lines")
	assert_false(rest.contains("elder.dynamic = true"),
		"Theron must NOT be unconditionally dynamic — pre-fix bug shape")


func test_is_chapter1_complete_helper_exists() -> void:
	var text := _read(HARMONIA_PATH)
	assert_true(text.find("func _is_chapter1_complete") != -1,
		"_is_chapter1_complete helper must be defined on HarmoniaVillage")
	var idx := text.find("func _is_chapter1_complete")
	var rest := text.substr(idx, 300)
	assert_true(rest.contains("cutscene_flag_chapter1_complete"),
		"_is_chapter1_complete must read game_constants[cutscene_flag_chapter1_complete]")
