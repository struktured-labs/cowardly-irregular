extends GutTest

## ⛔ THE F1 CONTROLS REFERENCE IGNORED THE TEXT SIZE SETTING — the one screen a player opens
## BECAUSE they cannot read or do not know the controls. Three raw font sizes, zero `TextScale`,
## while every other menu honours the setting.
##
## ⛔ AND SCALING THE TITLE ALONE COLLIDES, which is why this is not a three-line change. The title
## is a Label at y=35 with no explicit size, so its height tracks its font; the content top was a
## LITERAL 75. At 200% the title reaches ~97 and draws across the body text.
##
## 🔑 Three arms, per @cowir-main's rule: the font GREW, the grown text FITS, and a
## shrink-the-container mutation proving arm 2 reads drawn text and not a box (@cowir-story's
## discriminator — every mutation that breaks the FIX leaves that question open).
##
## ✅ The body needs no fit arm and gets none: `content.scroll_active = true`, so its text is
## absorbed by scrolling rather than overflowing. Same file, two labels, two correct answers.

const OVERLAY := "res://src/ui/HowToPlayOverlay.gd"

## ⛔ DERIVED FROM THE CONSUMER'S OWN LIST, NOT A COPY. A hardcoded [0.8, 1.0, 1.25, 1.5, 2.0] goes
## quietly stale the day a preset is added, and the arm meant to catch "it broke at 125%" then never
## visits the new step. NO FALLBACK DEFAULT: a rename must red, and a fallback would make this pass
## against a ladder the player cannot select.
##
## ⛔ THE FLOOR LIVES IN HERE, NOT ONLY IN ITS OWN ARM. An empty or renamed ladder makes every
## `for scale in _presets()` iterate ZERO times and pass green; asserting inside the helper makes
## each sweeping arm red BY ITS OWN NAME, and it cannot be separated from the loops by a later edit
## the way a standalone floor arm can (@cowir-autogrind named the gap, @cowir-story the repair).
func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve and hold more than one step, or this "
		+ "arm's preset loop iterates nothing and passes. Got " + str(p))
	return p

var _saved_scale = null


func before_each() -> void:
	_saved_scale = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved_scale != null:
		GameState.text_size_scale = _saved_scale


## Build the overlay at a given Text Size and return its title and content nodes.
func _built_at(scale: float) -> Dictionary:
	GameState.text_size_scale = scale
	var o: Node = load(OVERLAY).new()
	add_child_autofree(o)
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Label = null
	var content: RichTextLabel = null
	for c in o.get_children():
		if c is Label and title == null:
			title = c as Label
		elif c is RichTextLabel and content == null:
			content = c as RichTextLabel
	return {"overlay": o, "title": title, "content": content}


func test_the_overlay_builds_with_both_labels() -> void:
	var b: Dictionary = await _built_at(1.0)
	assert_not_null(b["title"], "PRECONDITION: the title Label must be findable")
	assert_not_null(b["content"], "PRECONDITION: the content RichTextLabel must be findable")


## ARM 1 — the font GREW. A fit-only arm is green on the raw-font defect, because small text fits
## its box by construction (@cowir-story measured two of four surfaces with no teeth).
func test_the_fonts_follow_the_setting() -> void:
	var small: Dictionary = await _built_at(0.8)
	var s_title: int = int((small["title"] as Label).get_theme_font_size("font_size"))
	var big: Dictionary = await _built_at(2.0)
	var b_title: int = int((big["title"] as Label).get_theme_font_size("font_size"))
	assert_gt(b_title, s_title,
		"the title font must GROW with Text Size: 80%% gave %d, 200%% gave %d" % [s_title, b_title])
	var s_body: int = int((small["content"] as RichTextLabel).get_theme_font_size("normal_font_size"))
	var b_body: int = int((big["content"] as RichTextLabel).get_theme_font_size("normal_font_size"))
	assert_gt(b_body, s_body,
		"the body font must GROW too: 80%% gave %d, 200%% gave %d" % [s_body, b_body])


