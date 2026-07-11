extends GutTest

## Artist-collab transparency ratchet: every overworld walk sheet on disk
## (jobs + NPCs) must be registered in sprite_manifest.json with a tier tag,
## and every registered entry must resolve on disk. The 26 npc sheets and
## 9 advanced/meta job sheets shipped untracked before this audit — AI-vs-
## artist provenance is a core pillar (the artist has approval rights on
## what ships, so untracked AI sheets are a policy hole, not just tidiness).

const MANIFEST_PATH := "res://data/sprite_manifest.json"
const VALID_TIERS := ["T0", "T1", "T2", "T3"]

## section name -> disk root holding <name>/overworld.png dirs
const SHEET_ROOTS := {
	"overworld_player_sheets": "res://assets/sprites/jobs",
	"overworld_npc_sheets": "res://assets/sprites/npcs",
}


func _load_manifest() -> Dictionary:
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert_not_null(file, "sprite_manifest.json must open")
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(parsed is Dictionary, "manifest root must be a Dictionary")
	return parsed if parsed is Dictionary else {}


func _disk_sheet_names(root: String) -> Array:
	var names: Array = []
	var dir = DirAccess.open(root)
	assert_not_null(dir, "sheet root must open: %s" % root)
	for sub in dir.get_directories():
		if ResourceLoader.exists("%s/%s/overworld.png" % [root, sub]):
			names.append(sub)
	return names


func test_every_disk_overworld_sheet_is_registered_with_tier() -> void:
	var manifest := _load_manifest()
	for section in SHEET_ROOTS:
		var entries = manifest.get(section, {})
		assert_true(entries is Dictionary and not entries.is_empty(),
			"manifest must have a populated '%s' section" % section)
		for name in _disk_sheet_names(SHEET_ROOTS[section]):
			assert_true(entries.has(name),
				"%s/%s/overworld.png is on disk but unregistered in %s — every AI sheet needs provenance tracking" % [SHEET_ROOTS[section], name, section])
			if entries.has(name):
				var tier = str(entries[name].get("tier", ""))
				assert_true(tier in VALID_TIERS,
					"%s entry '%s' needs a valid tier (got '%s') — T1=AI prototype, T2/T3=artist" % [section, name, tier])


func test_every_registered_overworld_sheet_exists_on_disk() -> void:
	var manifest := _load_manifest()
	for section in SHEET_ROOTS:
		var entries = manifest.get(section, {})
		for name in entries:
			var path = str(entries[name].get("path", ""))
			assert_true(ResourceLoader.exists(path),
				"%s entry '%s' points at missing asset %s — stale manifest entry" % [section, name, path])


func test_registered_paths_match_naming_convention() -> void:
	# Entry key must equal the sheet's directory name — the loaders resolve
	# by convention (npcs/<archetype>/overworld.png), so a drifted key is a
	# silently-wrong provenance record.
	var manifest := _load_manifest()
	for section in SHEET_ROOTS:
		var entries = manifest.get(section, {})
		for name in entries:
			var expected = "%s/%s/overworld.png" % [SHEET_ROOTS[section], name]
			assert_eq(str(entries[name].get("path", "")), expected,
				"%s entry '%s' path must follow the <root>/<name>/overworld.png convention" % [section, name])
