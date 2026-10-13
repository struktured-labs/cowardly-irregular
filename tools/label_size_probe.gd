extends SceneTree

## ONE probe for the Label-size ordering question (@cowir-main's work order, 2026-10-13).
##
## Three in-repo benches disagreed about whether `Label.size` survives:
##   ItemsMenu's comment   size BEFORE add_child is LOST (584 asked, 1068 back) -> set it AFTER
##   my bench              size AFTER  add_child gives a 2-line draw in a 3892px rect
##   cowir-controller      BOTH orderings hold 400, plain Control parent, read after 4 frames
## All three ran a different configuration and reported a rule. This varies the axes one at a
## time and prints the table instead.
##
## 🔑 Two facts already established without godot, so they are NOT axes here:
##   - ItemsMenu's parent is a plain `Control.new()`, the same kind as controller's bench, so
##     parent kind cannot be what separates those two results. It is still varied below because a
##     container is a SECOND, independent way to lose an assignment and the repo uses both.
##   - min width 1.0 is CORRECT for an autowrapping Label (it can wrap to one char per line), so
##     an assigned width can never be clamped UP while autowrap is live. A result of 1068 for an
##     asked-for 584 therefore means the wrap was not in effect at that moment — which makes
##     `autowrap_mode` and `max_lines_visible` the suspects, not the ordering.

const TEXT_141 := "A dusty bottle that smells faintly of mint and older things, stoppered with wax that someone pressed a thumbprint into before it cooled."
const TEXT_133 := "Everything you have fought was a measurement, and the slime in the first field was the control group for all of it, patiently."


func _init() -> void:
	await process_frame
	await process_frame

	print("=== LABEL SIZE PROBE ===")
	print("cfg: ordering · parent · autowrap · max_lines | immediate size/min/lines -> settled size/min/lines")
	print("")

	## The ItemsMenu configuration, which is the bench that reported a LOST assignment.
	await _table("ItemsMenu cfg (141 chars, ask 584, AUTOWRAP_WORD, font 11, no max_lines)",
		TEXT_141, 584.0, TextServer.AUTOWRAP_WORD, 11, 0)

	## cowir-controller's configuration, which reported the assignment HELD in both orderings.
	await _table("controller cfg (133 chars, ask 400, AUTOWRAP_WORD, font 10, max_lines 2)",
		TEXT_133, 400.0, TextServer.AUTOWRAP_WORD, 10, 2)

	## The suspect isolated: the SAME ItemsMenu config with the wrap turned OFF. If this is the
	## row that returns the content width, the two benches never disagreed about ordering at all.
	await _table("ItemsMenu cfg but AUTOWRAP_OFF (the suspect)",
		TEXT_141, 584.0, TextServer.AUTOWRAP_OFF, 11, 0)

	## And the max_lines cap on its own, since it is the other thing only one bench set.
	await _table("ItemsMenu cfg + max_lines 2",
		TEXT_141, 584.0, TextServer.AUTOWRAP_WORD, 11, 2)

	print("=== END ===")
	quit()


func _table(title: String, text: String, ask_w: float, wrap: int, font_size: int, max_lines: int) -> void:
	print("--- %s" % title)
	for parent_kind in ["Control", "VBoxContainer"]:
		for size_first in [true, false]:
			await _one(text, ask_w, wrap, font_size, max_lines, parent_kind, size_first)
	print("")


## One cell of the table. `size_first` = assign `size` BEFORE add_child.
func _one(text: String, ask_w: float, wrap: int, font_size: int, max_lines: int,
		parent_kind: String, size_first: bool) -> void:
	var host: Control = VBoxContainer.new() if parent_kind == "VBoxContainer" else Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)

	var l := Label.new()
	## Everything that feeds the minimum goes on first in BOTH arms — the axis under test is where
	## `size` lands relative to `add_child`, not whether the wrap is live.
	l.autowrap_mode = wrap
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	if max_lines > 0:
		l.max_lines_visible = max_lines

	var ask := Vector2(ask_w, 36.0)
	if size_first:
		l.size = ask
		host.add_child(l)
	else:
		host.add_child(l)
		l.size = ask

	var imm := "%s %s %d" % [_v(l.size), _v(l.get_minimum_size()), l.get_line_count()]
	await process_frame
	await process_frame
	var settled := "%s %s %d" % [_v(l.size), _v(l.get_minimum_size()), l.get_line_count()]

	var verdict := "HELD" if is_equal_approx(l.size.x, ask_w) else "LOST"
	print("  %-14s size %-6s | %-22s -> %-22s  %s"
		% [parent_kind, "FIRST" if size_first else "AFTER", imm, settled, verdict])

	host.queue_free()
	await process_frame


func _v(v: Vector2) -> String:
	return "(%d,%d)" % [int(round(v.x)), int(round(v.y))]
