extends GutTest

## The artist-first hierarchy is one branch ordering in BattleScene._get_monster_sprite_frames; a source pin cannot see an ordering, so assert the delivered texture's provenance.

const MANIFEST := "res://data/sprite_manifest.json"

var _saved_area: String = ""
var _saved_suffix: String = ""


func before_each() -> void:
	_saved_area = SoundManager._current_area
	_saved_suffix = SoundManager._current_world_suffix


func after_each() -> void:
	SoundManager._current_area = _saved_area
	SoundManager._current_world_suffix = _saved_suffix


func _sheets() -> Dictionary:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(txt, "", "sprite_manifest.json must be readable")
	var parsed = JSON.parse_string(txt)
	return (parsed as Dictionary).get("monster_sheets", {}) if parsed is Dictionary else {}


func _declared(sheets: Dictionary, id: String) -> String:
	return str((sheets.get(id, {}) as Dictionary).get("path", ""))


func _pin_world(area: String, want: String) -> void:
	SoundManager._current_area = area
	SoundManager._current_world_suffix = want
	assert_eq(SoundManager._get_current_world_suffix(), want,
		"CONTROL: the world pin must hold — the resolver's variant branch keys on it, so an ambient world set by an earlier test makes every path below a different question")


func _idle_atlas_path(bs, id: String) -> String:
	var f = bs._get_monster_sprite_frames(id)
	if f == null or not f.has_animation("idle") or f.get_frame_count("idle") == 0:
		return "<no idle frames>"
	var t = f.get_frame_texture("idle", 0)
	# procedural returns ImageTexture; only the manifest path cuts an atlas out of the sheet
	if not (t is AtlasTexture) or t.atlas == null:
		return "<%s, not an atlas — procedural won>" % (t.get_class() if t != null else "null")
	return t.atlas.resource_path


func test_every_manifest_monster_renders_from_its_own_png() -> void:
	var sheets := _sheets()
	assert_gt(sheets.size(), 10, "CONTROL: manifest must carry the monster roster")
	_pin_world("overworld", "medieval")
	var bs = load("res://src/battle/BattleScene.gd").new()
	assert_not_null(bs, "BattleScene must instantiate bare — the resolver is the unit under test")
	var scanned: Array = []
	var wrong: Array = []
	for id in sheets:
		var declared := _declared(sheets, id)
		if not ResourceLoader.exists(declared):
			continue
		scanned.append(id)
		var got := _idle_atlas_path(bs, id)
		if got != declared:
			wrong.append("%s: resolved %s, manifest declares %s" % [id, got, declared])
	bs.free()
	# named members the scan MUST reach — a count passes on one stray match
	assert_true(scanned.has("ogre"), "scan must reach ogre — else it read nothing")
	assert_true(scanned.has("slime"), "scan must reach slime, which also has a procedural creator")
	assert_gt(scanned.size(), 50, "scan must cover the bulk of the roster (%d)" % scanned.size())
	assert_eq(wrong, [], "artist/AI art lost to procedural, or resolved to the wrong sheet: %s" % [wrong])


func test_per_world_variant_overrides_the_base_sheet() -> void:
	var sheets := _sheets()
	assert_true(sheets.has("slime_abstract"), "CONTROL: the variant this test turns on must exist in the manifest")
	assert_false(sheets.has("ogre_abstract"), "CONTROL: ogre must have NO variant — it is the fall-through case")
	_pin_world("vertex_village", "abstract")
	var bs = load("res://src/battle/BattleScene.gd").new()
	var got_slime := _idle_atlas_path(bs, "slime")
	var got_ogre := _idle_atlas_path(bs, "ogre")
	bs.free()
	assert_eq(got_slime, _declared(sheets, "slime_abstract"),
		"outside medieval the variant sheet must win for a monster that has one")
	assert_ne(got_slime, _declared(sheets, "slime"),
		"CONTROL: the variant must differ from the base sheet, else the assertion above is trivially true")
	assert_eq(got_ogre, _declared(sheets, "ogre"),
		"a variant MISS must fall through to the monster's own manifest sheet, never to procedural")
