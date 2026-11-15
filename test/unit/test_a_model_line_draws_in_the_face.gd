extends GutTest

## A model line reaches display Labels (bubbles) and the reading face (NPC replies). What NEITHER live chain draws is tofu
## everywhere, so clean_model_text drops it; a character either chain draws is never flattened (main 25572, adhoc 25641).
## The second net behind the Latin fallback: a reply in another script is dropped and the caller falls back.

const DRAGON := "龍"


func before_each() -> void:
	UiFont.install(UiFont.READ_TIER_DEFAULT)


func after_each() -> void:
	UiFont.install(UiFont.READ_TIER_DEFAULT)


func _covered(ch: String) -> bool:
	if ch.unicode_at(0) < 128 or UiFont.draws(ch):
		return true
	var chain: Array = UiFont.display().fallbacks.duplicate()
	chain.append(UiFont.body())
	chain.append_array(UiFont.body().fallbacks)
	for f in chain:
		if f is Font and (f as Font).has_char(ch.unicode_at(0)):
			return true
	return false


func test_a_character_no_font_draws_is_dropped() -> void:
	assert_true(UiFont.is_installed(), "CONTROL: the pixel face is installed")
	assert_false(_covered(DRAGON), "PRECONDITION: no font on the display chain draws %s, or this arm proves nothing" % DRAGON)
	var out: String = DialoguePrompts.clean_model_text("Kneel before the %s king." % DRAGON)
	assert_false(out.contains(DRAGON), "the bubble would draw tofu")
	assert_true(out.begins_with("Kneel before the") and out.ends_with("king."), "and the rest of the line stays")


func test_a_reply_in_another_script_leaves_nothing_so_the_fallback_speaks() -> void:
	assert_eq(DialoguePrompts.clean_model_text("%s%s%s" % [DRAGON, DRAGON, DRAGON]), "", "every caller treats empty as fallback")


func test_nothing_the_chain_draws_is_touched() -> void:
	var sample: Array = UiFont.glyph_table().keys()
	for ch in ["—", "–", "…", "’", "“", "”", "·", "→", "É", "Ñ", "Ü", "ß", "×", "★"]:
		sample.append(ch)
	var flattened: Array = []
	var checked: int = 0
	for ch in sample:
		if not _covered(str(ch)) or str(ch).strip_edges() == "":
			continue
		checked += 1
		if DialoguePrompts.display_drawable("a%sb" % ch) != "a%sb" % ch:
			flattened.append(ch)
	assert_gt(checked, 100, "CONTROL: the sample walks the face's whole table plus the model and corpus characters")
	assert_eq(flattened, [], "a character the display chain draws must reach the bubble as written")


func test_the_model_sample_is_drawn() -> void:
	for ch in ["—", "É", "Ñ", "Ü", "ß"]:
		assert_true(_covered(ch), "%s is on the display chain (adhoc's Latin fallback), so the net never fires on it" % ch)
