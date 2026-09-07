extends GutTest

## Static NPCs (Guard Boris, Young Pip, Flora, et al) used to replay the
## exact same dialogue_lines array, in the exact same order, every single
## interaction. User feedback 2026-06: "guard boris still gave same text
## as last time". Fix: rotate the starting index per visit so the player
## hears each scripted opener in turn before the cycle repeats.

const OVERWORLD_NPC_PATH := "res://src/exploration/OverworldNPC.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_visit_counter_field_exists() -> void:
	var src := _read(OVERWORLD_NPC_PATH)
	assert_true(src.contains("var _dialogue_visit_count"),
		"OverworldNPC must track a per-instance dialogue visit counter")


func test_static_path_rotates_by_visit_count() -> void:
	var src := _read(OVERWORLD_NPC_PATH)
	var idx := src.find("Static path")
	assert_gt(idx, -1, "static dialogue branch must still exist")
	var rest := src.substr(idx, 1800)
	# Both halves of the rotation contract — offset derived from the
	# counter, and counter incremented per visit.
	assert_true(rest.contains("_dialogue_visit_count % n"),
		"offset must derive from visit count modulo line count")
	assert_true(rest.contains("_dialogue_visit_count += 1"),
		"visit count must increment so the next interaction starts elsewhere")
	# The rotated index must be (i + offset) % n — not raw i.
	assert_true(rest.contains("(i + offset) % n"),
		"line index must be rotated by offset, not iterated raw")


func test_rotation_handles_empty_dialogue_lines() -> void:
	# Edge case: empty dialogue_lines must not divide by zero. The guard
	# in _start_dialogue (early-return on is_empty) covers most paths,
	# but the offset calc itself must also be safe.
	var src := _read(OVERWORLD_NPC_PATH)
	var idx := src.find("Static path")
	var rest := src.substr(idx, 1800)
	assert_true(rest.contains("if n > 0 else 0"),
		"offset computation must short-circuit when n == 0")
