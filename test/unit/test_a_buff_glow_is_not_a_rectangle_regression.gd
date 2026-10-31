extends GutTest

## Regression: struktured, playing v3.33.745-alpha — "there is like a rectangular frame that
## sometimes appears behind the fighter sprite btw in battles". The buff/debuff glow was a
## hard-edged 40x50 ColorRect at z_index -1 behind a 32x48 party sprite, so it overhung on every
## side and its boundary read as a frame. "Sometimes" was: whenever that character held a buff or
## a debuff. _create_buff_visual's own comment said "Glow rectangle behind sprite".

const BS := preload("res://src/battle/BattleScene.gd")


func test_the_glow_fades_to_nothing_before_its_own_edge() -> void:
	## THE DEFECT, measured in pixels rather than asserted in prose: a glow has no boundary. The
	## old ColorRect was one flat alpha across the whole 40x50, so its edge was its outline.
	var img: Image = BS.buff_glow_texture().get_image()
	assert_not_null(img, "the buff glow texture produced no image")
	var w: int = img.get_width()
	var h: int = img.get_height()
	var center: float = img.get_pixel(w / 2, h / 2).a
	var corner: float = img.get_pixel(0, 0).a
	var edge_mid: float = img.get_pixel(w - 1, h / 2).a
	assert_gt(center, 0.9, "the glow is not opaque at its centre (alpha %.3f) — nothing to see" % center)
	assert_almost_eq(corner, 0.0, 0.02, "the glow's CORNER is alpha %.3f — a visible edge is the frame he saw" % corner)
	assert_almost_eq(edge_mid, 0.0, 0.02, "the glow's edge midpoint is alpha %.3f — still a hard boundary" % edge_mid)


func test_a_flat_fill_would_fail_that_arm() -> void:
	## THE CONTROL, in-test: the predicate above must be able to fail. A uniform fill — which is
	## exactly what the shipped ColorRect was — has to flunk the corner assertion.
	var flat := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.2, 0.9, 0.7, 1.0))
	assert_gt(flat.get_pixel(0, 0).a, 0.02,
		"a flat fill passed the corner check — the measurement cannot see the defect it exists for")


func test_the_falloff_is_radial_and_covers_the_body() -> void:
	var tex: GradientTexture2D = BS.buff_glow_texture()
	assert_eq(tex.fill, GradientTexture2D.FILL_RADIAL,
		"a linear fill leaves two hard edges — the falloff must be radial")
	assert_eq(Vector2i(tex.width, tex.height), BS.BUFF_GLOW_SIZE,
		"the glow texture no longer matches BUFF_GLOW_SIZE")
	## Wider than a 32x48 party sprite, so the soft part lands outside the silhouette rather
	## than dimming the character.
	assert_gt(tex.width, 32, "the glow is narrower than the sprite it sits behind")
	assert_gt(tex.height, 48, "the glow is shorter than the sprite it sits behind")


func test_the_gradient_ends_transparent_at_both_declared_stops() -> void:
	var grad: Gradient = BS.buff_glow_texture().gradient
	assert_not_null(grad, "the glow texture has no gradient")
	assert_almost_eq(grad.sample(0.0).a, 1.0, 0.01, "gradient does not start opaque")
	assert_almost_eq(grad.sample(1.0).a, 0.0, 0.01, "gradient does not end transparent")


func test_one_texture_is_shared_by_every_combatant() -> void:
	## modulate carries the per-combatant colour, so a second texture per party member would be
	## five identical resources for nothing.
	assert_eq(BS.buff_glow_texture().get_instance_id(), BS.buff_glow_texture().get_instance_id(),
		"buff_glow_texture built a second texture instead of sharing one")


func test_the_glow_node_actually_uses_it() -> void:
	## The texture being soft is worth nothing if the node ignores it. Source-level on purpose:
	## _create_buff_visual needs a live BattleScene, and what this has to pin is which of the two
	## shapes the call site builds — a question the text answers exactly.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var idx: int = src.find("func _create_buff_visual")
	assert_gt(idx, -1, "_create_buff_visual is gone")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2000)
	assert_string_contains(body, "buff_glow_texture()",
		"the glow node must take the shared radial texture")
	assert_false(body.contains("ColorRect.new()\n\tglow") or body.contains("glow = ColorRect.new()"),
		"the glow is a ColorRect again — that flat rect IS the frame behind the sprite")
	assert_string_contains(body, "glow.modulate",
		"a Sprite2D carries its colour on modulate; glow.color would silently do nothing")
