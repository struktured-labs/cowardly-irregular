extends GutTest

## Regression (cowir-main's .599 village frames): Maple Heights' "X Service door" was 10px grey with no edge, drawn
## UNDER the player standing at it; Brasston's "X Read the depot record" the same in faint gold. Eleven world
## interactables each styled their own prompt, none pinned over sprites (exit labels and save points were). Every
## one now goes through Mode7Prompt.style_interact_prompt: its own tint, 12px, outlined, drawn over the player.

const DIR := "res://src/exploration/"


## Derived from source, so a new interactable that builds its own prompt is covered without editing this file.
func _prompt_builders() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		if f.ends_with(".gd") and FileAccess.get_file_as_string(DIR + f).contains("_indicator = Label.new()"):
			out.append(f)
	return out


func test_the_derived_set_holds_the_prompts_that_shipped() -> void:
	var found := _prompt_builders()
	assert_gte(found.size(), 11, "SCOPE: the scan finds the world prompts: %s" % [found])
	assert_has(found, "CivicBackDoor.gd", "SCOPE: including the faint service door")


func test_every_world_prompt_is_styled_for_legibility() -> void:
	var checked := 0
	for f in _prompt_builders():
		var s = load(DIR + f).new()
		if not (s is Node):
			continue
		add_child_autofree(s)
		var l = s.get("_indicator")
		if not (l is Label):
			continue
		checked += 1
		assert_eq(l.z_index, Mode7Prompt.WORLD_Z, "%s's prompt must draw over the player" % f)
		assert_false(l.z_as_relative, "%s's prompt z is absolute, not relative to its prop" % f)
		assert_gt(l.get_theme_constant("outline_size"), 0, "%s's prompt needs an edge to read on any floor" % f)
		assert_eq(l.get_theme_font_size("font_size"), Mode7Prompt.INTERACT_FONT, "%s's prompt is legible size" % f)
	assert_gte(checked, 11, "SCOPE: every derived interactable built its prompt")
