extends GutTest

## Sprite audit 2026-11-11 (cowir-sprites 23682 S4, cowir-main ruling 23683). 70 legacy AI sheets (17 early-game ones in
## tip 1, 53 from the later worlds in tip 2) hold a different creature in almost every frame: the unassuming dog attacked
## as a husky, was hit as a bulldog and died as a corgi. Each frame is a legal 256 px frame, so nothing failed. Until those
## sheets are redrawn, a sheet on this REVIEWED list plays its idle picture for attack, hit and dead (manifest only; the
## engine's lunge, knockback and death fade carry the motion), and this guard keeps every frame it shows on that one
## creature. The list is by eye, not by tier: a sheet whose other frames ARE the same creature stays off it, and so does
## the ghost, whose wisp death is the design. Re-review an entry when its art is redrawn.

## A live frame must overlap one of its sheet's idle frames by at least this much (the idle guard's own floor).
const MIN_OVERLAP := 0.70
## MOTION frames below that floor ship on EYE + COLOUR (struktured via cowir-main 25446, 2026-11-14): a real lunge overlaps
## its idle 45-55%. Idle and dead keep the overlap floor. COLOUR: the frame's colours match an idle frame's (3-bit-per-channel
## histogram intersection); measured 2026-11-14, the Rat King's own lunge scores 0.79-0.81 and the closest other listed species
## 0.717 against his idle. EYE: a lane looked at THOSE pixels, pinned by hash, so any pixel change needs a fresh look. Colour
## alone cannot refuse a swap here: his unused frames are other rat kings in his palette (frame 4 scores 0.827).
const OVERLAP_ONLY_ANIMS := ["idle", "dead"]
const COLOUR_BITS := 3
const COLOUR_FLOOR := 0.75
## "sheet/anim" -> sha256 of the range's RGBA (transparent pixels zeroed: the import's fix_alpha_border rewrites their RGB).
const EYE_REVIEWED := {
	## cowir-sprites 2026-11-14: sceptre wind-up, then an open-mouthed lunge; his crown, cape, sceptre and grey fur, facing the idle's way.
	"cave_rat_king/royal_spite": "ba78a6bb309b37d0ce43e4fbc5fdc8b9c48872b383f2521ce7578c093fc6eb8a",
}
const ONE_CREATURE_BY_REPOINT := [
	"unassuming_dog", "cave_rat_king", "troll", "snake", "viper", "toxic_sludge", "cranky_lady", "skate_punk",
	"new_age_retro_hippie", "treasure_mimic", "fungoid", "diseased_rat", "elder_mushroom", "giant_bat",
	"blood_wolf_alpha", "steam_rat", "conveyor_gremlin", "adaptive_slime", "assembly_line_automaton", "brass_golem",
	"castle_warden", "clockwork_sentinel", "cog_swarm", "corrupted_guardian", "corrupted_sprite", "crystal_golem",
	"cursed_armor", "data_wraith", "elemental", "empty_set", "firewall_sentinel", "forgotten_variable",
	"glitch_entity", "ice_wolf", "ironback_beetle", "masterite_arbiter_abstract", "masterite_arbiter_futuristic",
	"masterite_arbiter_industrial", "masterite_arbiter_medieval", "masterite_arbiter_suburban",
	"masterite_curator_futuristic", "masterite_curator_industrial", "masterite_curator_medieval",
	"masterite_curator_suburban", "masterite_tempo_futuristic", "masterite_tempo_industrial",
	"masterite_tempo_medieval", "masterite_tempo_suburban", "masterite_warden_abstract",
	"masterite_warden_futuristic", "masterite_warden_industrial", "masterite_warden_medieval",
	"masterite_warden_suburban", "memory_leak", "meta_knight", "mushroom", "null_entity", "optimization_itself",
	"permadeath_reaper", "pipe_phantom", "recursive_loop", "rogue_process", "rust_elemental", "script_error",
	"shadow_knight", "shift_supervisor", "specter", "spiteful_crow", "the_absence", "the_margin",
]


func _sheets() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return manifest["monster_sheets"]


