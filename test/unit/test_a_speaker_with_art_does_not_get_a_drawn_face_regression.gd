extends GutTest

## `_create_portrait` had four rungs and none of them looked at a MONSTER sheet, so a speaker whose
## art is a monster sheet got a PROCEDURAL face. Census of every authored portrait id, 2026-09-16:
##
##   before   artist 40 ids / 1919 lines · bust 0 · procedural 14 ids / 396 lines · blur 1 / 17
##   after    artist 40 / 1919           · bust 13 ids / 342     · procedural 1 / 54 · blur 1 / 17
##
## The 13 are the goblin (artist art per CLAUDE.md) and 12 masterite world-variants — while the SAME
## masterite in another world showed its portrait, because those worlds' variants happen to be in
## PORTRAIT_SPRITES. `system` (54) and `narrator` (17) stay drawn, correctly: neither is a character.

const DialogueScript = preload("res://src/cutscene/CutsceneDialogue.gd")

var _box: Node


const SYNTH_ID := "zz_synthetic_late_idle"

var _synth_registered: bool = false


func before_each() -> void:
	_box = DialogueScript.new()
	add_child_autofree(_box)
	_box.show_dialogue([{"speaker": "x", "text": "x", "theme": "narrator", "portrait": "narrator"}])


## The loader's manifest is static — anything registered here must be erased, or the next file inherits it.
func after_each() -> void:
	if _synth_registered:
		HybridSpriteLoader._monster_manifest.erase(SYNTH_ID)
		_synth_registered = false


## Every portrait id any authored line asks for, with its line count.
func _authored_ids() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/cutscenes")
	if dir == null:
		return out
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for f in names:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
		if not (d is Dictionary):
			continue
		for s in d.get("steps", []):
			if not (s is Dictionary):
				continue
			var lines = s.get("lines", null)
			if not (lines is Array):
				continue
			for it in lines:
				if not (it is Dictionary):
					continue
				var id: String = str(it.get("portrait", it.get("theme", "narrator")))
				if id == "":
					id = "narrator"
				out[id] = int(out.get(id, 0)) + 1
	return out


## A texture the game AUTHORED (a loaded PNG, or an atlas window onto a sheet) rather than one it drew.
func _is_real_art(tex: Texture2D) -> bool:
	if tex == null:
		return false
	return tex.resource_path != "" or tex is AtlasTexture


func test_a_monster_sheet_speaker_gets_its_own_art() -> void:
	var tex: Texture2D = _box._create_bust_from_monster_sheet("goblin")
	assert_not_null(tex, "the goblin has an artist sheet on disk and speaks 4 authored lines")
	if tex == null:
		return
	assert_true(tex is AtlasTexture, "the bust must be a window onto the sheet, not a redrawn image")
	var atlas: AtlasTexture = tex
	assert_string_contains(atlas.atlas.resource_path, "goblin",
		"and the window must be onto the goblin's own sheet: %s" % atlas.atlas.resource_path)


## A box that overflows its frame samples the NEXT frame — the visible failure is two half-monsters.
func test_the_bust_window_stays_inside_its_own_frame() -> void:
	var checked: int = 0
	for id in ["goblin", "masterite_arbiter_abstract", "masterite_warden_futuristic"]:
		var frame_tex: AtlasTexture = HybridSpriteLoader.monster_frame_texture(id, "idle")
		var bust = _box._create_bust_from_monster_sheet(id)
		if frame_tex == null or bust == null:
			continue
		checked += 1
		var frame: Rect2 = frame_tex.region
		var box: Rect2 = (bust as AtlasTexture).region
		assert_true(frame.encloses(box),
			"%s: bust %s must sit inside its idle frame %s" % [id, str(box), str(frame)])
	assert_eq(checked, 3, "PRECONDITION: all three fixtures must resolve, else this measures nothing")
	# And a crop must actually happen: the goblin's figure fills 55 of its 128px frame, so serving the
	# whole frame would put a small figure in the corner of an 80px portrait — the frame-vs-figure bug
	# this codebase fixed on three other surfaces today.
	var g_frame: AtlasTexture = HybridSpriteLoader.monster_frame_texture("goblin", "idle")
	var g_bust = _box._create_bust_from_monster_sheet("goblin")
	assert_lt((g_bust as AtlasTexture).region.size.x, g_frame.region.size.x * 0.9,
		"the goblin bust must crop its frame's padding away, not serve the frame")


