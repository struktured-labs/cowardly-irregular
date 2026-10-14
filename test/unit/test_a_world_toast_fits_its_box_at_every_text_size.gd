extends GutTest

## 🐛 A TOAST RISES OFF THE TOP OF THE SCREEN, AND ONE PLACEMENT DOES IT AT 100% TEXT SIZE.
##
## `WorldToast` holds the authored BOTTOM edge and lets a taller block rise — correct, and
## unbounded. These are WORLD-SPACE labels: the village camera runs at zoom 2.0 and interiors at
## 2.5, so each toast pixel is two or two and a half SCREEN pixels, and `limit_top = 0` means a prop
## near a map's top edge sits high on screen rather than at the centre. Measured over all eleven
## placed examine points:
##
##     FrostholdVillage  prop at world y=80 -> camera clamped -> prop at screen y=160
##                       risen top at y=-20 AT 100% TEXT SIZE, the default
##     10 of the other 11 leave the top at 200%, by 34 to 220 px — whole lines gone
##
## `Signpost._keep_flat_label_on_screen` already carries this cure for its own label. The toasts
## never got it; `WorldToast.on_screen_origin` is that rule, and the arm below drives the real
## geometry (viewport height from ProjectSettings, zoom from BaseVillage, the highest placement
## from the map scripts) rather than restating any of those numbers.
##
## 🔑 WHAT MADE IT VISIBLE WAS THE CORPUS, NOT A NEW IDEA. The previous version of this file drove
## ONE string per caller, chosen by `.length()`. That is two separate errors, each found by a
## different lane: @cowir-adhoc measured that the longest string by characters is not the widest in
## pixels (QuestChicken's two disagree), and @cowir-controller named the deeper one — a corpus of
## one is a corpus chosen by whatever metric you reached for. **Driving EVERY authored string
## dissolves the selection question instead of answering it**: 43 strings here against 11 before,
## and the tallest block went from 124 px to 341 px. Nothing about the selector was fixed; the
## selector was deleted.
##
## ⚠️ AND A THIRD OF THE CORPUS IS UNREACHABLE FROM THE PROP'S OWN SOURCE. Three callers build
## their text at runtime (`LockedDoorFlavor.flavor_line`, `QuestExaminePoint.examine_text` /
## `idle_text`) and two carry it in consts the call site names rather than spells
## (`FireplaceSecret.FOUND_LINE` / `ALREADY_LINE`). So the harvest is a FIXPOINT over names that
## FLOW to the toast call, closed over local assignments — which reaches `QuestChicken.catch_line`
## through its intermediate local, two hops from `_toast(`, where a one-level predicate stops.
## Fields that survive that fixpoint are then filled from every map script in the four directories.
##
## ⛔ A FIRST VERSION HARVESTED EVERY `@export ... String` INSTEAD, AND IT REPORTED FOUR DEFECTS
## THAT ARE NOT TEXT AT ALL — `chicken_id`, `quest_world4_words_per_conversation_petition_submitted`
## and two more flag ids, flagged as tokens wider than their box. Ids are never drawn. The corpus
## was keyed on the wrong noun and every one of its findings was about a string no player sees.

## ⛔ DERIVED FROM THE LADDER THE PLAYER DRIVES, NOT COPIED. This was
## `const PRESETS := [0.8, 1.0, 1.25, 1.5, 2.0]` — a duplicate of `SettingsMenu.TEXT_SIZE_PRESETS`
## that goes stale the day a preset is added, and then every arm written to catch "it broke at
## 125%" never visits the new rung. @cowir-controller found the same copy in two of their guards.
##
## ⚠️ NO FALLBACK DEFAULT, DELIBERATELY. A `.get(..., [0.8, …])` would leave the arms passing
## against a ladder nobody can select, which is strictly worse than the copy it replaces — the copy
## at least fails visibly when someone compares the two lists.
##
## ⛔ BUT "A RENAME MUST RED" IS THE WRONG WORD FOR WHAT HAPPENS, AND THE RIGHT ONE MATTERS AT THE
## DIAGNOSIS MOMENT (@cowir-music). `SettingsMenu.TEXT_SIZE_PRESETS` is a `class_name` const, so it
## resolves at PARSE time: renaming or removing it does not fail an assert, it stops this file
## RUNNING, which `run_tests.sh` reports as `EC=3 NOT ALL TEST FILES RAN` — and that tool lists the
## unimported-worktree cause FIRST. So the honest statement is "a rename is impossible to miss, and
## it looks exactly like a skipped `--import`". **On a mass EC=3 across Text Size files, check this
## const before re-importing**; ~17 test files share this single parse-time dependency.
## ⛔ THE FLOOR LIVES HERE, NOT ONLY IN ITS OWN ARM, and the difference is DURABILITY rather than
## detection. A standalone floor arm reds the FILE on an empty ladder — which is what a gate reads —
## but every `for sc in _presets()` loop below still passes vacuously and is individually
## unfalsifiable. @cowir-autogrind named that; @cowir-story's repair is cheaper than a control per
## loop: assert in the helper, and each sweeping arm reds BY ITS OWN NAME. It also cannot be
## separated from the loops by a later edit the way a separate arm can (@cowir-controller).
##
## ⚠️ NOT static any more. Checked before changing it: 0 of this file's static functions call it, so
## nothing breaks at parse time — a single static caller would have been EC=3, "nothing ran", which
## is louder than a vacuous pass but costs the whole file.
func _presets() -> Array:
	var out: Array = SettingsMenu.TEXT_SIZE_PRESETS
	assert_gt(out.size(), 2,
		"the Text Size ladder derived only %d rung(s) — every preset loop in this file iterates over it, so a short ladder makes this arm vacuous rather than failing" % out.size())
	return out
