extends GutTest

## CLAUDE.md's artist-first hierarchy (T3>T2>T1>T0) lives in ONE ordering: BattleScene
## ._get_monster_sprite_frames consults the manifest BEFORE the procedural `match`.
## The pre-existing guard on that function pins SOURCE TEXT — measured 2026-08-22, disabling
## the manifest branch entirely (`if false and external_frames:`) left it 4/4 green with
## Asserts 16 unchanged, because both pinned tokens survive. A spelling cannot see an ordering.
##
## This asserts the OTHER END OF THE PIPE: the manifest path builds AtlasTexture over the
## declared PNG, procedural builds ImageTexture. The texture the player gets names its source.

const MANIFEST := "res://data/sprite_manifest.json"


func _sheets() -> Dictionary:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(txt, "", "sprite_manifest.json must be readable")
	var parsed = JSON.parse_string(txt)
	return (parsed as Dictionary).get("monster_sheets", {}) if parsed is Dictionary else {}


func test_every_manifest_monster_renders_from_its_own_png() -> void:
	var sheets := _sheets()
	assert_gt(sheets.size(), 10, "CONTROL: manifest must carry the monster roster")
	var bs = load("res://src/battle/BattleScene.gd").new()
	assert_not_null(bs, "BattleScene must instantiate bare — the resolver is the unit under test")
	var scanned: Array = []
	var wrong: Array = []
	for id in sheets:
		var declared: String = str((sheets[id] as Dictionary).get("path", ""))
		if not ResourceLoader.exists(declared):
			continue
		var f = bs._get_monster_sprite_frames(id)
		if f == null or not f.has_animation("idle") or f.get_frame_count("idle") == 0:
			wrong.append("%s: resolver returned no idle frames" % id)
			continue
		scanned.append(id)
		var t = f.get_frame_texture("idle", 0)
		# procedural returns ImageTexture; only the manifest path cuts an atlas out of the sheet
		if not (t is AtlasTexture) or t.atlas == null:
			wrong.append("%s: got %s, not an atlas over its sheet — procedural won" % [id, t.get_class() if t != null else "null"])
		elif t.atlas.resource_path != declared:
			wrong.append("%s: atlas is %s, manifest declares %s" % [id, t.atlas.resource_path, declared])
	bs.free()
	# named members the scan MUST reach — a count passes on one stray match
	assert_true(scanned.has("ogre"), "scan must reach ogre — else it read nothing")
	assert_true(scanned.has("slime"), "scan must reach slime, which also has a procedural creator")
	assert_gt(scanned.size(), 50, "scan must cover the bulk of the roster (%d)" % scanned.size())
	assert_eq(wrong, [], "artist/AI art lost to procedural, or resolved to the wrong sheet: %s" % [wrong])
