extends GutTest

## `load_monster_sprite_frames` guarded its result with
##
##     if sprite_frames.get_animation_names().size() == 0: return null
##
## and that condition CANNOT BE TRUE. `SpriteFrames.new()` ships with a "default" animation, so
## the name count starts at 1 and never returns to 0 — nothing in the builder removes it. Measured
## in-engine below, which is the first arm.
##
## The consequence is the artist-first hierarchy inverted: the caller does `if external_frames:`,
## and a non-null SpriteFrames is truthy however empty it is. So a sheet that produced no frames
## returns as a successful artist load and the procedural fallback — which exists for exactly this
## case — never runs. The monster renders as nothing and the log says it used the artist sheet.
##
## Fixed by asking the question the guard meant: does ANY animation have FRAMES.
##
## ZERO instances today, measured both halves: 114 monster entries, 0 with a missing path, 0
## without an `animations` key, 0 with an empty one.
##
## ⚠️ The JOB builder is NOT affected and must not be "fixed" to match. It guards with its own
## `loaded_any` flag (`return sprite_frames if loaded_any else null`), which works. A capability
## diff searching for the monster builder's SPELLING reported it as unguarded — a false asymmetry,
## and the reason this file says so is to stop the next reader repeating it. Its one narrower gap
## (an animation added with frame_count 0, when a declared frame_width exceeds the texture) also
## measures 0 across all 145 job animation files, so it is recorded, not changed.

const LOADER := "res://src/battle/sprites/HybridSpriteLoader.gd"


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_a_name_count_can_never_reach_zero() -> void:
	## The defect as a measurement, not as source text. If this ever returns 0, the old guard was
	## fine all along and this file should be deleted rather than kept as decoration.
	var fresh := SpriteFrames.new()
	assert_eq(fresh.get_animation_names().size(), 1,
		"a fresh SpriteFrames no longer carries exactly one built-in animation — re-derive whether the old size()==0 guard was vacuous before trusting anything below")
	assert_true(fresh.has_animation("default"),
		"the built-in animation is no longer called 'default' — the premise of this file is engine behaviour, so check it rather than assuming")
	assert_false(HybridSpriteLoader.has_usable_frames(fresh),
		"an EMPTY SpriteFrames must read as unusable. This is the case the old guard was written for and could not see")


func test_an_animation_without_frames_is_not_usable_art() -> void:
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	assert_eq(sf.get_animation_names().size(), 2, "SCOPE: expected 'default' + 'idle'")
	assert_false(HybridSpriteLoader.has_usable_frames(sf),
		"an animation that was added but never populated is not art — counting NAMES says 2 and counting FRAMES says 0, and only the second is the question")
	sf.add_frame("idle", PlaceholderTexture2D.new())
	assert_true(HybridSpriteLoader.has_usable_frames(sf),
		"one real frame must read as usable, or the guard refuses everything and the fallback becomes unconditional")


func test_null_is_unusable_rather_than_a_crash() -> void:
	assert_false(HybridSpriteLoader.has_usable_frames(null),
		"a null sheet must answer false, not abort the caller's frame")


func test_a_real_monster_sheet_still_loads() -> void:
	## Anti-over-correction: a predicate that refuses everything also "fixes" the bug.
	var frames := HybridSpriteLoader.load_monster_sprite_frames("slime")
	assert_not_null(frames, "slime no longer loads at all — the new guard is refusing real art")
	assert_true(HybridSpriteLoader.has_usable_frames(frames), "a real sheet must read as usable")


func test_the_builder_asks_for_frames_not_names() -> void:
	var src := _src(LOADER)
	assert_true(src.contains("if not has_usable_frames(sprite_frames):"),
		"WIRING: the monster builder no longer consults has_usable_frames, so an empty sheet is returned as a successful artist load")
	assert_false(src.contains("get_animation_names().size() == 0"),
		"the name-count guard is back. It reads as protection and cannot fire, because 'default' keeps the count at 1")
	assert_true(src.contains("return sprite_frames if loaded_any else null"),
		"SIBLING: the JOB builder's own guard is gone. It is a different spelling of the same intent and it works — do not converge them by deleting this one")