## ARM 2 — the grown text FITS: the title must not draw over the body, at EVERY preset step rather
## than only the endpoints (@cowir-adhoc's field menu broke at 125%, not 200%), derived from
## SettingsMenu rather than copied.
func test_the_title_never_draws_over_the_body_at_any_preset() -> void:
	var collisions: Array = []
	for scale in _presets():
		var b: Dictionary = await _built_at(float(scale))
		var title: Label = b["title"] as Label
		var content: RichTextLabel = b["content"] as RichTextLabel
		if title == null or content == null:
			continue
		var title_bottom: float = title.position.y + title.size.y
		if title_bottom > content.position.y:
			collisions.append("%.2fx: title ends %.0f, body starts %.0f"
				% [scale, title_bottom, content.position.y])
	assert_eq(collisions, [],
		"the title must clear the body at every Text Size step: %s" % [collisions])


## ARM 3 — the discriminator. Shrink the container and leave the text: if the extent arm 2 reads
## follows the container, arm 2 is measuring a box and is green in both worlds. If it stays at the
## line height, arm 2 reads drawn text. Here the title has NO explicit size, so this asserts the
## property arm 2 depends on rather than mutating the fix.
##
## 📌 THE FALSIFIER IS `clip_text` AND `autowrap_mode` TOGETHER, measured -- `clip_text` ALONE does
## NOT defeat the clamp, which is the mutation I tried first and it passed, leaving this arm
## advertising teeth it had not been shown to have:
##     baseline / clip_text / empty text   min 67 -> asked 4 -> stays 67   (clamps)
##     clip_text + AUTOWRAP_WORD           min  1 -> asked 4 -> becomes 4   (clamp DEFEATED)
## An EMPTY Label still reports 67, so the vertical minimum is line-height driven rather than glyph
## driven -- which is the property that makes it track Text Size, and is what arm 2 needs.
func test_the_title_extent_is_its_text_not_its_box() -> void:
	var b: Dictionary = await _built_at(2.0)
	var title: Label = b["title"] as Label
	assert_not_null(title, "PRECONDITION: the title must exist")
	if title == null:
		return
	var grown: float = title.size.y
	## Ask for a box far smaller than the glyphs and re-measure.
	title.size = Vector2(title.size.x, 4.0)
	await get_tree().process_frame
	assert_almost_eq(title.size.y, grown, 1.0,
		"asking for a 4px box must NOT shrink the reported extent — a Label clamps up to its "
		+ "content, which is why arm 2 reads drawn text. Got %.0f, expected ~%.0f"
			% [title.size.y, grown])
	assert_gt(grown, 4.0, "CONTROL: the glyphs must be taller than the box we asked for")


## ARM 4 — the claim the FIX makes about the state it did not change. Deriving the content top is a
## change to a shipped layout, and `maxf` against the authored 75 is what keeps 100% identical. That
## is a measurable claim, so it is pinned here rather than asserted in the commit message: if the
## derived value ever rises above the floor at 100%, every existing F1 screenshot moved and this
## reds instead of going quiet.
func test_the_default_text_size_renders_the_shipped_layout() -> void:
	var b: Dictionary = await _built_at(1.0)
	var content: RichTextLabel = b["content"] as RichTextLabel
	assert_not_null(content, "PRECONDITION: the content must exist")
	if content == null:
		return
	var consts: Dictionary = (load(OVERLAY) as GDScript).get_script_constant_map()
	assert_true(consts.has("BASE_CONTENT_Y"),
		"FLOOR: the overlay must still name BASE_CONTENT_Y -- a rename makes this arm vacuous")
	var floor_y: float = float(consts.get("BASE_CONTENT_Y", -1.0))
	assert_eq(content.position.y, floor_y,
		"at 100%% the content top must still be the authored %.0f, not a derived value: got %.1f"
			% [floor_y, content.position.y])


## FLOOR for the preset derivation — without it an empty list makes every preset loop above iterate
## ZERO times and pass, which is the shrinking-corpus shape a derived guard fails into silently.
func test_the_preset_list_derives_from_settings() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 1,
		"FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must still resolve and hold more than one step — a "
		+ "rename leaves every preset loop here iterating nothing and passing. Got " + str(p))
	assert_true(p.has(1.0), "the derived presets must include the 1.0 default: " + str(p))
