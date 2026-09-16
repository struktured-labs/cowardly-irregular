extends GutTest

## A theme's `portrait_bg` is a mood colour, and DARK art on a near-black ground has nothing to read
## against. Measured 2026-09-16 at the rendered 72px cell — mean luminance of opaque pixels, and mean
## |ΔL| against the narrator ground, which most lines use:
##
##   masterite_warden_futuristic  bust  0.159 / 0.108      cleric  PNG  0.728 / 0.676
##   mage                          PNG  0.203 / 0.154      elder   PNG  0.533 / 0.481
##   rogue                         PNG  0.199 / 0.147
##
## ⛔ The darkest three are one sheet bust and TWO HAND-DRAWN PORTRAITS. So this is NOT a bust
## problem (my own earlier framing) and NOT a crop problem (cowir-sprites measured three tighter
## crops, all worse on the sheet that prompted it). It is dark art on a dark ground, and it predates
## the busts by however long the Mage has had a portrait.

const DialogueScript = preload("res://src/cutscene/CutsceneDialogue.gd")
const NARRATOR_BG := Color(0.05, 0.05, 0.08)
const CELL := 72

var _box: Node


func before_each() -> void:
	_box = DialogueScript.new()
	add_child_autofree(_box)
	_box.show_dialogue([{"speaker": "x", "text": "x", "theme": "narrator", "portrait": "narrator"}])


func _flat(lum: float, fill: float = 0.5) -> Texture2D:
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rows: int = int(float(CELL) * fill)
	for y in rows:
		for x in CELL:
			img.set_pixel(x, y, Color(lum, lum, lum, 1.0))
	return ImageTexture.create_from_image(img)


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Mean |ΔL| between a texture's opaque pixels and a ground — the legibility number, independent of
## the implementation's own threshold.
func _contrast(tex: Texture2D, bg: Color) -> float:
	var img: Image = tex.get_image()
	var cell := img.duplicate()
	cell.convert(Image.FORMAT_RGBA8)
	cell.resize(CELL, CELL, Image.INTERPOLATE_NEAREST)
	var n: int = 0
	var total: float = 0.0
	for y in CELL:
		for x in CELL:
			var c: Color = cell.get_pixel(x, y)
			if c.a < 0.5:
				continue
			n += 1
			total += absf(_lum(c) - _lum(bg))
	return (total / float(n)) if n > 0 else 0.0


func test_dark_art_gets_the_lifted_ground() -> void:
	var dark := _flat(0.12)
	var ground: Color = DialogueScript.portrait_ground(dark, NARRATOR_BG)
	assert_ne(ground, NARRATOR_BG, "dark art must not be left on the theme's near-black ground")
	assert_gt(_contrast(dark, ground), _contrast(dark, NARRATOR_BG),
		"and the ground it gets must be MORE legible than the one it left — relationship, not a colour")


func test_bright_art_keeps_its_theme() -> void:
	var bright := _flat(0.78)
	assert_eq(DialogueScript.portrait_ground(bright, NARRATOR_BG), NARRATOR_BG,
		"bright art already reads on the theme's ground; the mood colour stays")
	var themed := Color(0.15, 0.15, 0.35)
	assert_eq(DialogueScript.portrait_ground(bright, themed), themed,
		"whatever the theme's colour is")


## CONTROL: the fixtures must actually differ in luminance, or both arms above are free.
func test_control_the_fixtures_differ_in_luminance() -> void:
	var dark: float = DialogueScript.portrait_mean_luminance(_flat(0.12))
	var bright: float = DialogueScript.portrait_mean_luminance(_flat(0.78))
	assert_gt(bright - dark, 0.4, "the two fixtures must sit far apart (%.2f vs %.2f)" % [dark, bright])


