extends GutTest

## Corruption readout in the OverworldMenu (2026-07-02). Corruption is
## a save-threatening core mechanic that was visible ONLY inside the
## autogrind dashboard — everywhere else the player flew blind.
## The menu info block now shows level + active effects, hidden at
## zero so untouched players meet the mechanic diegetically.

const MenuScript = preload("res://src/ui/OverworldMenu.gd")


func test_zero_corruption_renders_nothing() -> void:
	assert_eq(MenuScript._corruption_summary(0.0, []).size(), 0,
		"zero corruption must stay invisible — diegetic reveal")
	assert_eq(MenuScript._corruption_summary(-0.1, []).size(), 0)


func test_level_renders_as_percentage() -> void:
	var lines: Array = MenuScript._corruption_summary(0.23, [])
	assert_eq(lines.size(), 1)
	assert_eq(str(lines[0]), "Corruption: 23%")


func test_effects_append_count_and_pretty_names() -> void:
	var lines: Array = MenuScript._corruption_summary(0.5, ["inverted_healing", "static_whispers"])
	assert_eq(lines.size(), 2)
	assert_true(str(lines[0]).contains("(2 effects)"))
	assert_true(str(lines[1]).contains("Inverted Healing"),
		"snake_case effect ids must render human-readable, got: %s" % lines[1])
	assert_true(str(lines[1]).contains("Static Whispers"))


func test_single_effect_singular_grammar() -> void:
	var lines: Array = MenuScript._corruption_summary(0.1, ["inverted_healing"])
	assert_true(str(lines[0]).contains("(1 effect)"),
		"singular effect must not read '(1 effects)'")
