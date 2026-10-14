extends GutTest

## 🐛 ELEVEN PROPS HAND-ROLLED THE SAME FLOATING TOAST, AND THE COPIES HAD TWO DEFECTS.
##
## HEIGHT WAS AUTHORED, NOT MEASURED. At font 11 against each authored box: CivicFrontDesk needs
## 48 px of 34, and MissingPackage / SwordInscription / TallyWall / WildflowerPatch need 32 of 18.
## A Label does not clip, so the overflow drew DOWNWARD over the prop being read and the player at
## it. CivicFrontDesk already WRAPPED — which is why "make them wrap" was the wrong diagnosis.
##
## WIDTH WAS A FLOOR, NOT A CAP. Four set no autowrap, and `Control.size` clamps UP to
## `get_combined_minimum_size()`, which for an unwrapped Label is the whole string. The label grew
## past its box while `position.x` stayed at `-width / 2`, centring the BOX and not the TEXT:
## measured drift SwordInscription +114 px, WildflowerPatch +94, MissingPackage +64, TallyWall +22.
##
## ⚠️ ARM 2 MEASURES TEXT AGAINST THE BUILT LABEL'S BOX, never a font metric against an authored
## number. `box >= font.get_height(px)` reds correct layout, because a Label clamps its own height
## up to its content (cowir-story, measured). And arm 3 is the mutation that proves arm 2 reads
## text rather than a box: SHRINK THE CONTAINER, LEAVE THE FONT. If the extent shrinks with it the
## arm was about a box; it must stay at the glyph height.
##
## 📌 The width assert is the centring half: a label whose `size.x` exceeds its authored width has
## clamped up, which is exactly how the drift came back.

const PRESETS := [0.8, 1.0, 1.25, 1.5, 2.0]
const LONG := "A notice long enough to need more than one line at any text size the settings offer."

## ⛔ THE CALLER LIST IS DERIVED, NOT WRITTEN. It was twelve hand-typed literals, equal to the
## twelve live call sites and with nothing keeping them equal — and this very item adds a
## thirteenth, which is exactly the case a hand-list misses. Worse, my refactor REMOVED
## `Label.new()` from every caller, so a node-based census now sees only `WorldToast.gd`: the
## helper hid its own callers from the scan that found them.
##
## ⚠️ AND KEYING ON THE METHOD NAME WOULD MISS ONE TOO. `HiddenPassage`'s toast lives in
## `_shimmer_away`, not `_toast` — that is why the original census of twelve missed it. So the
## derivation keys on the HELPER (`WorldToast.show(`), which is the one name every caller must
## spell, and the scene-driven sweep then asks each prop whether it HAS a `_toast` to drive.
const CALL := "WorldToast.show("
const DIRS := ["res://src/exploration/", "res://src/maps/villages/", "res://src/maps/interiors/", "res://src/maps/dungeons/"]


static func _caller_paths() -> Array:
	var out: Array = []
	for d in DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for fn in da.get_files():
			if not str(fn).ends_with(".gd"):
				continue
			var path: String = d + str(fn)
			if FileAccess.get_file_as_string(path).contains(CALL):
				out.append(path)
	out.sort()
	return out


var _vp: SubViewport = null
var _saved_scale: float = 1.0


func before_all() -> void:
	_saved_scale = float(GameState.text_size_scale) if "text_size_scale" in GameState else 1.0


func after_all() -> void:
	if "text_size_scale" in GameState:
		GameState.text_size_scale = _saved_scale


func _scale(s: float) -> void:
	GameState.text_size_scale = s


func _host() -> SubViewport:
	if _vp == null or not is_instance_valid(_vp):
		_vp = SubViewport.new()
		_vp.size = Vector2i(64, 64)
		_vp.world_2d = World2D.new()
		add_child_autofree(_vp)
	return _vp


