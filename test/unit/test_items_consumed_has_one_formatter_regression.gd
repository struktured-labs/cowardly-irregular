extends GutTest

## AutogrindHistoryScreen rendered "potion_minor x3" where AutogrindSummary rendered
## "Potion Minor x3" — the SAME dict, two screens, one showing the raw id. Three surfaces each
## rolled their own formatter for {item_id: count} and one of them skipped name resolution.
##
## ItemNameResolver's own docstring is the precedent, one level down: ticks 130-134 added three
## near-identical copies of name resolution across BestiaryMenu, TreasureChest and VillageShop, and
## tick 133 found a singular-vs-plural typo locked in by one of those copies' tests. "Extract once
## so future fixes touch one file" — this is that, for the count formatting that wraps it.
##
## ⛔ AutogrindSystem.get_items_consumed_summary() already WAS the canonical formatter and had zero
## production callers. I came to this file intending to retire it as dead code. It is not dead — it
## is the un-adopted correct version, and the surfaces that should have called it had each written
## their own instead. Deleting it would have removed the one right answer and left three copies.
##
## AutogrindSummary is deliberately NOT converted: it already resolves names (its
## _resolve_item_display_name is a one-line wrapper on the same resolver), and
## test_autogrind_summary_items_canonical_name pins its exact expression. Changing it would red a
## guard to make identical output, which is a helper-name pin taxing a refactor rather than a defect.

const HISTORY := "res://src/ui/autogrind/AutogrindHistoryScreen.gd"
const LANE_DIRS := ["res://src/ui/autogrind", "res://src/ui/autobattle"]


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


## BEHAVIOUR, not a source pin: the formatter must resolve, and an id whose raw form differs
## visibly from its display name is the only kind that can prove it.
func test_the_formatter_resolves_display_names() -> void:
	assert_eq(AutogrindSystem.format_items_consumed({"phoenix_down": 2}), "Phoenix Down x2",
		"the shared formatter must resolve ids to display names — a raw id here is the defect this file exists for")
	assert_eq(AutogrindSystem.format_items_consumed({}), "None",
		"empty must read 'None', which is what every surface showed before and after")
	## CONTROL: the discriminator must actually discriminate, or the assert above proves nothing.
	assert_ne(ItemNameResolver.resolve("phoenix_down"), "phoenix_down",
		"CONTROL: this id must resolve to something OTHER than itself, or the test cannot see the bug")


## The canonical accessor keeps its one test caller working and now delegates rather than duplicating.
func test_the_system_summary_delegates_to_the_shared_formatter() -> void:
	AutogrindSystem.items_consumed = {"hi_potion": 1}
	assert_eq(AutogrindSystem.get_items_consumed_summary(), "Hi-Potion x1",
		"get_items_consumed_summary must produce what the shared formatter produces")
	AutogrindSystem.items_consumed = {}
	assert_eq(AutogrindSystem.get_items_consumed_summary(), "None")


## ⛔ BANS THE DEFECT SPELLING, does not pin the cure. Evading this scan means resolving the name,
## which IS the correction — @cowir-ai's discriminator for a guard that cannot be gamed. Comments are
## stripped because the fix's own explanatory comment quotes `str(item_id)`, and a scan that reads it
## would report the repair as the defect.
func test_no_autogrind_surface_formats_items_by_raw_id() -> void:
	var offenders: Array = []
	var scanned := 0
	for d in LANE_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = d + "/" + f
			var code := _code_only(FileAccess.get_file_as_string(path))
			scanned += 1
			if not code.contains("items_consumed"):
				continue
			for line in code.split("\n"):
				if line.contains("str(item_id)") or line.contains("str(key)"):
					offenders.append("%s: %s" % [path.get_file(), line.strip_edges()])
	assert_gt(scanned, 5, "CONTROL: the scan must read a real corpus, got %d files" % scanned)
	assert_eq(offenders, [],
		"an autogrind surface formats items_consumed by raw id — call AutogrindSystem.format_items_consumed instead:\n  %s"
		% "\n  ".join(offenders))


## The stripper, pinned directly — the fix's comment is the exact input that would break it.
func test_the_stripper_ignores_a_comment_quoting_the_defect() -> void:
	var sample := "\t## Was str(item_id) — a player read raw ids\n\tvar x := 1"
	assert_false(_code_only(sample).contains("str(item_id)"),
		"a comment quoting the defect must not register as the defect")
	assert_true(_code_only("\tparts.append(str(item_id))").contains("str(item_id)"),
		"CONTROL: and real code must still register")


func _code_only(src: String) -> String:
	var out := PackedStringArray()
	for l in src.split("\n"):
		var h := l.find("#")
		out.append(l if h == -1 else l.substr(0, h))
	return "\n".join(out)
