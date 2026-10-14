extends RefCounted
class_name WorldToast

## The floating one-line notice a prop shows when you press it. ELEVEN props hand-rolled this and
## the copies had diverged into seven box sizes, four rise distances, six durations and six fade
## delays — and two defects that only a derived box can fix:
##
##   HEIGHT WAS A HARD NUMBER. Measured at font 11 against each authored box: CivicFrontDesk needs
##   48 px of 34, and MissingPackage / SwordInscription / TallyWall / WildflowerPatch need 32 of 18.
##   A Label does not clip, so the overflow drew DOWNWARD over the prop being read and the player
##   standing at it. CivicFrontDesk already WRAPPED, which is why "make them wrap" was the wrong
##   diagnosis — wrapping does not help when the height is authored rather than measured.
##
##   WIDTH WAS A FLOOR, NOT A CAP. Four of them set no autowrap, and `Control.size` clamps UP to
##   `get_combined_minimum_size()`, which for an unwrapped Label is its whole string. So the label
##   grew past its box while `position.x` stayed at the authored `-width / 2`: that centres the BOX
##   and not the TEXT. Measured drift, worst string per prop: SwordInscription +114 px,
##   WildflowerPatch +94, MissingPackage +64, TallyWall +22 — to the RIGHT of the prop it names.
##
## Derived from `QuestExaminePoint`'s metrics (cowir-story, v3.33.688), which solved this for one
## prop; this is that shape with the per-prop values passed in rather than a thirteenth spelling.

const BASE_FONT: int = 11


## The authored size is the BASE; Text Size multiplies it. Reach the font only through here.
static func font_size() -> int:
	return TextScale.scaled(BASE_FONT)


## What the wrapped block needs at `width`, floored at the authored box so a short toast is
## unchanged. The font comes from a throwaway Label because that is where the theme default lives,
## and it is a STATIC seam so a guard can ask for a real string's height without building a scene.
static func height_for(text: String, width: float, min_h: float) -> float:
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	var h: float = min_h
	if font != null:
		h = maxf(font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size()).y, min_h)
	probe.free()
	return h


## ⛔ THE AUTHORED BOTTOM EDGE IS HELD AND GROWTH GOES UPWARD. `baseline_top` is where the authored
## rect's top sat, so `baseline_top + min_h` is its bottom; a taller block rises away from the
## player rather than covering them. Today the top is pinned instead, which is why the overflow
## lands on the prop.
static func top_for(text: String, width: float, baseline_top: float, min_h: float) -> float:
	return baseline_top - (height_for(text, width, min_h) - min_h)


## Every caller's x was already `-width / 2` to the pixel — 300 -> -150, 260 -> -130, 240 -> -120,
## 380 -> -190 — so this is derivation replacing eleven hand-computed literals, not a new rule.
static func origin_for(text: String, width: float, baseline_top: float, min_h: float) -> Vector2:
	return Vector2(-width * 0.5, top_for(text, width, baseline_top, min_h))


## Height already occupied by this host's live toasts, so a second one stacks above the first
## instead of over it. Only QuestChicken asks for this; it is its behaviour, kept.
static func stack_offset(host: Node, exclude: Node) -> float:
	var used := 0.0
	for c in host.get_children():
		if c is Label and c != exclude:
			used += (c as Label).size.y + 4.0
	return used


static func show(host: Node2D, text: String, width: float, baseline_top: float, col: Color,
		min_h: float = 18.0, rise: float = 20.0, dur: float = 1.6, delay: float = 0.6,
		stack: bool = false, label_name: String = "WorldToast") -> Label:
	if text == "" or host == null or not host.is_inside_tree():
		return null
	var lbl := Label.new()
	lbl.name = label_name
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ⛔ FONT OVERRIDE BEFORE `size`. The height is measured AT this font, so setting it after
	## would measure the theme default (cowir-story's note on the same hazard).
	lbl.add_theme_font_size_override("font_size", font_size())
	lbl.add_theme_color_override("font_color", col)
	var h: float = height_for(text, width, min_h)
	lbl.size = Vector2(width, h)
	var at: Vector2 = Vector2(-width * 0.5, baseline_top - (h - min_h))
	host.add_child(lbl)
	if stack:
		at.y -= stack_offset(host, lbl)
	lbl.position = at
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", at.y - rise, dur)
	tw.tween_property(lbl, "modulate:a", 0.0, dur).set_delay(delay)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
	return lbl