## THE PROPERTY, over the authored corpus: art on disk is never replaced by a drawn face.
func test_no_authored_speaker_with_art_gets_a_drawn_face() -> void:
	var ids: Dictionary = _authored_ids()
	assert_gt(ids.size(), 20, "PRECONDITION: the corpus must load")
	var with_art: int = 0
	var served: Array = []
	for id in ids.keys():
		var has_sheet: bool = HybridSpriteLoader.monster_frame_texture(str(id), "idle") != null
		var has_portrait: bool = DialogueScript.PORTRAIT_SPRITES.has(str(id))
		if not (has_sheet or has_portrait):
			continue
		with_art += 1
		var tex: Texture2D = _box._create_portrait(str(id))
		assert_true(_is_real_art(tex),
			"%s speaks %d authored lines and has art on disk — it must not render a drawn face" % [id, ids[id]])
		if tex is AtlasTexture:
			served.append("%s(%d)" % [id, ids[id]])
	gut.p("authored ids with art: %d · served by a sheet bust: %s" % [with_art, str(served)])
	assert_gt(with_art, 10,
		"ANTI-VACUITY: the corpus must name at least ten speakers whose art is on disk, else the assert above is free")


## CONTROL: a speaker with no art anywhere still gets a face, never null and never a crash.
func test_a_speaker_with_no_art_still_gets_a_face() -> void:
	var tex: Texture2D = _box._create_portrait("zzz_no_such_speaker_id")
	assert_not_null(tex, "the procedural fallback must still answer for an unknown speaker")
	assert_false(_is_real_art(tex), "and it must be a drawn face, not art this test mistook for one")
	assert_null(_box._create_bust_from_monster_sheet("zzz_no_such_speaker_id"),
		"the monster rung must decline an id with no sheet rather than inventing one")


## 342 lines share 13 busts: the crop is cached, and the key carries the world so a world change cannot serve the last world's face.
func test_the_bust_is_cached_per_world() -> void:
	var a: Texture2D = _box._create_bust_from_monster_sheet("goblin")
	var b: Texture2D = _box._create_bust_from_monster_sheet("goblin")
	assert_eq(a, b, "a second ask must return the cached crop, not a fresh one")
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDialogue.gd")
	var i := src.find("func _create_bust_from_monster_sheet")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1200)
	assert_true("current_world_suffix()" in body and "cache_key" in body,
		"the cache key must carry the world suffix — a per-world variant would otherwise be served the first world's crop forever")
	assert_true("monster_frame_texture" in body,
		"the frame must come from the loader, not from a path built here")
	assert_false("get_used_rect" in body,
		"the figure scan has ONE owner (HybridSpriteLoader.figure_rect, via bust_region) — no second scan here")


## No shipped sheet starts its idle past frame 0, so the offset into the idle frame is defensive —
## pinned on a synthetic entry rather than left unmeasured, because the failure is silent: the bust
## would crop frame 0 and the speaker would wear another pose's face.
func test_the_bust_follows_a_late_idle_frame() -> void:
	HybridSpriteLoader._load_manifest()
	var goblin: Dictionary = HybridSpriteLoader._monster_manifest.get("goblin", {})
	assert_false(goblin.is_empty(), "PRECONDITION: the goblin entry is the fixture's sheet")
	if goblin.is_empty():
		return
	var entry: Dictionary = goblin.duplicate(true)
	entry["animations"] = {"idle": {"start": 2, "end": 2}}
	HybridSpriteLoader._monster_manifest[SYNTH_ID] = entry
	_synth_registered = true
	var frame_tex: AtlasTexture = HybridSpriteLoader.monster_frame_texture(SYNTH_ID, "idle")
	assert_not_null(frame_tex, "the synthetic entry must resolve through the real loader")
	if frame_tex == null:
		return
	assert_gt(frame_tex.region.position.x, 0.0, "PRECONDITION: frame 2 must not sit at x=0")
	var bust = _box._create_bust_from_monster_sheet(SYNTH_ID)
	assert_not_null(bust)
	if bust == null:
		return
	assert_true(frame_tex.region.encloses((bust as AtlasTexture).region),
		"the bust must sit inside the IDLE frame %s, not frame 0 — got %s" % [
			str(frame_tex.region), str((bust as AtlasTexture).region)])
