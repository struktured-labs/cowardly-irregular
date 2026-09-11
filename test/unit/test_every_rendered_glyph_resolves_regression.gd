extends GutTest

## The day clock rendered BOXES for dawn, dusk and night — three quarters of the cycle, on the main
## scene's HUD. `NotoEmoji-Regular.ttf` is an 8.5 KB subset carrying twelve glyphs and 🌅🌇🌙 are not
## among them. ☀ never came from it either; it resolves from NotoSansSymbols, which is why the one
## band that worked was the one that is not an emoji.
##
## ⛔ WHY test_font_fallback_chain COULD NOT CATCH IT — a closed loop, and the tell is a number
## nobody looks twice at:
##     52 glyphs pinned in AUTHORED_GLYPHS  ->  52 of 52 covered     perfect agreement
##     30 unpinned                          ->   5 uncovered
## Perfect agreement is what you get when the font subset was generated FROM the pin list. That
## guard asserts "everything in my hand-typed list resolves" against an asset built from that list:
## it passes by construction and is blind to precisely one thing — a glyph the game USES that
## neither list contains, which is the entire population of real defects.
##
## So this guard derives its corpus from the SOURCE instead of from a list anyone maintains. It has
## no exemptions by design; the two glyphs that would have needed one (│ ├, in a docstring diagram)
## were converted to ASCII rather than allowlisted, because an exemption is how the loop re-forms.

const SRC_ROOT := "res://src"

var _file_count: int = 0