func _image(entry: Dictionary) -> Image:
	var img: Image = (load(str(entry["path"])) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _masks(entry: Dictionary, img: Image = null) -> Array:
	## One PackedByteArray per frame of the sheet: 1 where the pixel is solid.
	if img == null:
		img = _image(entry)
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


func _colour_hist(img: Image, fw: int, i: int) -> PackedFloat32Array:
	var shift := 8 - COLOUR_BITS
	var h := PackedFloat32Array()
	h.resize(1 << (3 * COLOUR_BITS))
	var d := img.get_data()
	var n := 0
	for y in img.get_height():
		for x in fw:
			var o := (y * img.get_width() + i * fw + x) * 4
			if d[o + 3] < 128:
				continue
			h[((d[o] >> shift) << (2 * COLOUR_BITS)) | ((d[o + 1] >> shift) << COLOUR_BITS) | (d[o + 2] >> shift)] += 1.0
			n += 1
	for k in h.size():
		h[k] /= maxf(1.0, float(n))
	return h


static func colour_match(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var s := 0.0
	for k in a.size():
		s += minf(a[k], b[k])
	return s


func _range_hash(img: Image, fw: int, r: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for i in range(int(r["start"]), int(r["end"]) + 1):
		var d := img.get_region(Rect2i(i * fw, 0, fw, img.get_height())).get_data()
		for o in range(0, d.size(), 4):
			if d[o + 3] == 0:
				d[o] = 0
				d[o + 1] = 0
				d[o + 2] = 0
		ctx.update(d)
	return ctx.finish().hex_encode()


## Why frame i of `anim` may not ship, given it is under MIN_OVERLAP; "" = it ships on eye + colour.
func _motion_refusal(key: String, anim: String, img: Image, entry: Dictionary, i: int) -> String:
	if anim in OVERLAP_ONLY_ANIMS:
		return "under the overlap floor, and %s is not a motion" % anim
	var fw := int(entry["frame_width"])
	var idle: Dictionary = entry["animations"]["idle"]
	var mine := _colour_hist(img, fw, i)
	var best := 0.0
	for j in range(int(idle["start"]), int(idle["end"]) + 1):
		best = maxf(best, colour_match(mine, _colour_hist(img, fw, j)))
	if best < COLOUR_FLOOR:
		return "colour %.3f under %.2f" % [best, COLOUR_FLOOR]
	if str(EYE_REVIEWED.get("%s/%s" % [key, anim], "")) != _range_hash(img, fw, entry["animations"][anim]):
		return "nobody has looked at these pixels (no EYE_REVIEWED pin matches)"
	return ""


func test_a_listed_monster_shows_one_creature_in_every_live_frame() -> void:
	var sheets := _sheets()
	var strays: Array = []
	var still_has_the_defect := 0
	for key in ONE_CREATURE_BY_REPOINT:
		assert_true(sheets.has(key), "CONTROL: %s is a monster sheet" % key)
		if not sheets.has(key):
			continue
		var entry: Dictionary = sheets[key]
		var img := _image(entry)
		var masks := _masks(entry, img)
		var idle: Dictionary = entry["animations"]["idle"]
		var live := {}
		for anim in entry["animations"]:
			var r: Dictionary = entry["animations"][anim]
			for i in range(int(r["start"]), int(r["end"]) + 1):
				live[i] = true
				if _best_idle_overlap(masks, idle, i) < MIN_OVERLAP:
					var why := _motion_refusal(key, anim, img, entry, i)
					if why != "":
						strays.append("%s %s frame %d: %s" % [key, anim, i, why])
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


func test_a_motion_frame_ships_on_eye_and_colour_and_a_swap_still_reds() -> void:
	var entry: Dictionary = _sheets()["cave_rat_king"]
	var img := _image(entry)
	var masks := _masks(entry, img)
	var r: Dictionary = entry["animations"]["royal_spite"]
	for i in range(int(r["start"]), int(r["end"]) + 1):
		assert_lt(_best_idle_overlap(masks, entry["animations"]["idle"], i), MIN_OVERLAP,
			"CONTROL: royal_spite frame %d is a real lunge, under the overlap floor, so eye + colour is what passes it" % i)
		assert_eq(_motion_refusal("cave_rat_king", "royal_spite", img, entry, i), "", "the reviewed lunge ships")
	var at := int(r["start"]) * 256
	var dog: Dictionary = _sheets()["unassuming_dog"]
	var swapped := img.duplicate() as Image
	swapped.blit_rect(_image(dog), Rect2i(int(dog["animations"]["idle"]["start"]) * 256, 0, 256, 256), Vector2i(at, 0))
	assert_string_contains(_motion_refusal("cave_rat_king", "royal_spite", swapped, entry, int(r["start"])), "colour",
		"a different species' frame in the lunge must red on colour")
	var own_kin := img.duplicate() as Image
	own_kin.blit_rect(img, Rect2i(4 * 256, 0, 256, 256), Vector2i(at, 0))
	var why := _motion_refusal("cave_rat_king", "royal_spite", own_kin, entry, int(r["start"]))
	assert_false(why.contains("colour"), "CONTROL: his unused frame 4 is another rat king in his palette and passes colour (%s)" % why)
	assert_string_contains(why, "looked", "so the eye pin is what refuses a same-palette swap")
	assert_ne(_motion_refusal("cave_rat_king", "dead", img, entry, int(r["start"])), "",
		"dead keeps the overlap floor; only motion ships on eye + colour")
