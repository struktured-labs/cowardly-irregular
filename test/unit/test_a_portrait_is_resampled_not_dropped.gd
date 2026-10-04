extends GutTest

## Every portrait drawn smaller than its art was pixel-DROPPED into the dialogue box. The box draws a 72px rect under the
## project's NEAREST filter, and the faces are 256px painted files or 130-246px busts cut from 256px monster sheets — none
## with a pixel grid (88 files, 33 boss busts measured) — so it kept ~1 source pixel in 2-3.5, unevenly: stair-stepped
## hair, broken outlines, eyes that lose a row. Every cutscene line and every battle intro. Now the art is resampled
## ONCE to the box and drawn 1:1.
## Judged on what the box DRAWS — its texture at the rect's scale — against an exact AREA AVERAGE of the source, a
## reference no resampler in the code produces. On all 88 files: a nearest drop scores 1.0x of its own error by
## definition, Godot's CUBIC ~1.0x (its kernel does not widen when shrinking), Lanczos 0.09-0.23x.

const CutsceneScript := preload("res://src/cutscene/CutsceneDialogue.gd")
const BattleScript := preload("res://src/ui/BattleDialogue.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
## The shown face's error against the area average, as a fraction of a nearest drop's error on the same art.
const MAX_ERROR_VS_DROP := 0.5
## Below this a drop is invisible and so is any fix: the least-detailed authored file measured 0.0104.
const MIN_DROP_ERROR := 0.005


func _box_average(src: Image, w: int, h: int) -> PackedFloat32Array:
	## Exact area average of premultiplied RGB at w x h: each output pixel is the mean of the source it covers.
	var sw := src.get_width()
	var sh := src.get_height()
	var d := src.get_data()
	var sx := float(sw) / w
	var sy := float(sh) / h
	var rows := PackedFloat32Array()
	rows.resize(w * sh * 3)
	for y in sh:
		for x in w:
			var a0 := x * sx
			var a1 := a0 + sx
			var acc := Vector3.ZERO
			var i := int(floor(a0))
			while i < sw and float(i) < a1:
				var o := (y * sw + i) * 4
				var k := (minf(a1, i + 1.0) - maxf(a0, float(i))) * d[o + 3] / 255.0 / 255.0
				acc += Vector3(d[o], d[o + 1], d[o + 2]) * k
				i += 1
			for c in 3:
				rows[(y * w + x) * 3 + c] = acc[c] / sx
	var out := PackedFloat32Array()
	out.resize(w * h * 3)
	for x in w:
		for y in h:
			var b0 := y * sy
			var b1 := b0 + sy
			var acc := Vector3.ZERO
			var j := int(floor(b0))
			while j < sh and float(j) < b1:
				var k := minf(b1, j + 1.0) - maxf(b0, float(j))
				acc += Vector3(rows[(j * w + x) * 3], rows[(j * w + x) * 3 + 1], rows[(j * w + x) * 3 + 2]) * k
				j += 1
			for c in 3:
				out[(y * w + x) * 3 + c] = acc[c] / sy
	return out


func _error(img: Image, ref: PackedFloat32Array) -> float:
	var d := img.get_data()
	var n := img.get_width() * img.get_height()
	var t := 0.0
	for p in n:
		var al := d[p * 4 + 3] / 255.0
		for c in 3:
			t += absf(d[p * 4 + c] / 255.0 * al - ref[p * 3 + c])
	return t / float(n * 3)


func _rgba(tex: Texture2D) -> Image:
	var img: Image = tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _minified(source: Texture2D, rect: TextureRect) -> bool:
	return minf(rect.size.x / source.get_width(), rect.size.y / source.get_height()) < 1.0


## What a box draws for `source`: "" when the shown face is the source resampled 1:1 and close to its area average.
func _judge(label: String, rect: TextureRect, source: Texture2D) -> String:
	var shown: Texture2D = rect.texture
	if shown == null:
		return "%s: no face shown" % label
	var scale: float = minf(rect.size.x / shown.get_width(), rect.size.y / shown.get_height())
	if absf(scale - 1.0) > 0.001:
		return "%s: %dx%d art drawn at %.2fx into a %s rect" % [label, shown.get_width(), shown.get_height(), scale, rect.size]
	var drawn := _rgba(shown)
	var src := _rgba(source)
	var ref := _box_average(src, drawn.get_width(), drawn.get_height())
	var dropped := src.duplicate() as Image
	dropped.resize(drawn.get_width(), drawn.get_height(), Image.INTERPOLATE_NEAREST)
	var drop_err := _error(dropped, ref)
	if drop_err < MIN_DROP_ERROR:
		return "%s: CONTROL: a pixel drop of this art is only %.4f off, so nothing here can be judged" % [label, drop_err]
	var err := _error(drawn, ref)
	if err > drop_err * MAX_ERROR_VS_DROP:
		return "%s: %.4f off the area average, a pixel drop is %.4f" % [label, err, drop_err]
	return ""


func _authored() -> Dictionary:
	## portrait id -> its painted texture, one id per file.
	var out := {}
	var seen := {}
	var ids: Array = CutsceneScript.PORTRAIT_SPRITES.keys()
	ids.sort()
	for id in ids:
		var path := str(CutsceneScript.PORTRAIT_SPRITES[id])
		if seen.has(path) or not ResourceLoader.exists(path):
			continue
		seen[path] = true
		out[id] = load(path)
	return out


func _intro_bosses() -> Dictionary:
	## monster id -> its display name, for every monster with an intro line.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var mons: Dictionary = parsed.get("monsters", parsed) if parsed is Dictionary else {}
	var out := {}
	var ids: Array = mons.keys()
	ids.sort()
	for id in ids:
		var d = mons[id].get("dialogue", {}) if mons[id] is Dictionary else {}
		if d is Dictionary and d.get("intro", []) is Array and not (d.get("intro", []) as Array).is_empty():
			out[str(id)] = str(mons[id].get("name", id))
	return out


func _pc(job: String) -> Combatant:
	var pc := Combatant.new()
	pc.combatant_name = job.capitalize()
	pc.is_alive = true
	pc.max_hp = 40
	pc.current_hp = 40
	pc.job = JobSystem.get_job(job)
	add_child_autofree(pc)
	return pc


func test_every_cutscene_portrait_is_resampled_into_its_box() -> void:
	var faces := _authored()
	assert_gt(faces.size(), 80, "CONTROL: the authored portraits were found (%d)" % faces.size())
	var box = CutsceneScript.new()
	add_child_autofree(box)
	var bad: Array = []
	for id in faces:
		box.show_dialogue([{"speaker": str(id), "text": "x", "theme": "narrator", "portrait": str(id)}])
		var why := _judge(str(id), box._portrait_image, faces[id])
		if why != "":
			bad.append(why)
	assert_eq(bad, [], "%d of %d cutscene portraits drawn dropped, not resampled: %s" % [bad.size(), faces.size(), str(bad.slice(0, 6))])


func test_a_battle_leader_s_portrait_is_resampled_into_its_box() -> void:
	var art = CutsceneScript.new()
	autofree(art)
	var bad: Array = []
	for job in STARTERS:
		var source: Texture2D = art.portrait_art(job)
		assert_not_null(source, "CONTROL: the %s has portrait art" % job)
		var box = BattleScript.new()
		add_child_autofree(box)
		box.set_party([_pc(job)])
		box.show_boss_intro("Test Boss", ["Hero: We are not leaving."])
		var why := _judge(job, box._portrait_image, source)
		if why != "":
			bad.append(why)
	assert_eq(bad, [], "battle leader portraits drawn dropped, not resampled: %s" % str(bad))


func test_every_boss_s_own_line_shows_its_face_resampled() -> void:
	var art = CutsceneScript.new()
	autofree(art)
	var bosses := _intro_bosses()
	var bad: Array = []
	var judged := 0
	for id in bosses:
		var source: Texture2D = art.monster_art(id)
		if source == null:
			continue
		var box = BattleScript.new()
		add_child_autofree(box)
		box.set_party([_pc("fighter")])
		box.show_boss_intro(bosses[id], ["%s: You will not pass." % bosses[id]], id)
		if _minified(source, box._portrait_image):
			judged += 1
			var why := _judge(id, box._portrait_image, source)
			if why != "":
				bad.append(why)
		box.queue_free()
	assert_gt(judged, 40, "CONTROL: the boss faces drawn smaller than their art were judged (%d)" % judged)
	assert_eq(bad, [], "%d boss faces drawn dropped, not resampled: %s" % [bad.size(), str(bad.slice(0, 6))])


func test_a_face_at_or_under_the_box_keeps_its_pixels() -> void:
	## A procedural face is drawn at the box size and the artist's 128px monster sheets cut busts smaller than the box:
	## neither is shrunk, so neither is touched.
	var art = CutsceneScript.new()
	autofree(art)
	var cell := Vector2(72, 72)
	var small: Texture2D = null
	for id in _intro_bosses():
		var t: Texture2D = art.monster_art(id)
		if t is AtlasTexture and t.get_width() <= cell.x and t.get_height() <= cell.y:
			small = t
			break
	assert_not_null(small, "CONTROL: a boss bust no bigger than the box exists")
	if small != null:
		assert_eq(HybridSpriteLoader.fitted_portrait(small, cell), small, "a bust under the box keeps its pixels")
	var drawn := ImageTexture.create_from_image(Image.create(72, 72, false, Image.FORMAT_RGBA8))
	assert_eq(HybridSpriteLoader.fitted_portrait(drawn, cell), drawn, "a drawn face keeps its pixels")


func test_resampling_leaves_the_source_art_intact() -> void:
	## The headless renderer returns a texture's own image from get_image(): a fit that resized it in place shrank the
	## 256px source to 72px for every later reader, and made this file's own judge compare the fit against itself.
	## A box size nothing else asks for, so the fit is computed here rather than served from an earlier arm's cache.
	var faces := _authored()
	var tex: Texture2D = faces.values()[0]
	var before: Vector2i = tex.get_image().get_size()
	assert_eq(before, Vector2i(tex.get_size()), "CONTROL: the source's image matches its texture before the fit")
	var fitted: Texture2D = HybridSpriteLoader.fitted_portrait(tex, Vector2(50, 50))
	assert_ne(fitted, tex, "CONTROL: a shrunk face is fitted")
	assert_eq(tex.get_image().get_size(), before, "fitting a portrait must not resize the source art")


func test_a_bust_cut_for_each_battle_is_fitted_once() -> void:
	## BattleDialogue cuts a new AtlasTexture per box, so a cache keyed by the texture object would grow by one 72px
	## image per boss intro for the whole session. Same sheet, same region: one fit.
	var a = CutsceneScript.new()
	var b = CutsceneScript.new()
	autofree(a)
	autofree(b)
	var id := ""
	for boss in _intro_bosses():
		var t: Texture2D = a.monster_art(boss)
		if t is AtlasTexture and t.get_width() > 72:
			id = boss
			break
	assert_ne(id, "", "CONTROL: a boss bust bigger than the box exists")
	var first: Texture2D = a.monster_art(id)
	var second: Texture2D = b.monster_art(id)
	assert_ne(first, second, "CONTROL: two boxes cut two bust objects")
	assert_eq(HybridSpriteLoader.fitted_portrait(first, Vector2(72, 72)), HybridSpriteLoader.fitted_portrait(second, Vector2(72, 72)),
		"the same bust must resolve to one fitted face")
