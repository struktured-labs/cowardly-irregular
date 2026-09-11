extends GutTest

## test_font_fallback_chain pins a HAND-TYPED glyph string. This derives the same question from the prose players actually read.

const CUTSCENE_DIR := "res://data/cutscenes"


func _font_chain() -> Array:
	var base := ThemeDB.fallback_font
	var chain: Array = [base]
	for f in base.fallbacks:
		chain.append(f)
	return chain


func _covered(ch: String, chain: Array) -> bool:
	for f in chain:
		if f != null and f.has_char(ch.unicode_at(0)):
			return true
	return false


## Every string a player can read in a cutscene: narration lines, dialogue, card titles.
func _player_strings() -> Array:
	var out: Array = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, fname]))
		if not (parsed is Dictionary):
			continue
		for step in (parsed as Dictionary).get("steps", []):
			if not (step is Dictionary):
				continue
			var s: Dictionary = step
			for key in ["text", "title", "name", "subtitle"]:
				if s.get(key) is String:
					out.append(str(s[key]))
			for line in s.get("lines", []):
				if line is String:
					out.append(str(line))
				elif line is Dictionary:
					out.append(str((line as Dictionary).get("text", "")))
	return out


## Non-ASCII characters actually used, mapped to one example scene each.
func _prose_glyphs() -> Dictionary:
	var out: Dictionary = {}
	for s in _player_strings():
		for i in s.length():
			var ch: String = s[i]
			if ch.unicode_at(0) > 127:
				out[ch] = int(out.get(ch, 0)) + 1
	return out


func test_the_prose_scan_reaches_the_corpus() -> void:
	var strings := _player_strings()
	assert_gt(strings.size(), 2000,
		"CONTROL: the cutscene corpus is the largest body of player text in the game; found %d strings" % strings.size())
	var joined := " ".join(strings)
	assert_true(joined.contains("—"),
		"CONTROL: the em dash is known to be present in cutscene prose — if this fails the scan is not reading text")
	assert_false(joined.contains("░"),
		"CONTROL: a fabricated glyph must not be found")


func test_every_glyph_in_cutscene_prose_resolves_in_the_font_chain() -> void:
	var chain := _font_chain()
	assert_gt(chain.size(), 1, "CONTROL: the fallback chain must have fallbacks to be worth testing")
	var glyphs := _prose_glyphs()
	assert_gt(glyphs.size(), 0, "CONTROL: the prose must contain non-ASCII characters at all")
	var missing: Array = []
	for ch in glyphs:
		if not _covered(str(ch), chain):
			missing.append("%s (U+%04X, %d uses)" % [ch, str(ch).unicode_at(0), int(glyphs[ch])])
	missing.sort()
	assert_eq(missing, [],
		("a character in cutscene prose has no coverage anywhere in the font chain, so it renders as tofu "
		+ "for every player who reads that line. AUTHORED_GLYPHS is hand-typed — it pins what someone "
		+ "remembered, and the em dash carrying most of this game's punctuation was never in it. This arm "
		+ "derives the corpus from the prose instead. Missing: %s") % str(missing))


func test_the_prose_glyphs_are_the_ones_we_think() -> void:
	var glyphs := _prose_glyphs()
	var ids: Array = []
	for ch in glyphs:
		ids.append("U+%04X" % str(ch).unicode_at(0))
	ids.sort()
	assert_eq(ids, ["U+2014", "U+2026"],
		("the set of non-ASCII characters in cutscene prose changed. That is not a failure — new punctuation "
		+ "is fine — but each new one must resolve in the font chain, and a scene authored by pasting from a "
		+ "word processor is how curly quotes and non-breaking spaces arrive unnoticed. Found: %s") % str(ids))