const LONG := "A notice long enough to need more than one line at any text size the settings offer."
const LIT := '"((?:[^"\\\\]|\\\\.)*)"'

## ⛔ THE BOTTOM-EDGE RULE IS ONE-SIDED, BECAUSE THE DEFECT IS. A bottom edge that moves UP as the
## font grows is the toast sitting slightly higher than authored — never over the prop. The defect
## was the edge moving DOWN, over the prop being read and the player standing at it. Asserting
## INVARIANCE instead of MONOTONICITY reds on a harmless rise, and it did: five callers author
## `min_h = 18.0` for a box that cannot hold one line of text at any text size, because a Label's
## own minimum for one line is ~23 px. Their edge sits 5 px low at 80%-100% and reaches the authored
## line by 150%, measured: -29 -29 -31 -34 -34. That is a cosmetic offset in the authored floor, in
## the safe direction, and it is NOT what this file defends — a two-sided assert cannot tell the two
## apart and condemns both. @cowir-battle's axis rule, one layer over: the direction is the claim.
const BOTTOM_TOLERANCE_PX := 2.0

## ⛔ THE CALLER LIST IS DERIVED, NOT WRITTEN. It was twelve hand-typed literals with nothing
## keeping them equal to the call sites. Keying on nodes would now see only `WorldToast.gd` — the
## refactor removed `Label.new()` from every caller — and keying on the method name `_toast` misses
## `HiddenPassage`, whose toast lives in `_shimmer_away`. The helper's own name is the one thing
## every caller must spell.
const CALL := "WorldToast.show("
const DIRS := ["res://src/exploration/", "res://src/maps/villages/", "res://src/maps/interiors/", "res://src/maps/dungeons/"]


static func _all_gd() -> Array:
	var out: Array = []
	for d in DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for fn in da.get_files():
			if str(fn).ends_with(".gd"):
				out.append(d + str(fn))
	out.sort()
	return out


static func _caller_paths() -> Array:
	var out: Array = []
	for p in _all_gd():
		if FileAccess.get_file_as_string(p).contains(CALL):
			out.append(p)
	return out


## The balanced text inside `key(` … `)`, string-literal aware, plus the index just past it.
static func _grab(src: String, key: String, from: int) -> Array:
	var at := src.find(key, from)
	if at < 0:
		return ["", -1]
	var i := at + key.length()
	var depth := 1
	var in_str := false
	var buf := ""
	while i < src.length() and depth > 0:
		var ch := src[i]
		if in_str:
			if ch == "\\":
				buf += src.substr(i, 2)
				i += 2
				continue
			if ch == '"':
				in_str = false
		elif ch == '"':
			in_str = true
		elif ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
			if depth == 0:
				break
		buf += ch
		i += 1
	return [buf, i]


static func _args(buf: String) -> Array:
	var out: Array = []
	var cur := ""
	var d := 0
	var in_str := false
	var j := 0
	while j < buf.length():
		var c := buf[j]
		if in_str:
			if c == "\\":
				cur += buf.substr(j, 2)
				j += 2
				continue
			if c == '"':
				in_str = false
			cur += c
		elif c == '"':
			in_str = true
			cur += c
		elif c == "(" or c == "[":
			d += 1
			cur += c
		elif c == ")" or c == "]":
			d -= 1
			cur += c
		elif c == "," and d == 0:
			out.append(cur.strip_edges())
			cur = ""
		else:
			cur += c
		j += 1
	if cur.strip_edges() != "":
		out.append(cur.strip_edges())
	return out


## A literal float, or a `const NAME := <number>` in the same file. QuestExaminePoint passes all
## four of its box numbers symbolically, so a parser that only reads literals skips the caller with
## the tallest toast in the game.
static func _num(tok: String, src: String) -> float:
	if tok.is_valid_float():
		return float(tok)
	for pat in ["const\\s+%s\\s*:=\\s*([0-9.\\-]+)", "const\\s+%s\\s*:\\s*\\w+\\s*=\\s*([0-9.\\-]+)"]:
		var m := RegEx.create_from_string(pat % tok).search(src)
		if m != null:
			return float(m.get_string(1))
	return NAN


## The box this caller hands the helper: width, authored top, floor, rise, base font.
static func _box(src: String) -> Dictionary:
	var a := _args(str(_grab(src, CALL, 0)[0]))
	if a.size() < 6:
		return {}
	return {
		"w": _num(a[2], src), "top": _num(a[3], src), "min_h": _num(a[5], src),
		"rise": _num(a[6], src) if a.size() > 6 else 20.0,
		"base": int(_num(a[12], src)) if a.size() > 12 else WorldToast.BASE_FONT,
	}


static func _idents(expr: String) -> Array:
	var out: Array = []
	## Strip the literals first, or every word of the prose inside them reads as an identifier.
	var bare := RegEx.create_from_string(LIT).sub(expr, " ", true)
	for m in RegEx.create_from_string("[A-Za-z_][A-Za-z_0-9]*").search_all(bare):
		out.append(m.get_string(0))
	return out


## Every expression in a text slot: a `_toast(...)` argument list, or `show`'s SECOND argument.
static func _toast_exprs(src: String) -> Array:
	var out: Array = []
	for key in ["_toast(", CALL]:
		var from := 0
		while true:
			var r := _grab(src, key, from)
			if int(r[1]) < 0:
				break
			from = int(r[1])
			if key == CALL:
				var p := _args(str(r[0]))
				if p.size() > 1:
					out.append(str(p[1]))
			else:
				out.append(str(r[0]))
	return out


