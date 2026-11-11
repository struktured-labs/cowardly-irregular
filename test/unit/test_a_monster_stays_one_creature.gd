extends GutTest

## Sprite audit 2026-11-11 (cowir-sprites 23682 S4, cowir-main ruling 23683). About 48 legacy AI sheets hold a different
## creature in almost every frame: the unassuming dog attacked as a husky, was hit as a bulldog and died as a corgi.
## Each frame is a legal 256 px frame, so nothing failed. Until those sheets are redrawn, a sheet on this REVIEWED list
## plays its idle picture for attack, hit and dead (manifest only; the engine's lunge, knockback and death fade carry the
## motion), and this guard keeps every frame it shows on that one creature. The list is by eye, not by tier: a sheet
## whose other frames ARE the same creature stays off it. Re-review an entry when its art is redrawn.

## A live frame must overlap one of its sheet's idle frames by at least this much (the idle guard's own floor).
const MIN_OVERLAP := 0.70
const ONE_CREATURE_BY_REPOINT := [
	"unassuming_dog", "cave_rat_king", "troll", "snake", "viper", "toxic_sludge", "cranky_lady", "skate_punk",
	"new_age_retro_hippie", "treasure_mimic", "fungoid", "diseased_rat", "elder_mushroom", "giant_bat",
	"blood_wolf_alpha", "steam_rat", "conveyor_gremlin",
]


func _sheets() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return manifest["monster_sheets"]


func _masks(entry: Dictionary) -> Array:
	## One PackedByteArray per frame of the sheet: 1 where the pixel is solid.
	var img: Image = (load(str(entry["path"])) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fw := int(entry["frame_width"])
	var h := img.get_height()
	var d := img.get_data()
	var out: Array = []
	for i in range(img.get_width() / fw):
		var m := PackedByteArray()
		m.resize(fw * h)
		for y in h:
			for x in fw:
				m[y * fw + x] = 1 if d[(y * img.get_width() + i * fw + x) * 4 + 3] >= 128 else 0
		out.append(m)
	return out


static func overlap(a: PackedByteArray, b: PackedByteArray) -> float:
	var both := 0
	var either := 0
	for i in a.size():
		both += 1 if a[i] and b[i] else 0
		either += 1 if a[i] or b[i] else 0
	return float(both) / maxf(1.0, float(either))


func _best_idle_overlap(masks: Array, idle: Dictionary, i: int) -> float:
	var best := 0.0
	for j in range(int(idle["start"]), int(idle["end"]) + 1):
		best = maxf(best, overlap(masks[i], masks[j]))
	return best


func test_a_listed_monster_shows_one_creature_in_every_live_frame() -> void:
	var sheets := _sheets()
	var strays: Array = []
	var still_has_the_defect := 0
	for key in ONE_CREATURE_BY_REPOINT:
		assert_true(sheets.has(key), "CONTROL: %s is a monster sheet" % key)
		if not sheets.has(key):
			continue
		var entry: Dictionary = sheets[key]
		var masks := _masks(entry)
		var idle: Dictionary = entry["animations"]["idle"]
		var live := {}
		for anim in entry["animations"]:
			var r: Dictionary = entry["animations"][anim]
			for i in range(int(r["start"]), int(r["end"]) + 1):
				live[i] = true
				if _best_idle_overlap(masks, idle, i) < MIN_OVERLAP:
					strays.append("%s %s frame %d" % [key, anim, i])
		for i in masks.size():
			if not live.has(i) and _best_idle_overlap(masks, idle, i) < MIN_OVERLAP:
				still_has_the_defect += 1
				break
	## CONTROL: the other creatures are still in the PNGs, so naming one of those frames again would red the arm above.
	assert_eq(still_has_the_defect, ONE_CREATURE_BY_REPOINT.size(),
		"every listed sheet still holds an unused frame of another creature (a redrawn sheet comes OFF the list)")
	assert_eq(strays, [], "listed monsters that still turn into something else: %s" % str(strays))


func test_the_measure_sees_an_artist_monster_move() -> void:
	## CONTROL: the artist's bat really animates, so its attack is not its idle picture, and it is still one creature.
	var entry: Dictionary = _sheets()["bat"]
	var masks := _masks(entry)
	var a: Dictionary = entry["animations"]["attack"]
	var worst := 1.0
	for i in range(int(a["start"]), int(a["end"]) + 1):
		worst = minf(worst, _best_idle_overlap(masks, entry["animations"]["idle"], i))
	assert_lt(worst, 0.999, "the bat's attack differs from its idle (%.3f)" % worst)
