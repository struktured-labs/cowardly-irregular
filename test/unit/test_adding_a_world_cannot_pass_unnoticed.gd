extends GutTest

## Sixteen guards carry a HARDCODED list of overworld scripts, and none of them lists all six.
##
## That is mostly correct — the Mode 7 guards exclude W6 on purpose, because W6 runs no Mode 7. But
## every one of those lists is a static population, and a seventh world would not RED any of them. It
## would simply not be covered: the reachability sweep, the bounds check, the prompt sweep, the
## encounter-source check and a dozen others would keep passing while saying nothing about it.
##
## 🔑 THIS IS THE INVERSE OF THE DEFECT THAT REDDENED TWO FOLD GATES ON 2026-09-10. There, ten of
## eleven failures were a static list in lane A's test made stale by lane B's correct fix — a list
## going stale LOUDLY. A world list going stale is the quiet version of the same thing, and quiet is
## worse: a stale allowlist gets fixed at the fold, a stale population is never noticed at all.
##
## So this is one census in one place instead of an assertion bolted onto sixteen files. It pins only
## the SET OF WORLDS — nothing about what any guard does with them — and when it reds, its message
## names every test that will need a new entry, computed by scanning rather than by a second list
## that could itself go stale.

const EXPLORATION := "res://src/exploration"
const TEST_DIR := "res://test/unit"
## The six authored overworlds. Adding a seventh is a real event that should cost one deliberate edit.
const KNOWN_WORLDS := [
	"AbstractOverworld.gd",
	"FuturisticOverworld.gd",
	"IndustrialOverworld.gd",
	"OverworldScene.gd",
	"SteampunkOverworld.gd",
	"SuburbanOverworld.gd",
]


func _overworld_scripts_on_disk() -> Array:
	var out: Array = []
	var dir := DirAccess.open(EXPLORATION)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		if f == "OverworldScene.gd" or (f.ends_with("Overworld.gd") and f != "AbstractOverworld.gd.uid"):
			out.append(f)
	out.sort()
	return out


## Derived, not pinned: a second hardcoded list here would be the very thing this file exists to stop.
func _tests_carrying_a_world_list() -> Array:
	var out: Array = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "test_adding_a_world_cannot_pass_unnoticed.gd":
			continue
		var src := FileAccess.get_file_as_string("%s/%s" % [TEST_DIR, f])
		if src.contains("OverworldScene.gd\"") or src.contains("Overworld.gd\""):
			out.append(f)
	out.sort()
	return out


func test_the_set_of_authored_overworlds_is_the_one_every_guard_was_written_against() -> void:
	var on_disk := _overworld_scripts_on_disk()
	var known := KNOWN_WORLDS.duplicate()
	known.sort()

	assert_gt(on_disk.size(), 0, "CONTROL: the scan found no overworld scripts at all")
	var dependents := _tests_carrying_a_world_list()
	assert_gt(dependents.size(), 5,
		"CONTROL: only %d tests found carrying a world list — the scan is broken and the pass below is free" % dependents.size())

	var added: Array = []
	for f in on_disk:
		if not (f in known):
			added.append(f)
	var removed: Array = []
	for f in known:
		if not (f in on_disk):
			removed.append(f)

	assert_eq(added, [],
		"a new overworld exists that no guard knows about: %s — %d tests carry a hardcoded world list and every one of them silently skips it: %s" %
		[str(added), dependents.size(), str(dependents)])
	assert_eq(removed, [],
		"an overworld named in this census is gone from disk: %s — the guards listing it will error or skip" % str(removed))