## Names that FLOW to the toast — seeded from its own arguments, then closed over assignments.
## The fixpoint is what reaches `QuestChicken.catch_line`: it is read into a local, and the local
## is what `_toast` is handed. A one-level predicate scores that caller as having no authored text.
static func _flow_names(src: String) -> Dictionary:
	var set: Dictionary = {}
	for e in _toast_exprs(src):
		for id in _idents(e):
			set[id] = true
	var grew := true
	var guard := 0
	while grew and guard < 12:
		grew = false
		guard += 1
		for nm in set.keys():
			for pat in ["\\bvar\\s+%s\\s*:?=\\s*([^\\n]*)", "^[ \\t]*%s\\s*=\\s*([^\\n]*)$"]:
				for m in RegEx.create_from_string(pat % nm).search_all(src):
					for id in _idents(m.get_string(1)):
						if not set.has(id):
							set[id] = true
							grew = true
	return set


## Every authored string that can reach this caller's toast, and the exported fields it came by.
static func _corpus(src: String, all_src: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for e in _toast_exprs(src):
		for m in RegEx.create_from_string(LIT).search_all(e):
			var s: String = m.get_string(1)
			if s.strip_edges() != "" and not seen.has(s):
				seen[s] = true
				out.append(s)
	var flow := _flow_names(src)
	for m in RegEx.create_from_string('const\\s+([A-Z_0-9]+)\\s*:?=\\s*' + LIT).search_all(src):
		if flow.has(m.get_string(1)):
			var s2: String = m.get_string(2)
			if s2 != "" and not seen.has(s2):
				seen[s2] = true
				out.append(s2)
	var fields: Array = []
	for m in RegEx.create_from_string('@export var ([a-z_]+): String').search_all(src):
		if flow.has(m.get_string(1)):
			fields.append(m.get_string(1))
	for other in all_src:
		for f in fields:
			for m in RegEx.create_from_string('\\.%s\\s*=\\s*' % f + LIT).search_all(other):
				var s3: String = m.get_string(1)
				if s3 != "" and not seen.has(s3):
					seen[s3] = true
					out.append(s3)
	return [out, fields]


var _vp: SubViewport = null
var _saved_scale: float = 1.0


## `before_each`/`after_each` rather than the file pair: the restore then runs between arms, so an
## error that aborts one arm mid-sweep cannot carry a scaled GameState into the next.
func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale) if "text_size_scale" in GameState else 1.0


func after_each() -> void:
	if "text_size_scale" in GameState:
		GameState.text_size_scale = _saved_scale


func _scale(s: float) -> void:
	GameState.text_size_scale = s


## ⛔ A REAL VIEWPORT, AND THE HOST LOW IN IT. `show` now clamps the label into view, so the host's
## screen position is an INPUT to every placement assert below. A 64x64 viewport — what this file
## used before — puts every host 32 px from the top and fires the clamp on every toast, turning the
## invariance arms into arms about the clamp.
##
## ⚠️ AND THE CENTRE IS NOT LOW ENOUGH, which is a measurement rather than a guess: at 200% the
## tallest authored examine string needs 419 world px above its prop (341 of block, 58 of baseline,
## 20 of rise) against 360 px of headroom at the centre, so the clamp fires for exactly that one
## pair and the arm reports a 27 px edge move that is the clamp doing its job. The host therefore
## sits near the BOTTOM of the viewport, where every toast in the corpus has room — and the arm
## asserts the clamp stayed inert rather than assuming it, by comparing each built label against the
## seam's unclamped answer.
func _host() -> SubViewport:
	if _vp == null or not is_instance_valid(_vp):
		_vp = SubViewport.new()
		_vp.size = Vector2i(_view_size())
		_vp.world_2d = World2D.new()
		add_child_autofree(_vp)
	return _vp


static func _view_size() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))


## Drive the REAL prop's own `_toast` and hand back the Label THAT CALL ADDED.
##
## ⛔ NOT "the first Label child". Nine of these callers build an `_indicator` Label in `_ready` —
## the world-space press prompt — so taking the first Label measured the INDICATOR and never the
## toast. The whole sweep once went green about the wrong node.
## ⛔ POSITION BEFORE ANY AWAIT, SIZE AFTER ONE. The two quantities need opposite treatment and
## reading both at one moment is wrong for one of them. `show` starts a tween on `position:y`, so a
## frame of settling measures the ANIMATION: headless frame deltas are large and a 9 px/s rise moved
## the label ~1 px, which my clamp detector then reported as the clamp firing on two callers at
## 0.80x. `size`, by contrast, clamps up to the content during layout and is only right AFTER a
## frame — and the tween never touches it. So: read `position` synchronously, then await for `size`.
## The sibling arm below already carries half of this note; the sweep did not have it.
func _toast_box(path: String, text: String, at: Vector2) -> Dictionary:
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return {}
	var prop = scr.new()
	## ⚠️ ASK BEFORE CALLING. `HiddenPassage`'s toast is in `_shimmer_away()` and takes no argument,
	## and an unguarded call is a GDScript error that ABORTS this function — the empty dictionary it
	## then returns is indistinguishable from "built no Label".
	if not prop.has_method("_toast"):
		prop.free()
		return {}
	prop.position = at
	_host().add_child(prop)
	await get_tree().process_frame
	var before: Dictionary = {}
	for c in prop.get_children():
		before[c.get_instance_id()] = true
	prop._toast(text)
	var lbl: Label = null
	for c in prop.get_children():
		if c is Label and not before.has(c.get_instance_id()):
			lbl = c
			break
	if lbl == null:
		return {}
	var pos: Vector2 = lbl.position
	await get_tree().process_frame
	return {"pos": pos, "size": lbl.size}


