extends GutTest

## The shopkeeper's dialogue portrait had a SEE-THROUGH V in his chest: his white shirt was keyed out with the white
## backdrop, and it ran to the bust's lower edge, so no hole enclosed it and the eye-white repair never saw it.
## Between the two halves of his vest the dialogue panel showed through (41% of his bust's lowest rows were clear).

const PORTRAIT := "res://assets/sprites/portraits/npcs/shopkeeper.png"
const ROWS := 12


func open_share(img: Image) -> float:
	## Mean share of clear pixels between the outermost drawn pixels, over the bust's lowest ROWS drawn rows.
	var last := -1
	for y in range(img.get_height() - 1, -1, -1):
		for x in img.get_width():
			if img.get_pixel(x, y).a >= 0.5:
				last = y
				break
		if last >= 0:
			break
	if last < 0:
		return 1.0
	var total := 0.0
	var rows := 0
	for y in range(maxi(0, last - ROWS + 1), last + 1):
		var lo := -1
		var hi := -1
		var drawn := 0
		for x in img.get_width():
			if img.get_pixel(x, y).a >= 0.5:
				lo = x if lo < 0 else lo
				hi = x
				drawn += 1
		if lo < 0:
			continue
		total += 1.0 - float(drawn) / float(hi - lo + 1)
		rows += 1
	return total / maxf(1.0, float(rows))


func test_the_shopkeepers_chest_is_not_see_through() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(PORTRAIT))
	assert_not_null(img, "CONTROL: the shopkeeper's portrait is on disk")
	img.convert(Image.FORMAT_RGBA8)
	assert_lt(open_share(img), 0.02, "the panel shows through %.2f of the shopkeeper's chest" % open_share(img))


func test_the_measure_tells_an_open_vest_from_a_closed_one() -> void:
	var open := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	open.fill_rect(Rect2i(4, 30, 18, 30), Color.RED)
	open.fill_rect(Rect2i(42, 30, 18, 30), Color.RED)
	assert_gt(open_share(open), 0.3, "two vest halves with nothing between them are open")
	var closed := open.duplicate() as Image
	closed.fill_rect(Rect2i(22, 30, 20, 30), Color.WHITE)
	assert_lt(open_share(closed), 0.02, "a shirt between them closes the chest")
