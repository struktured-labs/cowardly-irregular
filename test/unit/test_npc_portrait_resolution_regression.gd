extends GutTest

## Regression: every placed NPC must resolve to a portrait that EXISTS.
##
## struktured, 2026-07-31: "phil the lost: no portrait … PLEASE MAKE PORTRAITS
## FOR ALL SPRITES", then "young pip: no sprite", "rowan: no sprite",
## "its just busted basically same w/milo".
##
## Two defects, and the first is why phil.png never rendered once:
##   1. OverworldNPC passed `npc_type` as the dialogue portrait, IGNORING
##      sprite_archetype. Phil is _create_npc("Phil the Lost", "villager") with
##      sprite_archetype = "phil" — so his SPRITE was Phil and his PORTRAIT was
##      "villager". Same for Bram, Scholar Milo, Elder Theron, Dr. Temporal.
##   2. `villager` — the npc_type of 55 placed NPCs — had no portrait art at all,
##      so all of them fell to the generic procedural shopkeeper face.
##
## The join below is what nobody had: placements -> resolved archetype -> portrait.
## A named NPC losing its face again fails here instead of in struktured's session.

const OVERWORLD_NPC := "res://src/exploration/OverworldNPC.gd"
const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const MAPS_DIR := "res://src/maps"


func _portrait_sprites() -> Dictionary:
	var src := FileAccess.get_file_as_string(CUTSCENE_DIALOGUE)
	assert_ne(src, "", "CutsceneDialogue must be readable — it owns PORTRAIT_SPRITES")
	var out: Dictionary = {}
	var start := src.find("const PORTRAIT_SPRITES")
	var stop := src.find("\n}", start)
	if start < 0 or stop < 0:
		return out
	var rx := RegEx.new()
	rx.compile('"([a-z_0-9]+)"\\s*:\\s*"(res://[^"]+\\.png)"')
	for m in rx.search_all(src.substr(start, stop - start)):
		out[m.get_string(1)] = m.get_string(2)
	return out


## Every (name, npc_type) pair placed by a map script, with any sprite_archetype override.
func _placements() -> Array:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile('(\\w+)\\s*=\\s*_create_npc\\(\\s*"([^"]+)"\\s*,\\s*"([a-z_0-9]+)"')
	var arx := RegEx.new()
	arx.compile('(\\w+)\\.sprite_archetype\\s*=\\s*"([a-z_0-9]+)"')
	for path in _gd_files(MAPS_DIR):
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var overrides: Dictionary = {}
		for m in arx.search_all(src):
			overrides[m.get_string(1)] = m.get_string(2)
		for m in rx.search_all(src):
			out.append({
				"var": m.get_string(1), "name": m.get_string(2),
				"type": m.get_string(3),
				"archetype": overrides.get(m.get_string(1), ""),
				"file": path.get_file(),
			})
	return out


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_gd_files("%s/%s" % [dir_path, sub]))
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, f])
	return out


func test_overworld_npc_sends_the_ARCHETYPE_not_the_npc_type() -> void:
	# The original defect in one line — a bare `npc_type` here means every named
	# NPC shows its archetype's face instead of its own.
	var src := FileAccess.get_file_as_string(OVERWORLD_NPC)
	assert_ne(src, "", "OverworldNPC must be readable")
	assert_false(src.contains('"portrait": npc_type'),
		"OverworldNPC must not send npc_type as the portrait — that is the bug that " +
		"made phil.png never render. Send _portrait_key() (resolves sprite_archetype).")
	assert_true(src.contains('"portrait": _portrait_key()'),
		"dialogue lines must carry _portrait_key()")
	assert_true(src.contains("func _portrait_key"),
		"_portrait_key() must exist and resolve through _resolve_archetype")


func test_every_declared_portrait_path_exists() -> void:
	var sprites := _portrait_sprites()
	# NAMED control — a size floor would pass while the regex silently drifted.
	for known in ["fighter", "villager", "phil"]:
		assert_true(sprites.has(known),
			"PORTRAIT_SPRITES must yield '%s' — if not, the extraction drifted and every result below is measuring nothing" % [known])

	# masterite_* are DELIBERATELY pre-registered ahead of art: _create_portrait's
	# default arm tests begins_with("masterite_") and draws the mysterious face, so
	# they degrade on purpose rather than to a narrator blur. Everything else must exist.
	var missing: Array = []
	var preregistered: Array = []
	for key in sprites:
		if ResourceLoader.exists(sprites[key]):
			continue
		if str(key).begins_with("masterite_"):
			preregistered.append(key)
		else:
			missing.append("%s -> %s" % [key, sprites[key]])
	missing.sort()
	assert_eq(missing, [],
		"PORTRAIT_SPRITES declares path(s) with no PNG and no deliberate fallback — the " +
		"key falls through to a generic face and the authored intent is silently lost: %s" % [missing])
	# The exemption must stay EARNED: if the masterite prefix arm is ever removed,
	# these stop degrading deliberately and this becomes a real hole.
	if not preregistered.is_empty():
		var src := FileAccess.get_file_as_string(CUTSCENE_DIALOGUE)
		assert_true(src.contains('begins_with("masterite_")'),
			("%d masterite portrait(s) are declared without art and are only safe because " +
			"_create_portrait's default arm draws them as mysterious. That arm is gone, so " +
			"they now render a narrator blur.") % [preregistered.size()])


func test_every_placed_npc_resolves_to_a_real_portrait() -> void:
	var sprites := _portrait_sprites()
	var placed := _placements()
	assert_gt(placed.size(), 50,
		"sanity: expected >50 placed NPCs, found %d — the placement scan is broken" % [placed.size()])
	# NAMED control: the NPCs struktured reported must be in the scan.
	var names: Array = []
	for p in placed:
		names.append(p["name"])
	for known in ["Phil the Lost", "Young Pip", "Rowan", "Scholar Milo"]:
		assert_true(known in names,
			("the placement scan must find '%s' — it is placed in a shipped map, so if " +
			"this fails every result below is a false clean") % [known])

	# A named NPC (sprite_archetype set) must have art for THAT archetype.
	var faceless: Array = []
	for p in placed:
		var arch: String = p["archetype"]
		if arch == "":
			continue
		if not sprites.has(arch):
			faceless.append("%s (%s) -> archetype '%s' has no PORTRAIT_SPRITES entry" % [p["name"], p["file"], arch])
	faceless.sort()
	assert_eq(faceless, [],
		"named NPC(s) whose sprite_archetype has no portrait — they render a generic " +
		"face while their own sprite is on screen: %s" % [faceless])


func test_the_high_traffic_npc_types_all_have_art() -> void:
	# villager alone is 55 placed NPCs. These are the types that, missing art,
	# make most of the game's cast share one procedural face.
	var sprites := _portrait_sprites()
	var bare: Array = []
	for t in ["villager", "elder", "guard", "shopkeeper", "child", "traveler",
			"farmer", "scholar", "blacksmith", "mysterious", "merchant"]:
		if not sprites.has(t):
			bare.append(t)
		elif not ResourceLoader.exists(sprites[t]):
			bare.append("%s (declared, file missing)" % [t])
	bare.sort()
	assert_eq(bare, [],
		"high-traffic npc_type(s) with no portrait art — every NPC of that type shares " +
		"one generic procedural face: %s" % [bare])