## ⛔ THE DERIVATION'S OWN FLOOR, AS ITS OWN ARM. An empty or shrunken ladder makes every
## `for sc in _presets()` loop iterate zero times and every arm below pass green about nothing —
## the hollow shape @cowir-adhoc and @cowir-sfx each found in a guard of their own today, here
## reachable through the SOURCE rather than through a skip.
func test_the_preset_ladder_is_the_players_own() -> void:
	var p: Array = _presets()
	assert_gt(p.size(), 2,
		"CONTROL: the Text Size ladder derived only %d rung(s). Every preset loop in this file iterates over it, so a short ladder makes the whole file vacuous" % p.size())
	assert_true(p.has(1.0),
		"CONTROL: the ladder must contain 1.0 — the shipped default is the rung most of this file's claims are about")
	var sorted_copy: Array = p.duplicate()
	sorted_copy.sort()
	assert_eq(p, sorted_copy,
		"the ladder must be ASCENDING: the bottom-edge rule is monotonic in preset order, so an unsorted list silently changes what that arm asserts")
	gut.p("  ladder derived from SettingsMenu.TEXT_SIZE_PRESETS: %s" % str(p))


func test_the_corpus_reaches_the_runtime_text_providers() -> void:
	var all_src: Array = []
	for p in _all_gd():
		all_src.append(FileAccess.get_file_as_string(p))
	var total := 0
	var by_field := 0
	var fielded: Array = []
	var boxless: Array = []
	for path in _caller_paths():
		var src := FileAccess.get_file_as_string(path)
		var name: String = path.get_file().get_basename()
		var r := _corpus(src, all_src)
		total += (r[0] as Array).size()
		if not (r[1] as Array).is_empty():
			fielded.append(name)
			by_field += 1
		var b := _box(src)
		if b.is_empty() or is_nan(b["w"]) or is_nan(b["min_h"]) or is_nan(b["top"]):
			boxless.append(name)
	assert_eq(boxless, [],
		"CONTROL: every caller's box must parse from its own call site, including the symbolic ones — %s did not, and an unparsed box silently drops that caller from every arm below" % ", ".join(boxless))
	assert_gt(_caller_paths().size(), 12,
		"CONTROL: only %d callers derived; the helper name no longer finds them" % _caller_paths().size())
	assert_gt(total, 35,
		"CONTROL: only %d authored strings harvested across %d callers. The pre-fix corpus was one per caller (11) and it hid a 341 px block behind a 124 px one; a collapse back toward that number means the flow fixpoint stopped reaching" % [total, _caller_paths().size()])
	fielded.sort()
	assert_true(fielded.size() >= 3,
		"CONTROL: at least three callers must take their text through an exported field filled by a map script (found %s). These are the strings no census of the prop's own source can see, and they include the tallest toast in the game" % str(fielded))
	gut.p("  %d authored strings across %d callers; %d take text through map-script fields: %s" % [
		total, _caller_paths().size(), by_field, ", ".join(fielded)])


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
	## ⛔ AND THE BASE MUST REACH THE RESULT, AT EVERY PRESET. Most callers author 11, `HiddenPassage`
	## 12 and `SavePoint` 14, so a `font_size(base)` that ignored its argument would render one a
	## point small with every other arm green — the mutation that drops the parameter passed 5/5
	## before this existed. Three bases, ordered, is the whole check.
	var flat: Array = []
	for sc in _presets():
		_scale(sc)
		var a: int = WorldToast.font_size(11)
		var b: int = WorldToast.font_size(12)
		var c: int = WorldToast.font_size(14)
		if not (c > b and b > a):
			flat.append("@%.2fx base 11/12/14 gave %d/%d/%d — the base does not reach the result" % [sc, a, b, c])
	_scale(1.0)
	assert_eq(flat, [], "the authored base font must survive scaling: %s" % "; ".join(flat))
	gut.p("  font 80%%/100%%/200%% = %d / %d / %d; bases 11/12/14 ordered at all %d presets" % [
		small, base, big, _presets().size()])


