extends GutTest

## Regression class, found via the shop keeper portrait (256x256 in a 64x64 slot) and swept
## across all 45 TextureRect.new() sites in src/.
##
## A TextureRect's minimum size IS its texture's size until expand_mode is set to
## EXPAND_IGNORE_SIZE. Assigning `.size` smaller than the texture BEFORE that line is
## silently clamped straight back up, so the control renders at the texture's size.
##
## Live instance fixed here: CharacterPortrait draws procedurally at RENDER_SIZE (48), so a
## SMALL (32) portrait rendered at 48 — 50% oversized. SMALL is used by the autobattle grid
## editor, the save screen, and the battle party panel. The artist-sprite path resizes the
## source to _portrait_size and was never affected, which is why the starters look right and
## only jobs without an artist sheet showed it.
##
## KeyItemPopup carries the same ordering; items.json has zero sprite_path entries today so
## it is latent, and it is fixed here rather than left as a trap.

const RENDER_SIZE_EXPECTED: int = 48


func _portrait(size_enum: int) -> Control:
	var PortraitScript = load("res://src/ui/CharacterPortrait.gd")
	# A real customization is required: with null, _build_portrait falls to _build_placeholder
	# (a ColorRect) and never reaches the procedural TextureRect this regression is about.
	var p = PortraitScript.new(CharacterCustomization.new(), "guardian", size_enum)
	add_child_autofree(p)
	return p


func _inner_rect(p: Control) -> TextureRect:
	for c in p.get_children():
		if c is TextureRect:
			return c
	return null


func test_control_procedural_texture_is_larger_than_the_small_slot() -> void:
	# CONTROL: the defect requires RENDER_SIZE > SMALL. If the procedural renderer is ever
	# changed to draw at 32, the clamp cannot fire and the assertion below goes vacuous.
	var PortraitScript = load("res://src/ui/CharacterPortrait.gd")
	var render_size: int = int(PortraitScript.get_script_constant_map().get("RENDER_SIZE", 0))
	assert_eq(render_size, RENDER_SIZE_EXPECTED, "procedural portraits render at 48")
	assert_gt(render_size, 32, "CONTROL: 48 must exceed the SMALL slot, else no clamp occurs")


func test_small_portrait_sprite_is_not_clamped_up_to_the_texture() -> void:
	var PortraitScript = load("res://src/ui/CharacterPortrait.gd")
	var p := _portrait(PortraitScript.PortraitSize.SMALL)
	var inner := _inner_rect(p)
	assert_not_null(inner, "procedural portrait must contain a TextureRect")
	assert_eq(inner.size, Vector2(32, 32),
		"SMALL sprite must honour its 32px slot — a 48px texture clamps it up when expand_mode is set after size")


func test_medium_and_large_unaffected() -> void:
	# MEDIUM equals RENDER_SIZE and LARGE exceeds it, so neither could ever clamp. Pinned so
	# a future change to the fix cannot quietly shrink them.
	var PortraitScript = load("res://src/ui/CharacterPortrait.gd")
	assert_eq(_inner_rect(_portrait(PortraitScript.PortraitSize.MEDIUM)).size, Vector2(48, 48), "MEDIUM unchanged")
	assert_eq(_inner_rect(_portrait(PortraitScript.PortraitSize.LARGE)).size, Vector2(64, 64), "LARGE unchanged")