## The prop's OWN longest authored toast string, read from its source. Empty when it builds its
## strings at runtime (FireplaceSecret, LockedDoorFlavor) — those are driven with LONG instead.
func _worst_authored(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	## ⚠️ TWO CALL SHAPES, because a converted caller may pass its literal to the HELPER rather
	## than to its own `_toast`. `HiddenPassage` does exactly that, and keying only on `_toast(`
	## scored it as having no authored string — the control caught that rather than me.
	var worst := ""
	for pattern in ['_toast\\(\\s*"((?:[^"\\\\]|\\\\.)*)"', 'WorldToast\\.show\\(\\s*\\w+,\\s*"((?:[^"\\\\]|\\\\.)*)"']:
		var rx := RegEx.create_from_string(pattern)
		for m in rx.search_all(src):
			if m.get_string(1).length() > worst.length():
				worst = m.get_string(1)
	return worst


## Drive the REAL prop's own `_toast` and hand back the Label THAT CALL ADDED.
##
## ⛔ NOT "the first Label child". Nine of these eleven props build an `_indicator` Label in
## `_ready` — the world-space press prompt — so taking the first Label measured the INDICATOR and
## never the toast. My first version did, and the whole sweep went green about the wrong node:
## QuestChicken was the only caller reported correctly, because it is the one with no indicator.
## The shrink-the-container mutation naming exactly one of eleven is what exposed it.
func _toast_label(path: String, text: String) -> Label:
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return null
	var prop = scr.new()
	## ⚠️ ASK BEFORE CALLING. Not every caller exposes `_toast(text)` — `HiddenPassage`'s toast
	## is in `_shimmer_away()` and takes none — and an unguarded call is a GDScript error that
	## ABORTS this function. The null it then returns is indistinguishable from "built no Label",
	## so the sweep reported a clean skip while the log filled with errors.
	if not scr.new().has_method("_toast"):
		prop.free()
		return null
	_host().add_child(prop)
	await get_tree().process_frame
	var before: Dictionary = {}
	for c in prop.get_children():
		before[c.get_instance_id()] = true
	prop._toast(text)
	await get_tree().process_frame
	for c in prop.get_children():
		if c is Label and not before.has(c.get_instance_id()):
			return c
	return null


func test_the_font_grows_and_shrinks_with_the_setting() -> void:
	_scale(1.0)
	var base := WorldToast.font_size()
	_scale(2.0)
	var big := WorldToast.font_size()
	_scale(0.8)
	var small := WorldToast.font_size()
	_scale(1.0)
	assert_gt(big, base, "the toast font must GROW at 200%% (got %d vs %d)" % [big, base])
	assert_lt(small, base, "the toast font must SHRINK at 80%% (got %d vs %d)" % [small, base])
	gut.p("  font 80%%/100%%/200%% = %d / %d / %d" % [small, base, big])
	## ⛔ AND THE BASE MUST REACH THE RESULT, AT EVERY PRESET. Eleven callers author 11 and
	## `HiddenPassage` authors 12, so a `font_size(base)` that ignored its argument would render it
	## a point small with every other arm green — measured: the mutation that drops the parameter
	## passed 5/5 before this existed. Three bases, ordered, is the whole check.
	var flat: Array = []
	for sc in PRESETS:
		_scale(sc)
		var a: int = WorldToast.font_size(11)
		var b: int = WorldToast.font_size(12)
		var c: int = WorldToast.font_size(14)
		if not (c > b and b > a):
			flat.append("@%.2fx base 11/12/14 gave %d/%d/%d — the base does not reach the result" % [sc, a, b, c])
	_scale(1.0)
	assert_eq(flat, [], "the authored base font must survive scaling: %s" % "; ".join(flat))
	gut.p("  base 11/12/14 stay ordered at all %d presets" % PRESETS.size())


## ⛔ THE ARM THAT MATTERS: every caller's real toast, at every preset the player can pick, with
## its own longest authored string AND a long synthetic one, fits the box the prop gave it.
func test_every_toast_fits_its_box_at_every_preset() -> void:
	var bad: Array = []
	var bottoms: Dictionary = {}
	var widths: Dictionary = {}
	var checked := 0
	var authored := 0
	var no_toast: Array = []
	for path in _caller_paths():
		var name: String = path.get_file().get_basename()
		var own := _worst_authored(path)
		if own != "":
			authored += 1
		for s in PRESETS:
			_scale(s)
			for text in ([own, LONG] if own != "" else [LONG]):
				var lbl: Label = await _toast_label(path, text)
				if lbl == null:
					## No `_toast(text)` to drive — HiddenPassage's is `_shimmer_away()` and takes
					## none. Recorded, not failed: the source arm below covers every call site
					## regardless of the method name it sits in.
					if not (name in no_toast):
						no_toast.append(name)
					continue
				checked += 1
				## ⛔ WIDTH IS CHECKED AS AN INVARIANT, NOT AGAINST A TABLE. The authored width used
				## to come from a hand-written dict; the derivation has no such number, and it does
				## not need one: a wrapping label stays at its box width at EVERY preset, while an
				## unwrapped one takes its text's width and therefore GROWS with the font. So
				## "constant across presets" catches the clamp without anyone writing the width down
				## — and it is what the no-autowrap mutation reds.
				if not widths.has(name):
					widths[name] = {}
				(widths[name] as Dictionary)[s] = lbl.size.x
				## ⛔ THE BOTTOM EDGE, NOT "DOES THE TEXT FIT THE BOX". That comparison is HOLLOW here
				## and the shrink-the-container mutation is what showed it: `Control.size` clamps UP
				## to the content, so `lbl.size.y` becomes the text height whatever the caller
				## assigned, and text-vs-box is green in both worlds. What the defect actually did
				## was draw DOWNWARD over the prop, so the invariant is that the authored bottom
				## edge does not move — asserted as INVARIANCE ACROSS PRESETS, which needs no copy
				## of any caller's baseline or floor here.
				var bottom: float = lbl.position.y + lbl.size.y
				if not bottoms.has(name):
					bottoms[name] = {}
				(bottoms[name] as Dictionary)[s] = bottom
	_scale(1.0)
	## A toast anchors to the prop: its bottom edge is authored and must not move when the font
	## does. Under the fix it is one number per caller across all five presets.
	for name in bottoms:
		var per: Dictionary = bottoms[name]
		var vals: Array = per.values()
		var lo: float = vals.min()
		var hi: float = vals.max()
		## ⚠️ 2 px, NOT 0 px, AND THE NUMBER IS MEASURED. `height_for` measures off the FONT
		## (`get_multiline_string_size`) while the Label clamps `size.y` to its own
		## `get_combined_minimum_size()`, and the two disagree by up to a pixel of rounding —
		## `LockedDoorFlavor` reported -29..-28 across the presets on a correct tree. That is the
		## metric-vs-content gap @cowir-story measured on title cards and @cowir-adhoc on lens rows,
		## landing on a tolerance instead of a layout. **It keeps its teeth because the defect it
		## guards moves the edge 14 px at the floor and 124 px at 2.0x** — two orders off this.
		if absf(hi - lo) > 2.0:
			bad.append("%s bottom edge MOVES across presets: %.0f..%.0f — a taller toast grew DOWN over the prop instead of up (%s)" % [
				name, lo, hi, str(per)])
	for name in widths:
		var wper: Dictionary = widths[name]
		var wv: Array = wper.values()
		if absf(float(wv.max()) - float(wv.min())) > 2.0:
			bad.append("%s width GROWS with the font: %.0f..%.0f — the label took its text's width instead of its box, so the box is centred and the text is not (%s)" % [
				name, float(wv.min()), float(wv.max()), str(wper)])
	no_toast.sort()
	for n in no_toast:
		gut.p("  no _toast(text) to drive, covered by the source arm: %s" % n)
	assert_eq(authored, 11,
		"CONTROL: 11 of the 13 callers must carry authored toast literals (found %d); FireplaceSecret and LockedDoorFlavor build theirs at runtime" % authored)
	assert_gt(checked, 90,
		"CONTROL: only %d toasts were built across %d callers x %d presets; the sweep did not run" % [checked, _caller_paths().size(), PRESETS.size()])
	bad.sort()
	for b in bad:
		gut.p("  OVERFLOW %s" % b)
	assert_eq(bad, [],
		"%d toast(s) do not fit the box their prop gave them: %s" % [bad.size(), "; ".join(bad)])
	gut.p("  %d toasts built across %d callers x %d presets, every bottom edge held across all five" % [checked, _caller_paths().size(), PRESETS.size()])


## ⛔ CONTROL ON THE SHAPE: the authored BOTTOM edge is held, so a taller toast rises away from the
## player instead of growing down over them. Pinning the top is the defect this replaces.
func test_a_taller_toast_grows_upward() -> void:
	_scale(1.0)
	var short_top: float = WorldToast.top_for("Short.", 260.0, -52.0, 18.0)
	var tall_h: float = WorldToast.height_for(LONG, 260.0, 18.0)
	var tall_top: float = WorldToast.top_for(LONG, 260.0, -52.0, 18.0)
	assert_gt(tall_h, 18.0, "CONTROL: the long string must exceed the floor, else this proves nothing")
	assert_eq(short_top, -52.0, "a toast at the floor height must sit exactly where it was authored")
	assert_lt(tall_top, short_top, "a taller toast must rise: top %.0f should be above %.0f" % [tall_top, short_top])
	assert_almost_eq(tall_top + tall_h, short_top + 18.0, 0.5,
		"the authored BOTTOM edge must be held: %.0f vs %.0f" % [tall_top + tall_h, short_top + 18.0])
	gut.p("  floor top %.0f; %.0f px block tops at %.0f, same bottom edge" % [short_top, tall_h, tall_top])


## ⛔ THE SEAM AND THE BUILT NODE MUST AGREE, AND THIS ARM EXISTS BECAUSE THEY ONCE COULD NOT
## DISAGREE. `show` re-derived the origin inline beside `origin_for` — two expressions for one
## quantity, in the helper whose purpose is collapsing eleven of them. They matched, so nothing
## could fail; that is the CONDITION for a drift, not a drift, and changing the rule in one place
## would have left the other silently on the old one. Both now route through `origin_for_height`,
## and this compares what `show` BUILT against what the public seam PREDICTS so they cannot part.
##
## 📌 No await between `show` and the read: the tween it starts animates `position:y`, so a frame
## of settling would measure the animation rather than the placement.
func test_show_places_the_label_where_the_seam_says() -> void:
	_scale(1.0)
	var host := Node2D.new()
	add_child_autofree(host)
	await get_tree().process_frame
	var pairs := 0
	for text in ["Short.", LONG]:
		for mh in [18.0, 34.0, 48.0]:
			var want: Vector2 = WorldToast.origin_for(text, 260.0, -52.0, mh)
			var lbl: Label = WorldToast.show(host, text, 260.0, -52.0, Color.WHITE, mh, 20.0, 1.6, 0.6)
			assert_not_null(lbl, "CONTROL: show must build a Label (%d chars, floor %.0f)" % [text.length(), mh])
			if lbl == null:
				continue
			pairs += 1
			assert_almost_eq(lbl.position.x, want.x, 0.01,
				"x drifted: show built %.2f, the seam says %.2f" % [lbl.position.x, want.x])
			assert_almost_eq(lbl.position.y, want.y, 0.01,
				"y drifted: show built %.2f, the seam says %.2f (%d chars, floor %.0f)" % [
					lbl.position.y, want.y, text.length(), mh])
			lbl.queue_free()
			await get_tree().process_frame
	assert_eq(pairs, 6, "CONTROL: all six (text x floor) pairs must have been built, got %d" % pairs)
	## And the long string must actually exceed at least one floor, or every pair is the trivial case.
	assert_gt(WorldToast.height_for(LONG, 260.0, 18.0), 18.0,
		"CONTROL: the long string must exceed the 18 px floor, else the arm only tests h == min_h")
	gut.p("  %d (text x floor) pairs, show and the seam agree on every one" % pairs)


## ⛔ THE SOURCE ARM: every `WorldToast.show(` CALL SITE, whatever method it sits in. The sweep
## above drives each prop's `_toast(text)`, and `HiddenPassage` has none — its toast is in
## `_shimmer_away()` and takes no argument — so without this arm the thirteenth caller is derived
## into the list and then never exercised.
##
## ⚠️ WHAT IT ASSERTS IS NOT "the text fits", which wrapping makes true by construction. It is
## that NO SINGLE TOKEN IS WIDER THAN THE BOX. Autowrap breaks between words and cannot break
## inside one, so one long word takes the label's minimum width past its box and the centring drift
## returns — @cowir-autogrind measured exactly that on a grid cell ("Hallucination", 13 chars) and
## @cowir-controller checked the converse on 289 abilities ("no real token is unbreakable").
## At 2.0x every token is twice as wide, which is why this sweeps the presets rather than the default.
## One token's drawn width at a given size, off the theme font a Label would use. Measured from the
## FONT rather than a node, per @cowir-autogrind: a node's content minimum lands on a deferred pass
## whose timing depends on the order its properties were set, so reading a rect back is unreliable.
func _token_width(word: String, fs: int) -> float:
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	var w := 0.0
	if font != null:
		w = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	probe.free()
	return w


func test_no_authored_token_is_wider_than_its_own_box() -> void:
	var rx := RegEx.create_from_string('WorldToast\\.show\\(\\s*\\w+,\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*,\\s*([0-9]+\\.?[0-9]*)')
	var over: Array = []
	var uncovered: Array = []
	var pairs := 0
	var symbolic := 0
	for path in _caller_paths():
		var src := FileAccess.get_file_as_string(path)
		var name: String = path.get_file().get_basename()
		var found := false
		for m in rx.search_all(src):
			found = true
			var text: String = m.get_string(1)
			var width: float = float(m.get_string(2))
			for sc in PRESETS:
				_scale(sc)
				## ⛔ MEASURED AT THE DEFAULT BASE, DELIBERATELY. The first version read
				## `font_size(12) if name == "HiddenPassage"` — a second copy of BOTH the caller's
				## name and its authored base, which is the duplication this whole item exists to
				## remove, reintroduced inside its own guard. A caller with a larger base is
				## therefore under-measured by that ratio (12/11, ~9%), and that is acceptable here
				## only because the margin is not marginal: its widest token is ~56 px against a
				## 104 px box. If a future caller's token approaches its box this arm must parse the
				## base from the call site instead of assuming it.
				var fs: int = WorldToast.font_size()
				for word in text.split(" ", false):
					var w: float = _token_width(word, fs)
					pairs += 1
					if w > width + 0.5:
						over.append("%s @%.2fx token '%s' is %.0f px against a %.0f px box — autowrap cannot break inside a word, so the label takes the token's width and the toast drifts %+.0f px" % [
							name, sc, word, w, width, (w - width) * 0.5])
		if not found:
			symbolic += 1
			## ⛔ THE COVERAGE RELATIONSHIP, which replaced a guessed magnitude. My first control
			## here was `pairs > 200` and it RED: of thirteen call sites only ONE passes both a
			## literal text and a literal width, because the other twelve take `text` as an
			## argument. The number was invented; what matters is that no caller falls between the
			## two arms — the sweep drives anything with `_toast(text)`, this one covers literal
			## call sites, and a caller with NEITHER would be derived into the list and never run.
			if not src.contains("func _toast("):
				uncovered.append(name)
	_scale(1.0)
	uncovered.sort()
	assert_eq(uncovered, [],
		"%d caller(s) are covered by NEITHER arm — no `_toast(text)` for the sweep to drive and no literal call site for this arm: %s" % [
			uncovered.size(), ", ".join(uncovered)])
	assert_gt(pairs, 0,
		"CONTROL: no (token x preset) pair measured at all; the regex matched no literal call site")
	over.sort()
	for o in over:
		gut.p("  TOKEN %s" % o)
	assert_eq(over, [],
		"%d authored token(s) exceed their own toast box: %s" % [over.size(), "; ".join(over)])
	gut.p("  %d (token x preset) pairs within their boxes; %d call site(s) pass text or width symbolically" % [pairs, symbolic])