## ⛔ THE MEASUREMENT MUST USE THE LABEL'S OWN BREAK RULE, AND THIS ARM IS WHY IT IS CHECKABLE
## RATHER THAN ASSERTED IN A COMMENT. `get_multiline_string_size` defaults to
## `BREAK_MANDATORY | BREAK_WORD_BOUND`, which is `AUTOWRAP_WORD`'s rule — every toast label is set
## to `AUTOWRAP_WORD_SMART`, whose rule adds `BREAK_ADAPTIVE`. They agree on all 2,665 authored
## (string x box x preset) pairs and diverge precisely where a token is wider than its box: the
## default cannot break inside the word and reports ONE line for a block that draws four.
##
## 📌 So this arm drives the case the corpus does not contain — a single unbreakable token in a
## narrow box — and asserts the helper reports the TALLER answer. Before the flag was passed,
## `height_for` was correct only while the token arm below held, which is a coupling between two
## guards and not a property of the code.
func test_the_measurement_uses_the_labels_own_break_rule() -> void:
	_scale(1.0)
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	probe.free()
	assert_not_null(font, "CONTROL: the theme font must resolve, else every height here is the floor")
	if font == null:
		return
	var word := "Antidisestablishmentarianism"
	var narrow := 104.0
	var fs: int = WorldToast.font_size()
	var one_line: float = font.get_multiline_string_size(
		word, HORIZONTAL_ALIGNMENT_CENTER, narrow, fs).y
	var adaptive: float = font.get_multiline_string_size(
		word, HORIZONTAL_ALIGNMENT_CENTER, narrow, fs, -1, WorldToast.BREAK_FLAGS).y
	assert_gt(font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, narrow,
		"CONTROL: the token must actually exceed the box, else the two rules cannot disagree here")
	assert_gt(adaptive, one_line,
		"CONTROL: the two break rules must differ on an over-wide token (%.0f vs %.0f); if they no longer do, this arm proves nothing and the engine's default changed" % [adaptive, one_line])
	assert_almost_eq(WorldToast.height_for(word, narrow, 1.0), adaptive, 0.5,
		"height_for must measure with the label's own WORD_SMART rule: got %.0f, the node's rule says %.0f, the default rule says %.0f" % [
			WorldToast.height_for(word, narrow, 1.0), adaptive, one_line])
	gut.p("  over-wide token: WORD_SMART %.0f px vs the default rule's %.0f, height_for agrees with WORD_SMART" % [adaptive, one_line])


## ⛔ THE ARM THAT MATTERS: every caller's real toast, at every preset the player can pick, with
## EVERY string authored for it, fits the box the prop gave it.
func test_every_toast_fits_its_box_at_every_preset() -> void:
	var all_src: Array = []
	for p in _all_gd():
		all_src.append(FileAccess.get_file_as_string(p))
	var low := Vector2(float(_view_size().x) * 0.5, float(_view_size().y) - 32.0)
	var bad: Array = []
	var bottoms: Dictionary = {}
	var widths: Dictionary = {}
	var checked := 0
	var clamped: Array = []
	var no_toast: Array = []
	for path in _caller_paths():
		var name: String = path.get_file().get_basename()
		var src := FileAccess.get_file_as_string(path)
		var b := _box(src)
		var own: Array = (_corpus(src, all_src)[0] as Array).duplicate()
		own.append(LONG)
		for s in _presets():
			_scale(s)
			for text in own:
				var r: Dictionary = await _toast_box(path, text, low)
				if r.is_empty():
					if not (name in no_toast):
						no_toast.append(name)
					continue
				var pos: Vector2 = r["pos"]
				var sz: Vector2 = r["size"]
				checked += 1
				## ⛔ WIDTH AS AN INVARIANT, NOT AGAINST A TABLE. A wrapping label stays at its box
				## width at every preset; an unwrapped one takes its text's width and GROWS with the
				## font. "Constant across presets" catches the clamp with no width written down, and
				## it is what the no-autowrap mutation reds.
				## The seam's unclamped answer for this exact toast; any difference IS the clamp.
				var want: float = WorldToast.origin_for(text, b["w"], b["top"], b["min_h"], b["base"]).y
				if absf(pos.y - want) > 0.5:
					clamped.append("%s @%.2fx placed %.1f, seam says %.1f" % [name, s, pos.y, want])
				var key: String = "%s|%d" % [name, text.hash()]
				if not widths.has(key):
					widths[key] = {}
				(widths[key] as Dictionary)[s] = sz.x
				## ⛔ THE BOTTOM EDGE, NOT "DOES THE TEXT FIT THE BOX". That comparison is hollow:
				## `Control.size` clamps UP to the content, so `lbl.size.y` becomes the text height
				## whatever the caller assigned, and text-vs-box is green in both worlds. What the
				## defect did was draw DOWNWARD over the prop, so the invariant is that the authored
				## bottom edge does not move — asserted as INVARIANCE ACROSS THE PRESETS, needing no copy
				## of any caller's baseline here.
				if not bottoms.has(key):
					bottoms[key] = {}
				(bottoms[key] as Dictionary)[s] = pos.y + sz.y
	_scale(1.0)
	for key in bottoms:
		var per: Dictionary = bottoms[key]
		## ⛔ MONOTONIC IN PRESET ORDER, NOT A MIN/MAX SPREAD. `_presets()` is ascending, so the claim is
		## that a bigger font never pushes the edge DOWN. A spread cannot express that.
		var worst_drop := 0.0
		var first := true
		var prev := 0.0
		for sc in _presets():
			if not per.has(sc):
				continue
			var cur: float = float(per[sc])
			if not first:
				worst_drop = maxf(worst_drop, cur - prev)
			prev = cur
			first = false
		if worst_drop > BOTTOM_TOLERANCE_PX:
			bad.append("%s bottom edge moves DOWN %.1f px as the font grows: %s — a taller toast grew over the prop instead of away from it" % [
				str(key).split("|")[0], worst_drop, str(per)])
		var vals: Array = per.values()
		var lo: float = vals.min()
		var hi: float = vals.max()
		## ⚠️ 2 px, NOT 0 px, AND THE NUMBER IS MEASURED. `height_for` measures off the FONT while
		## the Label clamps `size.y` to its own `get_combined_minimum_size()`, and the two disagree
		## by up to a pixel of rounding — `LockedDoorFlavor` reported -29..-28 across the presets on
		## a correct tree. It keeps its teeth because the defect it guards moves the edge 14 px at
		## the floor and 124 px at 2.0x — two orders off this.
		## The rise is bounded too: an edge that climbs away without limit would be the mirror
		## defect, a toast detaching from the prop it names. The authored floor accounts for ~5 px of
		## it; anything beyond a line of text at 200% is not a floor artefact.
		if absf(hi - lo) > float(WorldToast.font_size(14)) * 2.0:
			bad.append("%s bottom edge wanders %.1f px across presets: %s — more than a line of text, so the toast is detaching from its prop" % [
				str(key).split("|")[0], hi - lo, str(per)])
	for key in widths:
		var wper: Dictionary = widths[key]
		var wv: Array = wper.values()
		if absf(float(wv.max()) - float(wv.min())) > 2.0:
			bad.append("%s width GROWS with the font: %.0f..%.0f — the label took its text's width instead of its box, so the box is centred and the text is not" % [
				str(key).split("|")[0], float(wv.min()), float(wv.max())])
	no_toast.sort()
	for n in no_toast:
		gut.p("  no _toast(text) to drive, covered by the token arm: %s" % n)
	## ⛔ THE HOST SITS AT THE VIEWPORT CENTRE SO THE ON-SCREEN CLAMP IS INERT HERE, AND THAT IS A
	## PRECONDITION RATHER THAN A CONVENIENCE. If the clamp fires it LOWERS the label on purpose, so
	## the invariance claims above would be measuring the clamp instead of the growth rule. Checked,
	## not assumed: at the centre every bottom edge must be above the host, which is only true while
	## nothing was pushed down past it.
	clamped.sort()
	assert_eq(clamped, [],
		"CONTROL: the on-screen clamp fired for %d toast(s) here, so the asserts above are about the clamp and not about the growth rule — move the host lower or the corpus has outgrown the viewport: %s" % [
			clamped.size(), "; ".join(clamped)])
	assert_gt(checked, 180,
		"CONTROL: only %d toasts built across %d callers x %d presets; the sweep did not run the full corpus (the pre-fix sweep managed ~100 and hid the tallest block)" % [
			checked, _caller_paths().size(), _presets().size()])
	bad.sort()
	for b in bad:
		gut.p("  OVERFLOW %s" % b)
	assert_eq(bad, [],
		"%d toast(s) do not fit the box their prop gave them: %s" % [bad.size(), "; ".join(bad)])
	var drop := 0.0
	var rise := 0.0
	for key in bottoms:
		var per2: Dictionary = bottoms[key]
		var pv := 0.0
		var f2 := true
		for sc in _presets():
			if not per2.has(sc):
				continue
			if not f2:
				drop = maxf(drop, float(per2[sc]) - pv)
			pv = float(per2[sc])
			f2 = false
		var v: Array = per2.values()
		rise = maxf(rise, float(v.max()) - float(v.min()))
	gut.p("  %d toasts across %d callers x %d presets; worst DOWNWARD move %.1f px (tolerance %.1f), worst total wander %.1f px" % [
		checked, _caller_paths().size(), _presets().size(), drop, BOTTOM_TOLERANCE_PX, rise])


