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

## ⚠️ ELEVEN CALLERS USE 11 AND TWO DO NOT. `HiddenPassage`'s "Secret passage!" is authored at
## 12 and `SavePoint`'s "Game Saved!" at 14, so the base is a PARAMETER with 11 as its default —
## appended nowhere, because it is the first argument every measuring function already needed.
const BASE_FONT: int = 11


## The authored size is the BASE; Text Size multiplies it. Reach the font only through here.
static func font_size(base: int = BASE_FONT) -> int:
	return TextScale.scaled(base)


## What the wrapped block needs at `width`, floored at the authored box so a short toast is
## unchanged. The font comes from a throwaway Label because that is where the theme default lives,
## and it is a STATIC seam so a guard can ask for a real string's height without building a scene.
static func height_for(text: String, width: float, min_h: float, base: int = BASE_FONT) -> float:
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	var h: float = min_h
	if font != null:
		h = maxf(font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size(base)).y, min_h)
	probe.free()
	return h


## ⛔ THE ONE PLACE THE ORIGIN IS SPELLED. It takes an ALREADY-MEASURED height because `show` has
## one and must not pay for a second measurement — and because the alternative is two expressions
## for one quantity inside the helper whose whole purpose is collapsing eleven of them. `show` had
## exactly that: an inline `Vector2(-width * 0.5, baseline_top - (h - min_h))` beside this. They
## agreed, so it was not a bug; it was the CONDITION for one, since changing the rule here would
## have left `show` silently on the old one. Found by cowir-story reading the pair, and it is the
## same shape as @cowir-adhoc's lens overrun — a floor applied on one side of a quantity only.
##
## 🔑 THE AUTHORED BOTTOM EDGE IS HELD AND GROWTH GOES UPWARD. `baseline_top` is where the authored
## rect's top sat, so `baseline_top + min_h` is its bottom; a taller block rises away from the
## player rather than covering them. Pinning the top is the defect this replaces.
##
## Every caller's x was already `-width / 2` to the pixel — 300 -> -150, 260 -> -130, 240 -> -120,
## 380 -> -190 — so that term is derivation replacing eleven hand-computed literals, not a new rule.
static func origin_for_height(h: float, width: float, baseline_top: float, min_h: float) -> Vector2:
	return Vector2(-width * 0.5, baseline_top - (h - min_h))


## The measuring entry points. Both route through `origin_for_height`, so a change to the rule
## reaches `show` and cowir-story's delegated `toast_position_for` together or not at all.
static func origin_for(text: String, width: float, baseline_top: float, min_h: float,
		base: int = BASE_FONT) -> Vector2:
	return origin_for_height(height_for(text, width, min_h, base), width, baseline_top, min_h)


static func top_for(text: String, width: float, baseline_top: float, min_h: float,
		base: int = BASE_FONT) -> float:
	return origin_for(text, width, baseline_top, min_h, base).y


## Height already occupied by this host's live toasts, so a second one stacks above the first
## instead of over it. Only QuestChicken asks for this; it is its behaviour, kept.
##
## ⚠️ IT COUNTS EVERY SIBLING `Label`, WHICH IS CORRECT ONLY BECAUSE QuestChicken HAS NO OTHER
## ONE. Nine of the twelve props build an `_indicator` Label in `_ready` -- the world-space press
## prompt -- and a caller with `stack = true` AND an indicator would stack its toast above its own
## prompt. Measured: QuestChicken is the one prop with zero indicator Labels, which is also how the
## guard for this file came to be measuring press prompts instead of toasts for nine callers.
## A future stacking caller needs a narrower rule than "is a Label" before it passes `stack`.
static func stack_offset(host: Node, exclude: Node) -> float:
	var used := 0.0
	for c in host.get_children():
		if c is Label and c != exclude:
			used += (c as Label).size.y + 4.0
	return used


## ⛔ `fade_dur` IS APPENDED, NOT INSERTED, and it exists for exactly one caller. Eleven of the
## twelve toasts fade over the same span they rise over — identical in every census row — so the
## default keeps `dur` and none of their argument lists move. `QuestExaminePoint` is the twelfth:
## it rises over `hold + fade` while fading over `fade` alone after a `hold` delay, where hold is
## derived from the string's word count. That is a reading time, not a notice, and flattening it
## would change what cowir-story measured as 24 prose strings' legibility.
static func show(host: Node2D, text: String, width: float, baseline_top: float, col: Color,
		min_h: float = 18.0, rise: float = 20.0, dur: float = 1.6, delay: float = 0.6,
		stack: bool = false, label_name: String = "WorldToast", fade_dur: float = -1.0,
		base_font: int = BASE_FONT) -> Label:
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
	lbl.add_theme_font_size_override("font_size", font_size(base_font))
	lbl.add_theme_color_override("font_color", col)
	var h: float = height_for(text, width, min_h, base_font)
	lbl.size = Vector2(width, h)
	var at: Vector2 = origin_for_height(h, width, baseline_top, min_h)
	host.add_child(lbl)
	if stack:
		at.y -= stack_offset(host, lbl)
	lbl.position = at
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", at.y - rise, dur)
	tw.tween_property(lbl, "modulate:a", 0.0, (dur if fade_dur < 0.0 else fade_dur)).set_delay(delay)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
	return lbl
