extends GutTest

## Mortimer, the black-magic dealer, was a FLOATING FACE in his own shop: his generated portrait held a face and a few
## wisps of hair and no neck, shoulders or robe (4% of its lower third was drawn; the other keepers hold 46-83%).
## A keeper's portrait is a bust: the bottom of the frame holds their shoulders.

const KEEPERS := "res://assets/sprites/portraits/keepers/"
## Share of the lower third that must be drawn. The slimmest real bust (Lenora) measures 0.46.
const MIN_BODY := 0.30


func body_share(img: Image) -> float:
	## Share of the image's lower third at alpha >= 0.5.
	var top := img.get_height() * 2 / 3
	var drawn := 0
	for y in range(top, img.get_height()):
		for x in img.get_width():
			drawn += 1 if img.get_pixel(x, y).a >= 0.5 else 0
	return float(drawn) / maxf(1.0, float((img.get_height() - top) * img.get_width()))


func _keepers() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(KEEPERS):
		if f.ends_with(".png"):
			out.append(f)
	out.sort()
	return out


func test_every_keeper_portrait_has_shoulders() -> void:
	var keepers := _keepers()
	assert_gt(keepers.size(), 3, "CONTROL: the keeper portraits were found (%d)" % keepers.size())
	var bad: Array = []
	for f in keepers:
		var img := Image.load_from_file(ProjectSettings.globalize_path(KEEPERS + f))
		img.convert(Image.FORMAT_RGBA8)
		var share := body_share(img)
		if share < MIN_BODY:
			bad.append("%s: %.2f of the lower third is drawn" % [f, share])
	assert_eq(bad, [], "%d keeper(s) are a face with no body: %s" % [bad.size(), str(bad)])


func test_the_measure_tells_a_bust_from_a_floating_face() -> void:
	var face := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	face.fill_rect(Rect2i(20, 10, 24, 28), Color.WHITE)
	assert_lt(body_share(face), MIN_BODY, "a face alone has no body")
	var bust := face.duplicate() as Image
	bust.fill_rect(Rect2i(6, 40, 52, 24), Color.WHITE)
	assert_gt(body_share(bust), MIN_BODY, "a face over shoulders is a bust")
