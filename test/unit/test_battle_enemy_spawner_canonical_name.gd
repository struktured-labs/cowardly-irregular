extends GutTest

## tick 142 regression: BattleEnemySpawner must prettify enemy_id
## when monsters.json lacks a "name" field. Pre-fix the raw
## snake_case id was used as the Combatant.name, which then flowed
## into the battle log, damage popups, gloat lines, defeat
## messages, and bestiary entries — dozens of player-facing places
## all rendering "cave_rat" instead of "Cave rat" or canonical.
##
## monsters.json entries normally have "name" so this fallback
## rarely fires in production, but Scriptweaver custom enemies
## and save-format drift can hit it. Better to leak prettifier
## output than raw snake_case.

const BATTLE_ENEMY_SPAWNER := "res://src/battle/BattleEnemySpawner.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_combatant_name_fallback_prettifies_enemy_id() -> void:
	# Pin the exact fallback string. monster_data.get("name", X)
	# where X must be the prettified id, not raw.
	var src := _read(BATTLE_ENEMY_SPAWNER)
	assert_true(src.contains("\"name\": monster_data.get(\"name\", enemy_id.replace(\"_\", \" \").capitalize())"),
		"Combatant name fallback must prettify enemy_id — pre-fix leaked raw snake_case")
	# Negative pin: the old raw-id fallback must be gone.
	assert_false(src.contains("\"name\": monster_data.get(\"name\", enemy_id),"),
		"old raw `monster_data.get('name', enemy_id)` fallback must be gone — leaked snake_case to combat name")


func test_other_get_name_default_kept_as_monster() -> void:
	# Different leak site at line ~272: data.get("name", "Monster").
	# This one is intentionally a semantic default ("Monster" is a
	# sensible placeholder, not the raw id). Don't accidentally
	# regress it to id-leak.
	var src := _read(BATTLE_ENEMY_SPAWNER)
	assert_true(src.contains("data.get(\"name\", \"Monster\")"),
		"the 'Monster' generic-placeholder default must remain — it's a semantic default, not a leak")


func test_combatant_name_flows_into_battle_log() -> void:
	# Cross-check: BattleScene's battle log uses combatant_name in
	# the rendered output. A raw-id Combatant.name would surface in
	# every log line. Pin one canonical site.
	var scene_src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(scene_src.contains("log_message(\"[color=yellow]%s has been defeated![/color]\" % enemy.combatant_name)"),
		"battle log uses combatant_name verbatim — so the spawner fallback IS what the player sees on enemy defeat")
