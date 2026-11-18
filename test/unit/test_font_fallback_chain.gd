extends GutTest

## Proof for the FontFallbacks autoload (tofu fix 2026-07-10): the default
## UI font must carry the Noto fallback chain, and every glyph family the
## codebase actually authors (2026-07-10 sweep of src/ string literals)
## must resolve SOMEWHERE in base+chain. Before this, all of these were
## boxes on web: battle icons, element icons, menu markers, grid-editor
## arrows, virtual-keyboard keys.

## One representative per authored glyph block; the sweep found ~58 chars.
const AUTHORED_GLYPHS := "→↑↓←⚠▶▸▼▲✓✦►✗★⚙◀⚔☠◉⚒─═♪⚡∅◄✎●○◦💬■□⌫⇧↻⊞👑◂✖⧗🛡🔍🔥❄🌑🌀💧♥◤◥◣◢🕳◇♦◈"


func _font_chain() -> Array:
	var base := ThemeDB.fallback_font
	var chain: Array = [base]
	for f in base.fallbacks:
		chain.append(f)
	return chain


func test_fallback_chain_is_wired() -> void:
	assert_true(get_node_or_null("/root/FontFallbacks") != null,
		"FontFallbacks autoload must be registered")
	assert_gte(ThemeDB.fallback_font.fallbacks.size(), 4,
		"default font must chain Symbols2 + Symbols + Math + Emoji fallbacks")


func test_every_authored_glyph_resolves_in_chain() -> void:
	var chain := _font_chain()
	var missing := ""
	for ch in AUTHORED_GLYPHS:
		var found := false
		for f in chain:
			if f != null and f.has_char(ch.unicode_at(0)):
				found = true
				break
		if not found:
			missing += ch
	assert_eq(missing, "",
		"authored glyphs with no coverage anywhere in the font chain (tofu): '%s'" % missing)


## main 25569/25570: a model's bark or gloat reaches a display Label (the speech bubble, the gloat box), so the
## characters models write that the pixel face does not draw must still resolve behind it. The authored corpus is
## test_every_rendered_glyph_resolves_regression's job (derived); this is the sample no corpus contains.
const LLM_SAMPLE := "ÉÑÜßÀÇØ—"
const CJK_PROBE := "中"


func test_what_a_model_writes_resolves_behind_the_pixel_face() -> void:
	assert_true(UiFont.is_installed(), "CONTROL: the pixel face is installed, so this walks ITS chain")
	var face: Font = UiFont.display()
	var chain: Array = [face]
	chain.append_array(face.fallbacks)
	var missing := ""
	for ch in LLM_SAMPLE:
		var found := false
		for f in chain:
			if f != null and f.has_char(ch.unicode_at(0)):
				found = true
				break
		if not found:
			missing += ch
	assert_eq(missing, "", "characters a model writes that would draw as tofu in a display Label: '%s'" % missing)
	var cjk := false
	for f in chain:
		cjk = cjk or (f != null and f.has_char(CJK_PROBE.unicode_at(0)))
	gut.p("INFO: CJK '%s' resolves behind the pixel face: %s (no CJK font ships; not required)" % [CJK_PROBE, cjk])