## ⛔ THE DEFECT ARM. A toast's risen top must stay on screen, at every preset, for the HIGHEST
## placement in the game — derived, not restated: the viewport from ProjectSettings, the zoom from
## `BaseVillage`, and the smallest placement `y` from the map scripts that place examine points.
##
## 🔑 THE CAMERA CLAMP IS THE WHOLE MECHANISM AND IT IS WHY MID-MAP MEASUREMENTS MISS THIS.
## `limit_top = 0`, so the camera centre cannot rise above half a viewport's worth of world — a prop
## above that line is rendered ABOVE screen centre, and the toast rises from there. Measure any prop
## in the middle of a map and it is fine at 100% and marginal at 200%; measure Frosthold's and it
## leaves the screen at the default setting.
func test_a_toast_cannot_rise_off_the_top_of_the_screen() -> void:
	var zoom := _village_zoom()
	assert_gt(zoom, 1.0,
		"CONTROL: the village camera zoom must parse from BaseVillage (got %.2f); at zoom 1.0 this arm cannot reproduce the defect, because it is the zoom that turns a 122 px rise into 244 screen px" % zoom)
	var highest := _highest_placement_y()
	assert_gt(highest, 0.0, "CONTROL: a placed examine point's world y must parse from the map scripts")
	var view_h := float(_view_size().y)
	## The camera centre, clamped by limit_top = 0; then where the prop lands on screen.
	var cam: float = maxf(highest, view_h * 0.5 / zoom)
	var prop_screen: float = view_h * 0.5 + (highest - cam) * zoom
	assert_lt(prop_screen, view_h * 0.5 - 1.0,
		"CONTROL: the highest placement must actually sit above screen centre (%.0f of %.0f); if it does not, the clamp is not under test" % [prop_screen, view_h])
	var src := FileAccess.get_file_as_string("res://src/exploration/QuestExaminePoint.gd")
	var b := _box(src)
	var all_src: Array = []
	for p in _all_gd():
		all_src.append(FileAccess.get_file_as_string(p))
	var strs: Array = _corpus(src, all_src)[0]
	assert_gt(strs.size(), 3, "CONTROL: the tallest caller's corpus must be non-trivial, found %d" % strs.size())
	var off: Array = []
	var would_have: Array = []
	for sc in _presets():
		_scale(sc)
		for text in strs:
			var h: float = WorldToast.height_for(text, b["w"], b["min_h"], b["base"])
			var raw: Vector2 = WorldToast.origin_for_height(h, b["w"], b["top"], b["min_h"])
			## Where the risen top lands on screen, and the rule's answer for it.
			var screen_top: float = prop_screen + (raw.y - float(b["rise"])) * zoom
			var fixed: Vector2 = WorldToast.on_screen_origin(raw, screen_top, zoom)
			var after: float = prop_screen + (fixed.y - float(b["rise"])) * zoom
			if screen_top < 0.0:
				would_have.append("@%.2fx %.0f px" % [sc, -screen_top])
			if after < 0.0:
				off.append("@%.2fx top at %.0f after clamping (h %.0f px)" % [sc, after, h])
	_scale(1.0)
	assert_gt(would_have.size(), 0,
		"CONTROL: no string at any preset would have left the screen without the clamp, so this arm is not exercising it — the geometry (zoom %.1f, prop screen y %.0f) no longer reproduces the defect" % [zoom, prop_screen])
	off.sort()
	assert_eq(off, [],
		"%d toast(s) still rise off the top of the screen at the game's highest placement (world y %.0f, screen y %.0f, zoom %.1f): %s" % [
			off.size(), highest, prop_screen, zoom, "; ".join(off)])
	gut.p("  highest placement: world y %.0f -> screen y %.0f at zoom %.1f; %d (string x preset) would have left the top, none does" % [
		highest, prop_screen, zoom, would_have.size()])


