extends GutTest

## Sprite audit 2026-11-11 (cowir-sprites 23682 S4, cowir-main ruling 23683). 70 legacy AI sheets (17 early-game ones in
## tip 1, 53 from the later worlds in tip 2) hold a different creature in almost every frame: the unassuming dog attacked
## as a husky, was hit as a bulldog and died as a corgi. Each frame is a legal 256 px frame, so nothing failed. Until those
## sheets are redrawn, a sheet on this REVIEWED list plays its idle picture for attack, hit and dead (manifest only; the
## engine's lunge, knockback and death fade carry the motion), and this guard keeps every frame it shows on that one
## creature. The list is by eye, not by tier: a sheet whose other frames ARE the same creature stays off it, and so does
## the ghost, whose wisp death is the design. Re-review an entry when its art is redrawn.
## 2026-11-18: 17 of the 70 were redrawn from their own idle (paid S4 motion regen, installed at $0) and moved to
## REDRAWN_BY_MOTION_REGEN, where every range ships only on an eye pin plus a colour floor against the idle.

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
	## cowir-sprites 2026-11-18: the 17 REDRAWN sheets below, every range looked at in tools/install_motion_regen.py's install.
	"troll/idle": "cad0fd4d8b7afbe5169ada459c9c62210532367bfce31b486ac20cfb5ece8cdb",
	"troll/attack": "2acd9e79198fdc3a1169a46b02b3963dc51c1f66a8be5dab3708fa154762bce4",
	"troll/hit": "4f025fcfe921aefdafb2f3b43b1d297ec175ba7ade6eeb3d4f8a72ed0e699c3f",
	"troll/dead": "856bcf7760d5f229be2b88c289bab102ba0e5548d5470c94c44bd0fca16ae3ea",
	"unassuming_dog/idle": "5889a4cf692b754354b7b84d0cf168d0ab65da49a17c71cf2b25efc52fdd2818",
	"unassuming_dog/attack": "28eb64bb77e60c597f26e647e610b5ab86f78bc65f3c953b53d1bb1f4c6661c7",
	"unassuming_dog/hit": "9d7ef81e3ac1fb18be766dd640da800da011cb23cb2a865c3741909fbab90a73",
	"unassuming_dog/dead": "0f90497fa2f0d13be7cdecddafc6bfa7e50b034381485fe3cc18f63f14f89877",
	"cave_rat_king/idle": "542f69dacbe9056c8fb3bf2c607f9709e03aa98ea80df600975b175168a7d013",
	"cave_rat_king/attack": "f56203f55e9e051d72ce63fd98f4f00079602d5d9a2062e0ee08ed5f175b4526",
	"cave_rat_king/hit": "e6687fb4fbd5675cd988865390a6ffd81a272592bc43f0a51986fbf6a327c105",
	"cave_rat_king/dead": "500525edb457b5246a21e61a1516706c8fc99fc3cf449c99fdf51767e32828e7",
	"snake/idle": "afd9df8a49144dbc4574bfd8f63d23016ba23e362fbcdfa0a08fbe0253464b98",
	"snake/attack": "5a91ac4e8c00723915d019a17c58ef499f24d2c4c696229439645b23798d94ca",
	"snake/hit": "02dd9e30c1a5f1e013d9912bbd16053a34b7cf46f19c177285691413556d88b4",
	"snake/dead": "4f8e7cb4f2027f0c913403c8b997ef56dab9f7b53d0206d2a4da3a248595ddc8",
	"viper/idle": "15b2463a814427f6e0889ee487c3acb0721b0e033992dbbbeeb7843f17f94a1f",
	"viper/attack": "2231c0e1a0bb4218fe97925e055504854e5340dbb15db65fa3210e6ac9e98d21",
	"viper/hit": "cb0c68d5a2c83db817dcec84000dd12ead7f6f2b49dd349aefd0016c6954571d",
	"viper/dead": "7deaca9c39642b9ad6c4d30198a92e6776133f3509fe701fad0f66c2e9d508b8",
	"toxic_sludge/idle": "8436b44c564a75ac3f60858ce0612f9606ec3d8936906d4b0f1006bf73c312d6",
	"toxic_sludge/attack": "fcb0cf1f6ea3fbd1d0863e67168eed2c1caae4c1ad7c71bb8d525f776b6d1411",
	"toxic_sludge/hit": "69c6bee75fc1b555878c233fe2e7eeac75d0aceb81f531bfdf00f7ef5733de9e",
	"toxic_sludge/dead": "a69f1cae97f54bd472f2bd61d29814603974bbceaeaa9fa40cd9b2342bc614ad",
	"cranky_lady/idle": "c13800cee4f2af5b463aedb408dc3cbcf2ae13d5e90af56915421fa9c327a955",
	"cranky_lady/attack": "e9c9dd8cbbd9cd66d72ee0ba63c8bd3ba18059d7bb804e9f05036e669fbfbe16",
	"cranky_lady/hit": "700679aaf7b89232f21cbe9c37888d9c46ca2dc1e13924d1502a74323c06ffa0",
	"cranky_lady/dead": "634dda440c2e281215ae14948fd5fa8750f9ed4094b95adce58876a262b6778b",
	"skate_punk/idle": "f6af265466976f3bff2866aa95f3eb7d75c98fd5422148bae82a8372953c79c8",
	"skate_punk/attack": "d8dccfa2ea6feb75fee3b3be49b7d66a6a4c16d313d7a48f8b7c8fb9f0c565bb",
	"skate_punk/hit": "1c079bf857c09712c87e67092c7b081aa81f013a03dcd17b38ef48868bc74d11",
	"skate_punk/dead": "2057d50c01575497e40d79275e5d71abc52c823c745bfda49bf4a4e2eaa70def",
	"new_age_retro_hippie/idle": "9e9e24383bfa96707360e4d32c36ed1fca9705c4f3171259aa131685b217e877",
	"new_age_retro_hippie/attack": "5053b129cb8ef852295e687f58c7790d99fce9a3f5d382db0f54252872784743",
	"new_age_retro_hippie/hit": "c891807ee7305b46cf3a5560b0a4d5ab9e85fe803583b7fd3f415e8af5c671d6",
	"new_age_retro_hippie/dead": "b40adb2aa898993236d7749b1e08892f483cfcc07221c1fd3449bff36817a55c",
	"treasure_mimic/idle": "b8a0b4261f05bd8eea32b5f5a4ece400e03895259be97628a2fbf4f2ce436960",
	"treasure_mimic/attack": "5425448ac6f5d72bc4e95ccda27d77791e2e5ffec21977fb8f2ff0dc2c76526d",
	"treasure_mimic/hit": "a4c482e245b806a7647b0e7544540536365e27a21a93a2b95dd88374b69a5ae0",
	"treasure_mimic/dead": "de80027a8c8f5bbc53435a1c88d688cbf20043dbd06296e21bd247200edef9ea",
	"fungoid/idle": "e730226e617e428e1a077a603d1246cbfb16ae14482d2b0978c1e8bfc2342997",
	"fungoid/attack": "81f1ebe440e5e67156f245abdb12c47f51eb15c8acae1c4ba91fd23d66c6e2d5",
	"fungoid/hit": "3572e1a381426c3099e584623c70c519d803bc486fe0fa6e6ba074f8dad5caf4",
	"fungoid/dead": "2d244f96e93564017e7b233dedacd9a4901bb624ba4b270705eabca10d2675e7",
	"diseased_rat/idle": "22b4339de26f5562bffcdbeaedacee3bd4720790b84e02fd3ba502ec5ac78192",
	"diseased_rat/attack": "2ba45e153d11bceef803484d8ea3c6573920aa64d504c08229b133938d93b773",
	"diseased_rat/hit": "e19757da6039488af10babbdfa52c4afd3c667641eaa14b2372adc2fad9f9efd",
	"diseased_rat/dead": "50565f16e72b8736e164a0d09b8b55a8ac0211b8b7eb68a4660c7a0107354e50",
	"elder_mushroom/idle": "ac12bfde68f8e0f0969d6ae4120473f94d660de734fb569deba2dc129bc0a7f8",
	"elder_mushroom/attack": "51d8f1df72586c7aed110f30a7649c2686e2d9d674b48c5b8cfcfa925f2f925d",
	"elder_mushroom/hit": "c23acfc74eb4ca666461d42d8641ca43f45414ae13b6ce866a60360b2cb28d13",
	"elder_mushroom/dead": "3a477045a03567da332415ad1de1eefc03c750420f3558720064d8845e4d7470",
	"giant_bat/idle": "7df079d95d63464a221c730bc0928c70435eb51464198edbff62e54cf7c9b1e0",
	"giant_bat/attack": "7ee312133bfd1249f15fd74ced43902beb0542b2cb222ac77f60c2507d060317",
	"giant_bat/hit": "017dbaef8d917112a73afafb3d481cee3ed8c34702da2c60c4ba63a40b256dbd",
	"giant_bat/dead": "71a3a98cf10f426a27145e39021d04619544e97de5749186f9c9c5f1ed4746c0",
	"blood_wolf_alpha/idle": "1dcc076a1d577a25aa271bd5e1113fd937639ce00d73b9388146b2f9aab5548c",
	"blood_wolf_alpha/attack": "8f12f5953c19bb77b7b9304340fe3f30d950f690f047d01ea57693558b8f160a",
	"blood_wolf_alpha/hit": "9ea9cb27ce142ebf5d12d5defffae3a2cc9910ba10a74361b4e48af6ccc44119",
	"blood_wolf_alpha/dead": "467b0b8ffe358f313cb9f455c26fcef811f20ecc1a913fcf8c4eff2e48f57f14",
	"steam_rat/idle": "0718a8b046a162457925dc676dc564e1501213dd62e4afd6c6fec602d41bfed4",
	"steam_rat/attack": "ce7fdb8e6936263dbc47d991b8619e7739e282ff3f5992992b3d40147d3d60bf",
	"steam_rat/hit": "60d296b422ee82727d912805eac79ea5e9240e935618d481d3e40381c52cebd4",
	"steam_rat/dead": "1547861afc571d3889c4b9fb9a49343e6f2ded7d6c323356f0c0d0a16fe970ac",
	"conveyor_gremlin/idle": "dd99ea87887094adb6ce45bc07ffda558d3670f8c9c71bca2d46f0c4cededd4e",
	"conveyor_gremlin/attack": "bcb2be3f69bcd7cffa02d7a99f25d811515d898e8c867ef4d9f7b819df843ef4",
	"conveyor_gremlin/hit": "a72ab73ce9144f0687ebc3a77a00e3506a6562fa59563dfe420918007a737cd1",
	"conveyor_gremlin/dead": "b545040fd4b99f20fc8958cf133cacd9b4b5b34f9ce9801b050010f408d9ea13",
}
## Redrawn from their own idle by the paid S4 motion regen (tools/install_motion_regen.py, $0): off the repoint list, every range eye-pinned.
const REDRAWN_BY_MOTION_REGEN := [
	"troll", "unassuming_dog", "cave_rat_king", "snake", "viper", "toxic_sludge", "cranky_lady", "skate_punk",
	"new_age_retro_hippie", "treasure_mimic", "fungoid", "diseased_rat", "elder_mushroom", "giant_bat",
	"blood_wolf_alpha", "steam_rat", "conveyor_gremlin",
]
## A redrawn frame's colours against its idle: measured min 0.697 (the thin snake's lunge); another species scores lower.
const REDRAWN_COLOUR_FLOOR := 0.65
const ONE_CREATURE_BY_REPOINT := [
	"adaptive_slime", "assembly_line_automaton", "brass_golem", "castle_warden", "clockwork_sentinel", "cog_swarm",
	"corrupted_guardian", "corrupted_sprite", "crystal_golem", "cursed_armor", "data_wraith", "elemental", "empty_set",
	"firewall_sentinel", "forgotten_variable", "glitch_entity", "ice_wolf", "ironback_beetle",
	"masterite_arbiter_abstract", "masterite_arbiter_futuristic", "masterite_arbiter_industrial",
	"masterite_arbiter_medieval", "masterite_arbiter_suburban", "masterite_curator_futuristic",
	"masterite_curator_industrial", "masterite_curator_medieval", "masterite_curator_suburban",
	"masterite_tempo_futuristic", "masterite_tempo_industrial", "masterite_tempo_medieval", "masterite_tempo_suburban",
	"masterite_warden_abstract", "masterite_warden_futuristic", "masterite_warden_industrial",
	"masterite_warden_medieval", "masterite_warden_suburban", "memory_leak", "meta_knight", "mushroom", "null_entity",
	"optimization_itself", "permadeath_reaper", "pipe_phantom", "recursive_loop", "rogue_process", "rust_elemental",
	"script_error", "shadow_knight", "shift_supervisor", "specter", "spiteful_crow", "the_absence", "the_margin",
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
	assert_false(why.contains("colour"), "CONTROL: his own hit frame 4 is a rat king in his palette and passes colour (%s)" % why)
	assert_string_contains(why, "looked", "so the eye pin is what refuses a same-palette swap")
	assert_ne(_motion_refusal("cave_rat_king", "dead", img, entry, int(r["start"])), "",
		"dead keeps the overlap floor; only motion ships on eye + colour")


func test_a_redrawn_monster_ships_only_the_frames_someone_looked_at() -> void:
	var sheets := _sheets()
	var unseen: Array = []
	var off_colour: Array = []
	for key in REDRAWN_BY_MOTION_REGEN:
		assert_true(sheets.has(key), "CONTROL: %s is a monster sheet" % key)
		assert_false(key in ONE_CREATURE_BY_REPOINT, "%s is redrawn, so it is off the repoint list" % key)
		if not sheets.has(key):
			continue
		var entry: Dictionary = sheets[key]
		var img := _image(entry)
		var fw := int(entry["frame_width"])
		var idle: Dictionary = entry["animations"]["idle"]
		for anim in ["idle", "attack", "hit", "dead"]:
			var r: Dictionary = entry["animations"][anim]
			assert_eq(int(r["end"]) - int(r["start"]), 1, "%s %s plays two frames again, not the idle picture" % [key, anim])
			if str(EYE_REVIEWED.get("%s/%s" % [key, anim], "")) != _range_hash(img, fw, r):
				unseen.append("%s/%s" % [key, anim])
			for i in range(int(r["start"]), int(r["end"]) + 1):
				var best := 0.0
				for j in range(int(idle["start"]), int(idle["end"]) + 1):
					best = maxf(best, colour_match(_colour_hist(img, fw, i), _colour_hist(img, fw, j)))
				if best < REDRAWN_COLOUR_FLOOR:
					off_colour.append("%s frame %d: %.3f" % [key, i, best])
	assert_eq(unseen, [], "redrawn ranges whose pixels nobody looked at (re-pin after an eye check): %s" % str(unseen))
	assert_eq(off_colour, [], "redrawn frames off their idle's colours: %s" % str(off_colour))


func test_a_species_swap_into_a_redrawn_range_reds_on_both_checks() -> void:
	var troll: Dictionary = _sheets()["troll"]
	var dog: Dictionary = _sheets()["unassuming_dog"]
	var img := _image(troll)
	var r: Dictionary = troll["animations"]["attack"]
	assert_eq(str(EYE_REVIEWED["troll/attack"]), _range_hash(img, 256, r), "CONTROL: the shipped troll attack is the pinned one")
	img.blit_rect(_image(dog), Rect2i(0, 0, 256, 256), Vector2i(int(r["start"]) * 256, 0))
	assert_ne(str(EYE_REVIEWED["troll/attack"]), _range_hash(img, 256, r), "a dog in the troll's attack breaks the eye pin")
	var best := 0.0
	for j in range(int(troll["animations"]["idle"]["start"]), int(troll["animations"]["idle"]["end"]) + 1):
		best = maxf(best, colour_match(_colour_hist(img, 256, int(r["start"])), _colour_hist(img, 256, j)))
	assert_lt(best, REDRAWN_COLOUR_FLOOR, "and falls under the colour floor (%.3f)" % best)
