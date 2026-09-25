extends GutTest

## Random encounters spawn 2–3 enemies, and 60% of those groups are one species.
## The banner appended a bare "s", so the forest log read "2 Wolfs appeared!" and a
## corrupted-zone fight read "2 Glitch Entitys appeared!". The kill toast already
## said Entities / Processes / Ladies, and still said Wolfs. Calls go through the
## loaded script so a missing helper fails the assert instead of failing to parse.


func _spawner() -> Object:
	var script: GDScript = load("res://src/battle/BattleEnemySpawner.gd")
	return script.new(null)


func _phrase(counts: Dictionary) -> String:
	var spawner := _spawner()
	assert_true(spawner.has_method("encounter_count_phrase"),
		"spawn banners must share encounter_count_phrase")
	if not spawner.has_method("encounter_count_phrase"):
		return ""
	return str(spawner.call("encounter_count_phrase", counts))


func test_group_banner_uses_real_plurals() -> void:
	assert_eq(_phrase({"Wolf": 2}), "2 Wolves",
		"a same-type forest group must not say Wolfs")
	assert_eq(_phrase({"Ice Wolf": 2}), "2 Ice Wolves",
		"Ice Wolf pluralizes on the last word")
	assert_eq(_phrase({"Glitch Entity": 2}), "2 Glitch Entities",
		"Entity → Entities, the string the toast fix already named")
	assert_eq(_phrase({"Rogue Process": 2}), "2 Rogue Processes",
		"Process → Processes, not Processs")
	assert_eq(_phrase({"Cranky Lady": 2}), "2 Cranky Ladies",
		"Lady → Ladies")
	assert_eq(_phrase({"Rogue Mailbox": 2}), "2 Rogue Mailboxes",
		"Mailbox → Mailboxes")
	assert_eq(_phrase({"Slime": 2}), "2 Slimes",
		"ordinary names still take a single s")
	assert_eq(_phrase({"Wolf": 1}), "1 Wolf",
		"a lone enemy stays singular")
	assert_eq(_phrase({"Wolf": 2, "Slime": 1}), "2 Wolves and 1 Slime",
		"mixed groups pluralize only the names with a count above 1")
	assert_eq(_phrase({"Optimization Itself": 2}), "2 Optimization Itselfs",
		"the wolf rule must not rewrite Itself into Itselves")


func test_kill_toast_uses_the_same_pluralizer() -> void:
	var gl_script: GDScript = load("res://src/GameLoop.gd")
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	assert_eq(gl._pluralize_monster_name("Wolf"), "Wolves",
		"the milestone toast and the banner must agree on Wolf")
	assert_eq(gl._pluralize_monster_name("Ice Wolf"), "Ice Wolves",
		"Ice Wolf on the toast")
	assert_eq(gl._pluralize_monster_name("Glitch Entity"), "Glitch Entities",
		"the toast path still pluralizes Entity")
	assert_eq(gl._pluralize_monster_name("Optimization Itself"), "Optimization Itselfs",
		"Itself is not a wolf")


func test_spawn_paths_do_not_append_a_bare_s() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleEnemySpawner.gd")
	assert_false(src.contains('enemy_name + "s"'),
		"all three spawn banners must go through encounter_count_phrase")
	assert_eq(src.count("encounter_count_phrase(enemy_names)"), 3,
		"random, autogrind, and overworld encounter spawns each announce through the phrase")
