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

## caller -> [script path, authored width]
const CALLERS := {
	"AnnexLiberation": ["res://src/exploration/AnnexLiberation.gd", 300.0],
	"BulletinBoard": ["res://src/exploration/BulletinBoard.gd", 300.0],
	"CivicBackDoor": ["res://src/exploration/CivicBackDoor.gd", 300.0],
	"CivicFrontDesk": ["res://src/exploration/CivicFrontDesk.gd", 300.0],
	"FireplaceSecret": ["res://src/exploration/FireplaceSecret.gd", 380.0],
	"LockedDoorFlavor": ["res://src/exploration/LockedDoorFlavor.gd", 300.0],
	"MissingPackage": ["res://src/exploration/MissingPackage.gd", 260.0],
	"QuestChicken": ["res://src/exploration/QuestChicken.gd", 240.0],
	"SwordInscription": ["res://src/exploration/SwordInscription.gd", 260.0],
	"TallyWall": ["res://src/exploration/TallyWall.gd", 240.0],
	"WildflowerPatch": ["res://src/exploration/WildflowerPatch.gd", 260.0],
	## cowir-story's, converted to a caller 2026-10-14 (cowir-main's ruling). It is the one caller
	## whose fade span differs from its rise span, so it also covers `show`'s `fade_dur`.
	"QuestExaminePoint": ["res://src/exploration/QuestExaminePoint.gd", 300.0],
}

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
	var rx := RegEx.create_from_string('_toast\\(\\s*"((?:[^"\\\\]|\\\\.)*)"')
	var worst := ""
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


## ⛔ THE ARM THAT MATTERS: every caller's real toast, at every preset the player can pick, with
## its own longest authored string AND a long synthetic one, fits the box the prop gave it.
func test_every_toast_fits_its_box_at_every_preset() -> void:
	var bad: Array = []
	var bottoms: Dictionary = {}
	var checked := 0
	var authored := 0
	for name in CALLERS:
		var path: String = str(CALLERS[name][0])
		var width: float = float(CALLERS[name][1])
		var own := _worst_authored(path)
		if own != "":
			authored += 1
		for s in PRESETS:
			_scale(s)
			for text in ([own, LONG] if own != "" else [LONG]):
				var lbl: Label = await _toast_label(path, text)
				if lbl == null:
					bad.append("%s @%.2fx built no Label" % [name, s])
					continue
				checked += 1
				## The box must still be the authored width: a clamp up is the centring drift.
				if lbl.size.x > width + 0.5:
					bad.append("%s @%.2fx width clamped to %.0f past its authored %.0f — the box is centred, the text is not (drift %+.0f px)" % [
						name, s, lbl.size.x, width, (lbl.size.x - width) * 0.5])
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
		if absf(hi - lo) > 0.5:
			bad.append("%s bottom edge MOVES across presets: %.0f..%.0f — a taller toast grew DOWN over the prop instead of up (%s)" % [
				name, lo, hi, str(per)])
	assert_eq(authored, 10,
		"CONTROL: 10 of the 12 callers must carry authored toast literals (found %d); FireplaceSecret and LockedDoorFlavor build theirs at runtime" % authored)
	assert_gt(checked, 90,
		"CONTROL: only %d toasts were built across %d callers x %d presets; the sweep did not run" % [checked, CALLERS.size(), PRESETS.size()])
	bad.sort()
	for b in bad:
		gut.p("  OVERFLOW %s" % b)
	assert_eq(bad, [],
		"%d toast(s) do not fit the box their prop gave them: %s" % [bad.size(), "; ".join(bad)])
	gut.p("  %d toasts built across %d callers x %d presets, every bottom edge held across all five" % [checked, CALLERS.size(), PRESETS.size()])


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