## The rule can never make a frame worse than the theme already served it — that is the property that
## replaces a threshold, and the one that keeps 29 portraits on the colour they were authored against.
func test_the_chosen_ground_is_never_worse_than_the_theme() -> void:
	for lum in [0.05, 0.12, 0.2, 0.28, 0.33, 0.4, 0.55, 0.78, 0.95]:
		var tex := _flat(float(lum))
		var themed: float = _contrast(tex, NARRATOR_BG)
		var chosen: float = _contrast(tex, DialogueScript.portrait_ground(tex, NARRATOR_BG))
		assert_gte(chosen, themed - 0.001,
			"art at luminance %.2f: the chosen ground (%.3f) must not read worse than the theme (%.3f)" % [lum, chosen, themed])


## Transparency must not count as dark: a sparse figure of BRIGHT pixels is bright.
func test_a_sparse_bright_figure_is_not_read_as_dark() -> void:
	var sparse := _flat(0.8, 0.08)
	assert_eq(DialogueScript.portrait_ground(sparse, NARRATOR_BG), NARRATOR_BG,
		"luminance is measured over the OPAQUE pixels; 8%% coverage of bright ink is still bright")


## THE CORPUS: every authored portrait must clear a legibility floor on the ground it actually gets.
func test_every_authored_portrait_clears_a_legibility_floor() -> void:
	var ids: Dictionary = {}
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir)
	if dir == null:
		return
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
				if it is Dictionary:
					ids[str(it.get("portrait", it.get("theme", "narrator")))] = true
	assert_gt(ids.size(), 20, "PRECONDITION: the corpus must load")
	var lifted: Array = []
	var worst: float = 99.0
	var worst_id: String = ""
	for id in ids.keys():
		var tex: Texture2D = _box._create_portrait(str(id))
		if tex == null:
			continue
		var ground: Color = DialogueScript.portrait_ground(tex, NARRATOR_BG)
		var c: float = _contrast(tex, ground)
		if ground != NARRATOR_BG:
			lifted.append(str(id))
		if c < worst:
			worst = c
			worst_id = str(id)
	gut.p("portraits lifted onto a ground: %d %s · worst contrast %.3f (%s)" % [lifted.size(), str(lifted), worst, worst_id])
	assert_gt(worst, 0.12,
		"%s reads at %.3f against the ground it gets — under the floor the Warden was at (0.108)" % [worst_id, worst])
	# ANTI-VACUITY: at least one authored portrait must be dark enough to need the lift, else this
	# file guards a rule nothing exercises.
	assert_gt(lifted.size(), 0,
		"no authored portrait triggered the lift — the corpus no longer exercises the rule this defends")


## An unreadable texture keeps the theme, and nothing throws.
func test_an_unreadable_portrait_keeps_the_theme() -> void:
	var ph := PlaceholderTexture2D.new()
	ph.size = Vector2(CELL, CELL)
	assert_eq(DialogueScript.portrait_ground(ph, NARRATOR_BG), NARRATOR_BG,
		"no readable pixels means no judgement to make; the mood colour stands")
	assert_eq(DialogueScript.portrait_ground(null, NARRATOR_BG), NARRATOR_BG, "and null must not throw")


## The ground is applied where the ART is known, not at theme time — the box is built first.
func test_the_live_box_applies_the_ground_to_its_own_portrait() -> void:
	_box.show_dialogue([{"speaker": "The Warden", "text": "You were not meant to read this room.",
		"theme": "narrator", "portrait": "masterite_warden_futuristic"}])
	var tex: Texture2D = _box._portrait_image.texture
	assert_not_null(tex, "PRECONDITION: the Warden must resolve to a texture")
	if tex == null:
		return
	assert_eq(_box._portrait_bg.color, DialogueScript.portrait_ground(tex, _box._portrait_theme_bg),
		"the live frame's ground must be the one the rule picks for the art it is showing")
	_box.show_dialogue([{"speaker": "Cleric", "text": "Bright.", "theme": "cleric", "portrait": "cleric"}])
	assert_eq(_box._portrait_bg.color, _box._portrait_theme_bg,
		"and a bright portrait's frame goes back to its theme colour, not the last speaker's ground")