## ⛔ AND THROUGH THE BUILT NODE, not only the arithmetic. The seam above is pure; this drives the
## real `show` with the host placed where the camera would put Frosthold's prop and reads the label
## back. A rule that is right in arithmetic and unreached by `show` is the drift this file already
## caught once between `show` and `origin_for`.
func test_show_keeps_a_high_toast_on_screen() -> void:
	_scale(2.0)
	var view_h := float(_view_size().y)
	var host := Node2D.new()
	host.position = Vector2(float(_view_size().x) * 0.5, 40.0)
	_host().add_child(host)
	await get_tree().process_frame
	var src := FileAccess.get_file_as_string("res://src/exploration/QuestExaminePoint.gd")
	var b := _box(src)
	var text := LONG + " " + LONG
	var raw: Vector2 = WorldToast.origin_for(text, b["w"], b["top"], b["min_h"], b["base"])
	var lbl: Label = WorldToast.show(host, text, b["w"], b["top"], Color.WHITE,
		b["min_h"], b["rise"], 2.0, 1.0)
	assert_not_null(lbl, "CONTROL: show must build a Label")
	if lbl == null:
		return
	assert_lt(host.position.y + raw.y - float(b["rise"]), 0.0,
		"CONTROL: unclamped, this toast's risen top must land above the viewport (%.0f); otherwise the arm proves nothing" % (host.position.y + raw.y - float(b["rise"])))
	assert_gt(lbl.position.y, raw.y,
		"show must apply the on-screen rule: it placed the label at %.0f, the unclamped origin is %.0f" % [lbl.position.y, raw.y])
	assert_gte(host.position.y + lbl.position.y - float(b["rise"]), 0.0,
		"show placed a toast whose risen top is off the top of the screen: %.0f" % (host.position.y + lbl.position.y - float(b["rise"])))
	assert_lt(host.position.y + lbl.position.y + lbl.size.y, view_h + lbl.size.y,
		"CONTROL: the clamp must not push the whole block below the viewport")
	gut.p("  host at y=40: unclamped top %.0f -> clamped %.0f, on screen" % [
		host.position.y + raw.y - float(b["rise"]), host.position.y + lbl.position.y - float(b["rise"])])


## ⛔ AND IT MUST BE INERT WHERE IT IS NOT NEEDED. A clamp that always fires would hold every toast
## at the top of the screen and silently delete the growth rule the rest of this file defends.
func test_the_clamp_does_nothing_to_a_toast_with_room() -> void:
	var at := Vector2(-150.0, -120.0)
	assert_eq(WorldToast.on_screen_origin(at, 300.0, 2.0), at,
		"a toast with 300 px of headroom must not be moved")
	assert_eq(WorldToast.on_screen_origin(at, WorldToast.VIEW_MARGIN_PX, 2.0), at,
		"a toast exactly at the margin must not be moved")
	var pushed: Vector2 = WorldToast.on_screen_origin(at, -100.0, 2.0)
	assert_eq(pushed.x, at.x, "the clamp is vertical only; x must not move")
	assert_almost_eq(pushed.y, at.y + (WorldToast.VIEW_MARGIN_PX + 100.0) / 2.0, 0.01,
		"the push must be divided by the canvas scale: at zoom 2.0, 104 screen px is 52 world px")
	## ⛔ DIVIDED BY THE SCALE, WHICH IS THE HALF A MUTATION GETS WRONG SILENTLY. Pushing by the
	## SCREEN deficit instead of the world one over-corrects by exactly the zoom factor — 2x in a
	## village, 2.5x in an interior — and the toast lands below the prop it names. Both arms above
	## pass under that mutation; only this ratio reds.
	assert_almost_eq(WorldToast.on_screen_origin(at, -100.0, 2.5).y,
		at.y + (WorldToast.VIEW_MARGIN_PX + 100.0) / 2.5, 0.01,
		"the same deficit at interior zoom must move the label LESS in world space, not the same")
	assert_eq(WorldToast.on_screen_origin(at, -100.0, 0.0), at,
		"a zero canvas scale must not divide; the label stays where it was")
	gut.p("  clamp inert with headroom, at the margin, and at zero scale; push scales with zoom")


static func _village_zoom() -> float:
	var m := RegEx.create_from_string("camera\\.zoom\\s*=\\s*Vector2\\(([0-9.]+)").search(
		FileAccess.get_file_as_string("res://src/maps/villages/BaseVillage.gd"))
	return float(m.get_string(1)) if m != null else 1.0


