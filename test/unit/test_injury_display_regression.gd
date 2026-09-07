extends GutTest

## Permanent injuries carry authored flavor text (INJURY_TYPES
## descriptions like "Fractured ribs") plus the mechanical penalty —
## the StatusMenu rendered only the raw stat key ("- Max_hp: -8"),
## reading like debug output and wasting the flavor that makes the
## stakes FEEL permanent. Now: "- Fractured ribs (Max HP -8)".

const StatusMenuScript = preload("res://src/ui/StatusMenu.gd")


func test_injury_line_shows_description_and_pretty_stat() -> void:
	var line: String = StatusMenuScript._format_injury(
		{"stat": "max_hp", "description": "Fractured ribs", "penalty": 8})
	assert_eq(line, "- Fractured ribs (Max HP -8)")


func test_max_mp_prettified() -> void:
	var line: String = StatusMenuScript._format_injury(
		{"stat": "max_mp", "description": "Mana drain wound", "penalty": 5})
	assert_true(line.contains("Max MP -5"), "max_mp must render as 'Max MP', got: %s" % line)


func test_plain_stats_capitalize() -> void:
	var line: String = StatusMenuScript._format_injury(
		{"stat": "speed", "description": "Sprained ankle", "penalty": 2})
	assert_eq(line, "- Sprained ankle (Speed -2)")


func test_missing_description_falls_back_to_stat_form() -> void:
	# Old saves / synthetic injuries may lack description — must not
	# render "- ( -3)" garbage.
	var line: String = StatusMenuScript._format_injury(
		{"stat": "attack", "penalty": 3})
	assert_eq(line, "- Attack -3")


func test_every_authored_injury_type_formats_cleanly() -> void:
	# Data sweep: all INJURY_TYPES entries must produce a line with
	# their description and a real penalty number.
	for template in BattleManager.INJURY_TYPES:
		var injury := {
			"stat": template["stat"],
			"description": template["description"],
			"penalty": int(template["base_penalty"]),
		}
		var line: String = StatusMenuScript._format_injury(injury)
		assert_true(line.contains(str(template["description"])),
			"authored flavor must appear: %s" % line)
		assert_true(line.contains("-%d" % int(template["base_penalty"])),
			"penalty must appear: %s" % line)
