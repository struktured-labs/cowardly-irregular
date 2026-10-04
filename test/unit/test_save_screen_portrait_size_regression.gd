extends GutTest

## Playtest 2026-07-14: SaveScreen party portraits rendered at native 256×256
## instead of the intended 32-pixel slot bust, tiling the fighter armor as a
## chaotic body band across every filled save slot (visible in the user's
## screenshot).
##
## Root: `TextureRect.expand_mode = EXPAND_IGNORE_SIZE` +
## `STRETCH_KEEP_ASPECT_CENTERED` didn't reliably clamp the rect to
## SLOT_PORTRAIT_SIZE — the Control tree let the texture render at native
## dims. Fix: scale the TextureRect explicitly via `.scale`
## (SLOT_PORTRAIT_SIZE / max(tex_w, tex_h)), which honors the target size
## regardless of what the layout system does with rect.size.


func test_slot_portrait_uses_explicit_scale_not_expand_ignore() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")
	var i := src.find("func _make_slot_portrait")
	assert_gt(i, -1)
	# Ends at the next top-level declaration — the function after it is `static func`, so a "\nfunc " search found none
	# and a fixed 1400-char window stood in, which two added lines pushed the asserted line out of.
	var next := src.length()
	for decl in ["\nfunc ", "\nstatic func ", "\nstatic var ", "\nvar ", "\nconst "]:
		var at := src.find(decl, i + 1)
		if at > -1:
			next = mini(next, at)
	var body := src.substr(i, next - i)
	assert_true(body.contains("_make_slot_portrait") and not body.contains("func _bust_from_job_sheet"),
		"CONTROL: the body is _make_slot_portrait alone (%d chars)" % body.length())
	assert_true("rect.scale = Vector2(s, s)" in body,
		"portrait rect must set an explicit .scale so 256px textures render at SLOT_PORTRAIT_SIZE regardless of layout quirks")
	assert_false("rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE" in body,
		"the EXPAND_IGNORE_SIZE ASSIGNMENT was the bug — it lets the texture spill to native size when the parent Control has no container-side sizing rules (a docstring mention is fine, the assignment isn't)")
	assert_true("SLOT_PORTRAIT_SIZE / maxf" in body,
		"scale factor must divide SLOT_PORTRAIT_SIZE by the texture's LONGER axis (maxf) so non-square portraits still fit the box")
