extends GutTest

## Live-playtest regression (2026-07-17 → cowir-main msg 2779):
##
## Struktured saw the procedural `_draw_dancer` composite in The Dancing
## Tonberry (VillageBar.gd:275) — a pixel-by-pixel red-dress dancer with
## 4 hardcoded frames — and asked for real art / gpt-image sprites.
##
## Fix: DANCER_FRAME_PATHS pre-registers 4 PNG paths under
## assets/sprites/npcs/dancer/frame_<n>.png, checked BEFORE the procedural
## fallback via `_try_load_artist_dancer_frames`. All-or-nothing: partial
## coverage falls through to procedural rather than mixing artist +
## procgen frames mid-animation (would visibly flicker).
##
## This ratchet pins the wiring (same defect class as guard.png and
## keeper portraits — art-exists-implies-wired).

const VILLAGE_BAR := "res://src/exploration/VillageBar.gd"
const DANCER_PATHS: Array = [
	"res://assets/sprites/npcs/dancer/frame_0.png",
	"res://assets/sprites/npcs/dancer/frame_1.png",
	"res://assets/sprites/npcs/dancer/frame_2.png",
	"res://assets/sprites/npcs/dancer/frame_3.png",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_dancer_frame_paths_registered_and_files_exist() -> void:
	# Pin: DANCER_FRAME_PATHS declares 4 entries AND every referenced file
	# exists on disk (art-exists-implies-wired — same class that caught
	# the guard.png repoint in v3.33.201 and the keeper wiring ratchet).
	var src := _read(VILLAGE_BAR)
	assert_true(src.contains("DANCER_FRAME_PATHS"),
		"VillageBar must declare DANCER_FRAME_PATHS — the wiring const is what makes bespoke art win over the procedural draw")
	for i in range(4):
		var path := "res://assets/sprites/npcs/dancer/frame_%d.png" % i
		assert_true(FileAccess.file_exists(path),
			"%s must exist on disk — DANCER_FRAME_PATHS references it and any missing frame silently drops the whole animation to the legacy procedural composite (msg 2779 regression)" % path)


func test_artist_load_precedes_procedural_fallback() -> void:
	# Pin the ORDER: artist load must be attempted BEFORE any procedural
	# _draw_dancer call, otherwise procedural wins and the whole point of
	# the wiring is defeated.
	var src := _read(VILLAGE_BAR)
	var artist_idx := src.find("_try_load_artist_dancer_frames")
	var proc_idx := src.find("_draw_dancer(image, frame)")
	assert_gt(artist_idx, -1, "VillageBar must have _try_load_artist_dancer_frames — the artist-first branch")
	assert_gt(proc_idx, -1, "VillageBar must still keep the procedural _draw_dancer fallback so old builds still render if art goes missing")
	assert_lt(artist_idx, proc_idx,
		"Artist load must precede the procedural fallback — otherwise procedural silently wins even when PNGs exist")


func test_artist_load_is_all_or_nothing() -> void:
	# BEHAVIOURAL, deliberately — the source-text version of this test passed
	# 3/3 against a mutation that broke the exact contract it names (swap the
	# `return false` for a `continue` and both pinned strings survive
	# elsewhere in the function). See cowir-ai msg 3319: a pinned string is a
	# claim about the code's SPELLING where we meant its BEHAVIOUR.
	#
	# So drive it instead. `_try_load_artist_dancer_frames` takes an
	# injectable path list for this reason alone — DANCER_FRAME_PATHS is a
	# const, and without injection the missing-file branch is unreachable
	# from a test, which is why the old guard could only pin spelling.
	var bar: VillageBar = autofree(VillageBar.new())

	# Positive control: all four real frames load, all four land.
	assert_true(bar._try_load_artist_dancer_frames(),
		"the four shipped dancer PNGs must load — if this fails the bar is silently procedural again")
	assert_eq(bar._dancer_frames.size(), 4,
		"a successful artist load must yield exactly 4 frames")

	# Negative control: one path missing => refuse the WHOLE set. A partial
	# load would alternate artist and procedural frames every ANIM_SPEED
	# tick, flickering between two art styles — the defect this guards.
	bar._dancer_frames.clear()
	var one_missing: Array = DANCER_PATHS.slice(0, 3)
	one_missing.append("res://assets/sprites/npcs/dancer/frame_DOES_NOT_EXIST.png")
	assert_false(bar._try_load_artist_dancer_frames(one_missing),
		"a missing frame must fail the whole load, not load the other three")
	assert_true(bar._dancer_frames.is_empty(),
		"a failed artist load must leave NO frames behind — any survivors mix artist + procgen mid-animation")
