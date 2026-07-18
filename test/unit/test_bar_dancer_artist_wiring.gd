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
	# Pin partial-coverage guard: _try_load_artist_dancer_frames returns
	# false on ANY missing path, so we never mix artist + procgen frames
	# mid-animation (that would visibly flicker between styles per tick).
	var src := _read(VILLAGE_BAR)
	assert_true(src.contains("_try_load_artist_dancer_frames"),
		"VillageBar must define _try_load_artist_dancer_frames")
	# Find the function body and confirm it early-returns on ResourceLoader.exists false.
	var fn_idx := src.find("func _try_load_artist_dancer_frames")
	assert_gt(fn_idx, -1)
	var body := src.substr(fn_idx, 500)
	assert_true(body.contains("ResourceLoader.exists"),
		"artist-load must guard on ResourceLoader.exists per frame — early-returns preserve the all-or-nothing contract")
	assert_true(body.contains("return false"),
		"artist-load must early-return false on any missing frame (all-or-nothing)")