## The smallest world y any map script places an examine point at — the game's highest toast.
static func _highest_placement_y() -> float:
	var best := INF
	for p in _all_gd():
		var src := FileAccess.get_file_as_string(p)
		for key in ["_add_quest_examine_point(", "_add_quest_route_point("]:
			if not src.contains(key):
				continue
			var from := 0
			while true:
				var r := _grab(src, key, from)
				if int(r[1]) < 0:
					break
				from = int(r[1])
				var a := _args(str(r[0]))
				if a.is_empty():
					continue
				var pos: String = str(a[a.size() - 1])
				if not pos.begins_with("Vector2("):
					continue
				var xy := _args(pos.substr(8, pos.length() - 9))
				if xy.size() < 2:
					continue
				var t: String = str(xy[1]).replace(" ", "")
				var y := NAN
				if t.contains("*TILE_SIZE"):
					y = float(t.split("*")[0]) * 32.0
				elif t.is_valid_float():
					y = float(t)
				if not is_nan(y):
					best = minf(best, y)
	return 0.0 if is_inf(best) else best


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
## could fail; that is the CONDITION for a drift, not a drift.
##
## 📌 No await between `show` and the read: the tween it starts animates `position:y`, so a frame of
## settling would measure the animation rather than the placement. And the host sits at the viewport
## centre so the on-screen clamp is inert — asserted, since otherwise `show` and the seam SHOULD
## differ and this arm would be reading the clamp.
func test_show_places_the_label_where_the_seam_says() -> void:
	_scale(1.0)
	var host := Node2D.new()
	host.position = Vector2(_view_size()) * 0.5
	_host().add_child(host)
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
	assert_gt(WorldToast.height_for(LONG, 260.0, 18.0), 18.0,
		"CONTROL: the long string must exceed the 18 px floor, else the arm only tests h == min_h")
	gut.p("  %d (text x floor) pairs, show and the seam agree on every one" % pairs)


## One token's drawn width at a given size, off the theme font a Label would use. Measured from the
## FONT rather than a node: a node's content minimum lands on a deferred pass whose timing depends
## on the order its properties were set, so reading a rect back is unreliable.
func _token_width(word: String, fs: int) -> float:
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	var w := 0.0
	if font != null:
		w = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	probe.free()
	return w


## ⛔ THE TOKEN ARM, NOW OVER EVERY CALLER RATHER THAN ONE. It asserts that NO SINGLE TOKEN IS WIDER
## THAN ITS BOX: autowrap breaks between words and `BREAK_ADAPTIVE` breaks inside one only as a last
## resort, so an over-wide token takes the label's minimum width past its box and the centring drift
## returns. @cowir-autogrind measured exactly that on a grid cell ("Hallucination", 13 chars).
##
## 🔑 IT USED TO REACH ONE CALLER OF THIRTEEN, and the shape of that gap is worth keeping: it
## required a literal TEXT and a literal WIDTH on the same call line, and twelve callers pass `text`
## as an argument. Both halves now come from the same derivation the sweep uses — strings from the
## flow fixpoint, the box from the caller's own `show` call — so the base font comes from the call
## site too, and the old compromise ("measured at the default base, deliberately; a caller with a
## larger base is under-measured by 12/11") is gone rather than documented.
func test_no_authored_token_is_wider_than_its_own_box() -> void:
	var all_src: Array = []
	for p in _all_gd():
		all_src.append(FileAccess.get_file_as_string(p))
	var over: Array = []
	var uncovered: Array = []
	var pairs := 0
	var reached: Array = []
	for path in _caller_paths():
		var src := FileAccess.get_file_as_string(path)
		var name: String = path.get_file().get_basename()
		var b := _box(src)
		var strs: Array = _corpus(src, all_src)[0]
		if b.is_empty() or strs.is_empty():
			if not src.contains("func _toast("):
				uncovered.append(name)
			continue
		reached.append(name)
		for sc in _presets():
			_scale(sc)
			var fs: int = WorldToast.font_size(int(b["base"]))
			for text in strs:
				for word in text.split(" ", false):
					pairs += 1
					var w: float = _token_width(word, fs)
					if w > float(b["w"]) + 0.5:
						over.append("%s @%.2fx token '%s' is %.0f px against a %.0f px box — autowrap cannot break between letters, so the label takes the token's width and the toast drifts %+.0f px" % [
							name, sc, word, w, b["w"], (w - float(b["w"])) * 0.5])
	_scale(1.0)
	uncovered.sort()
	assert_eq(uncovered, [],
		"%d caller(s) are covered by NEITHER arm — no authored string for this one and no `_toast(text)` for the sweep: %s" % [
			uncovered.size(), ", ".join(uncovered)])
	assert_gt(reached.size(), 12,
		"CONTROL: this arm reached only %d of %d callers. It reached ONE before the corpus was derived, and that was invisible because the arm was green — a token check over one caller is green about twelve it never read" % [
			reached.size(), _caller_paths().size()])
	assert_gt(pairs, 1500,
		"CONTROL: only %d (token x preset) pairs measured; the corpus collapsed" % pairs)
	over.sort()
	for o in over:
		gut.p("  TOKEN %s" % o)
	assert_eq(over, [],
		"%d authored token(s) exceed their own toast box: %s" % [over.size(), "; ".join(over)])
	gut.p("  %d (token x preset) pairs within their boxes, across %d of %d callers" % [
		pairs, reached.size(), _caller_paths().size()])
