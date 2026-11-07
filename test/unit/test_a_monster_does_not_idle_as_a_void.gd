extends GutTest

## Seventeen legacy monster sheets idled as a slash arc or a void oval: frames 0-1, which the manifest's idle names, hold
## an empty swoosh with the creature absent or tiny, while frames 2-7 show it. Battle plays idle for most of a fight, so
## they stood as a blob. test_a_monster_idles_as_one_creature cannot see it: the two oval frames are identical and one
## shape. Found 2026-11-05 by rendering every sheet's idle beside its attack (cowir-sprites, channel 22534). The fix is the
## manifest only, as a8eac3de6 did for five others: idle names frames of the same sheet that show the creature, picked by
## eye at zoom with its facing checked. ghost (a blob ghost) and recursive_loop (a ring) are left alone as plausibly drawn.

const VOID_IDLE_FRAMES := [0, 1]
## Reviewed by eye 2026-11-07. Re-review an entry when its art is redrawn.
const IDLED_AS_A_VOID := [
	"corrupted_guardian", "corrupted_sprite", "crystal_golem", "empty_set", "forgotten_variable", "glitch_entity",
	"masterite_arbiter_futuristic", "masterite_tempo_futuristic", "masterite_warden_abstract",
	"masterite_warden_futuristic", "memory_leak", "null_entity", "optimization_itself", "pipe_phantom",
	"rogue_process", "specter", "the_absence",
]


func _sheets() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return manifest["monster_sheets"]


func _frame(entry: Dictionary, i: int) -> Image:
	var img: Image = (load(str(entry["path"])) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fw := int(entry.get("frame_width", 256))
	return img.get_region(Rect2i(i * fw, 0, fw, img.get_height()))


func test_the_void_frames_are_the_identical_pair_they_were_found_as() -> void:
	## CONTROL: the defect is real on every listed sheet, so the list cannot hold a monster whose frames 0-1 are art.
	var sheets := _sheets()
	for id in IDLED_AS_A_VOID:
		assert_true(sheets.has(id), "CONTROL: %s is a monster sheet" % id)
		var e: Dictionary = sheets[id]
		assert_eq(_frame(e, 0).get_data(), _frame(e, 1).get_data(), "CONTROL: %s frames 0 and 1 are one void picture" % id)


func test_no_listed_monster_idles_on_its_void_frames() -> void:
	var sheets := _sheets()
	var still_void: Array = []
	for id in IDLED_AS_A_VOID:
		var idle: Dictionary = ((sheets[id] as Dictionary).get("animations", {}) as Dictionary).get("idle", {})
		for f in range(int(idle.get("start", 0)), int(idle.get("end", 0)) + 1):
			if f in VOID_IDLE_FRAMES:
				still_void.append("%s idle %d-%d" % [id, idle.get("start", 0), idle.get("end", 0)])
				break
	assert_eq(still_void, [], "monsters whose idle is still the void swoosh, not the creature: %s" % [still_void])