## Comments are excluded because they never render — 🅰 🅱 🔑 🔴 all live in comment prose and
## flagging them would make this guard cry about text no player can see, which is how a guard gets
## suppressed. Quote-aware so a '#' inside a string literal cannot truncate real text.
func _strip_comment(line: String) -> String:
	var esc := false
	var quote := ""
	for i in range(line.length()):
		var c := line[i]
		if esc:
			esc = false
			continue
		if c == "\\":
			esc = true
		elif quote != "":
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _gd_files(root: String, out: Array) -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := root + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_gd_files(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = d.get_next()
	d.list_dir_end()


## GDScript source may spell a glyph as a literal OR as a \\uXXXX escape, and the two sibling grid
## editors use OPPOSITE conventions — @cowir-autogrind's grep for the character came back empty on
## @cowir-battle's converted file and read as "never changed". A corpus that counts only literals is
## blind to every file written in the other style. (data/**.json needs no equivalent: the JSON parser
## decodes escapes for free — @cowir-overworld.)
func _resolve_escapes(line: String) -> String:
	var out := line
	var at := out.find("\\u")
	while at >= 0 and at + 6 <= out.length():
		var hex := out.substr(at + 2, 4)
		if hex.is_valid_hex_number():
			out = out.substr(0, at) + char(hex.hex_to_int()) + out.substr(at + 6)
			at = out.find("\\u", at + 1)
		else:
			at = out.find("\\u", at + 1)
	return out


## Every non-ASCII character that survives comment-stripping, with one example path each.
func _rendered_glyphs() -> Dictionary:
	var files: Array = []
	_gd_files(SRC_ROOT, files)
	_file_count = files.size()
	assert_gt(files.size(), 200, "PRECONDITION: the walk must reach src/ — a short list scans nothing")
	var glyphs := {}
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for raw in text.split("\n"):
			for ch in _resolve_escapes(_strip_comment(raw)):
				if ch.unicode_at(0) > 127 and not glyphs.has(ch):
					glyphs[ch] = path
	return glyphs


func _chain() -> Array:
	var chain: Array = [ThemeDB.fallback_font]
	for f in ThemeDB.fallback_font.fallbacks:
		chain.append(f)
	return chain


func _covered(ch: String, chain: Array) -> bool:
	for f in chain:
		if f != null and f.has_char(ch.unicode_at(0)):
			return true
	return false


## THE DEFECT. Every glyph the game can draw must resolve somewhere in the chain.
func test_no_glyph_the_game_renders_is_tofu() -> void:
	var chain := _chain()
	var glyphs := _rendered_glyphs()
	var tofu: Array[String] = []
	for ch in glyphs:
		if not _covered(ch, chain):
			tofu.append("%s (U+%04X, first seen %s)" % [ch, ch.unicode_at(0), str(glyphs[ch]).get_file()])
	# @cowir-adhoc: print the parser's SELF-ASSESSMENT beside its answer. This is not a denominator
	# for the unknown-unknown — nothing is — but it makes "I know of two spellings" a sentence a
	# reader can look at and say "there is a third". Every blind spot found in this fleet today
	# arrived from outside; a printed count is what an outsider needs in order to hand you one.
	gut.p("glyph corpus: %d distinct, from %d files | spellings recognised: 2 (literal, \\uXXXX) | comments excluded"
		% [glyphs.size(), _file_count])
	assert_eq(tofu, [] as Array[String],
		"glyphs with no coverage anywhere in the font chain render as BOXES to the player: %s" %
		", ".join(tofu))


## CONTROL. The probe must return BOTH answers, or "no tofu" is unfalsifiable — a chain that
## answered true for everything, or a null chain answering false for everything, both pass an
## arm that only ever sees one value. @cowir-adhoc's pair, adopted.
func test_the_coverage_probe_discriminates() -> void:
	var chain := _chain()
	assert_gt(chain.size(), 4, "FontFallbacks must have installed the chain — a bare font proves nothing")
	assert_true(_covered("A", chain), "CONTROL: the probe must return TRUE for a certainty")
	assert_false(_covered("", chain),
		"CONTROL: the probe must return FALSE for a private-use codepoint, or it cannot report tofu")


## The corpus must actually contain the things this lane emits. A derived corpus can silently shrink
## — a walk that broke would report zero tofu over zero glyphs — so membership is NAMED, not counted.
func test_the_corpus_reaches_the_glyphs_this_game_actually_uses() -> void:
	var glyphs := _rendered_glyphs()
	assert_gt(glyphs.size(), 60, "the derived corpus collapsed; it should hold ~78 distinct glyphs")
	for pair in [["Ⓑ", "InputProfileManager FACE_GLYPHS"], ["☾", "DayClockWidget BAND_GLYPH"],
			["↑", "a navigation legend"], ["✕", "the PlayStation cancel face"]]:
		assert_true(glyphs.has(pair[0]),
			"the corpus must reach %s (%s) — if it does not, this guard is green about nothing" % pair)


## The defect's own shape, pinned: the day clock must not go back to glyphs the subset lacks.
## Named rather than derived, because this is the specific regression.
func test_the_day_clock_bands_are_all_covered() -> void:
	var chain := _chain()
	var src := FileAccess.get_file_as_string("res://src/ui/DayClockWidget.gd")
	var at := src.find("const BAND_GLYPH")
	assert_gt(at, -1, "PRECONDITION: BAND_GLYPH must exist")
	var line := src.substr(at, src.find("\n", at) - at)
	for ch in line:
		if ch.unicode_at(0) > 127:
			assert_true(_covered(ch, chain),
				"day-clock band glyph %s (U+%04X) is not in the font chain — it draws as a box" %
				[ch, ch.unicode_at(0)])


## THE ESCAPE RESOLVER'S OWN TEST. Measured 2026-09-11: NO glyph in src/ is reachable only through
## an escape (2 appear both ways, 0 exclusively), so the corpus CANNOT exercise this path — it is
## correct by luck, not by coverage, which is the distinction @cowir-overworld drew about their own
## sweep. Pinned directly, both directions, so it cannot rot into a no-op nobody notices.
func test_the_escape_resolver_resolves_and_preserves() -> void:
	var bs := "\\"
	# RESOLVES: the spelling @cowir-battle's converted editor uses.
	assert_eq(_resolve_escapes(bs + "u2191"), "↑", "a \\uXXXX escape must become its character")
	assert_eq(_resolve_escapes("a" + bs + "u25d1b"), "a◑b", "…mid-string, with text either side")
	assert_eq(_resolve_escapes(bs + "u2191" + bs + "u2193"), "↑↓", "…twice in one line")
	# PRESERVES: anything that is not a complete escape must survive untouched.
	assert_eq(_resolve_escapes("no escapes here"), "no escapes here", "plain text is unchanged")
	assert_eq(_resolve_escapes(bs + "uZZZZ"), bs + "uZZZZ", "a non-hex run must NOT be consumed")
	assert_eq(_resolve_escapes(bs + "u21"), bs + "u21", "a truncated escape must not be consumed")
	assert_eq(_resolve_escapes("↑ already literal"), "↑ already literal", "a literal glyph is kept")
	# And an ASCII escape resolves but contributes nothing to the corpus, which is correct.
	assert_eq(_resolve_escapes(bs + "u0041"), "A", "an ASCII escape resolves like any other")
