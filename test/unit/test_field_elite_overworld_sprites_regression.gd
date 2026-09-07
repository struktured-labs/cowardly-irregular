extends GutTest

## Regression: the W1 field elite (dark_knight) rendered as a magenta placeholder box on the
## overworld in v3.33.226 — it had a BATTLE sheet in sprite_manifest.json but RoamingMonster
## loads overworld art by PATH (assets/sprites/monsters/overworld/<id>.png), which is a
## different ledger. Every elite is the one monster a player is meant to stare at; none may
## fall through to the hue-hashed square. (cowir-deploy store-shot pass, 2026-09-07)

const ELITE_DATA := "res://data/field_elites.json"
## FileAccess, not ResourceLoader.exists — the latter answers YES from the .import cache after
## the PNG is gone (measured: the mutation arm stayed green with the file moved away).
const OVERWORLD_DIR := "res://assets/sprites/monsters/overworld/%s.png"


func _per_world() -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ELITE_DATA))
	return cfg.get("per_world", {})


func test_every_field_elite_has_an_overworld_sheet_on_disk() -> void:
	var per := _per_world()
	assert_gt(per.size(), 1, "CONTROL: the roster must be populated or this test checks nothing")
	var missing: Array[String] = []
	for world in per:
		var id: String = str(per[world])
		if not FileAccess.file_exists(OVERWORLD_DIR % id):
			missing.append("%s (%s)" % [id, world])
	assert_eq(missing, [] as Array[String],
		"field elites with NO overworld sheet — they render as a placeholder box: %s" % str(missing))


func test_the_probe_can_see_absence() -> void:
	assert_false(FileAccess.file_exists(OVERWORLD_DIR % "zzz_no_such_monster"),
		"CONTROL: a fabricated id must read as missing, or the assertion above is vacuous")


func test_roaming_monster_loads_overworld_art_by_path_not_manifest() -> void:
	# Pins the mechanism the fix targets: if this ever moves to the manifest, move the check too.
	var src := FileAccess.get_file_as_string("res://src/exploration/RoamingMonster.gd")
	assert_true(src.contains('"res://assets/sprites/monsters/overworld/%s.png" % monster_id'),
		"RoamingMonster resolves overworld sheets by path; this test's ledger must match")
