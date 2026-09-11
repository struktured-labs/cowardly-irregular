extends GutTest

## A name passed to a drawing routine that never renders it exists only in the source file.
##
## FOUND 2026-09-11 in a contact sheet of all 30 interiors. Maple Heights' arcade draws four cabinets
## via `_draw_cabinets(marker, anchor, hue, label_text)` — and `label_text` is never used in the
## function body. Its comment said "the player sees four neon machines visually, the dialogue says the
## names", which was true for ONE of the four: Pete mentioned "Bug Zero", and DRAGON, PAC-MOM and
## SPACE 2 appeared nowhere in the game at all. Three authored names, reachable by nobody.
##
## 🔑 THE PARAMETER IS WHY IT SURVIVED. `_marker` carries the underscore that means "deliberately
## unused"; `label_text` does not, so it reads as live at every call site, and the comment above it
## described a consumer that was not there. Same shape as every dead-consumer find this week, at the
## smallest possible scale: a promise in prose, a plausible-looking argument, and nothing in between.
##
## This pins the DELIVERABLE rather than the habit: whatever name the source gives a machine must be
## readable by a player somewhere. It cannot be silenced — only satisfied by writing the name into
## something the player can reach.

const ARCADE := "res://src/maps/interiors/MapleHeightsArcadeInterior.gd"


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "cannot open %s" % path)
	return "" if f == null else f.get_as_text()


func test_every_cabinet_the_arcade_names_can_be_read_by_a_player() -> void:
	var src := _read(ARCADE)
	assert_ne(src, "", "CONTROL: the arcade source must be readable")

	## Last quoted argument on each _draw_cabinets line — the brand the source claims it carries.
	## Not a single regex over the whole call: the argument list contains Color(...), whose closing
	## paren ends a naive [^)]* match. The CONTROL below caught exactly that, on the first run.
	var quoted := RegEx.new()
	quoted.compile('"([^"]*)"')
	var named: Array = []
	for line in src.split("\n"):
		if not line.contains("_draw_cabinets("):
			continue
		if line.strip_edges().begins_with("func "):
			continue
		var hits := quoted.search_all(line)
		if hits.size() > 0:
			named.append(hits[hits.size() - 1].get_string(1))

	assert_gt(named.size(), 2,
		"CONTROL: only %d cabinet names found — the scan is broken and the pass below is free" % named.size())

	## The dialogue block is the only surface these names can reach; the bar on the cabinet is a colour.
	var dlg_start := src.find("dialogue_lines = [")
	assert_gt(dlg_start, -1, "CONTROL: the arcade must author dialogue at all")
	var dlg_end := src.find("]", dlg_start)
	var dialogue := src.substr(dlg_start, dlg_end - dlg_start)

	var unreadable: Array = []
	for n in named:
		if not dialogue.contains(n):
			unreadable.append(n)
	unreadable.sort()
	assert_eq(unreadable, [],
		"the source names these machines and no player can ever read the names: %s" % str(unreadable))
