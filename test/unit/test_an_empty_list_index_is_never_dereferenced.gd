extends GutTest

## ⛔ A CLAMP DOES NOT PROTECT AN EMPTY LIST. Measured, and it is the premise for everything below:
##
##     clampi(5, 0, -1)  == -1      clampi(0, 0, -1) == -1      clamp(5, 0, -1) == -1
##
## When `max < min` the MAX wins, so `clampi(i, 0, list.size() - 1)` on an empty list yields -1 for
## every non-negative input. Eight sites in src/ui/ spell it that way (cowir-battle's sweep).
##
## 🔑 NONE OF THE SEVEN SURFACES IS EXPOSED TODAY, and they are safe for FOUR DIFFERENT REASONS.
## The clamp is not what protects any of them:
##
##   CONSUMER-GUARDED   BossSelectorMenu · RadialPicker · JukeboxMenu
##     the index DOES become -1 — measured, both reach it on an emptied list via paging AND nav —
##     and every dereference tests the low end first. A stored -1 nobody reads is not a bug
##     (cowir-music's rule), and it stops being true the moment a consumer drops its guard.
##
##   GATE-PROTECTED     PartyChatMenu · BestiaryMenu
##     the handler early-returns while `_chats` / `_entries` is empty, so the clamp is unreachable.
##     Measured: both stay at 0 with every list emptied.
##
##   LOCALLY GUARDED    CutsceneGallery
##     the clamp sits INSIDE `if not world_items.is_empty():`. I first filed this as "by
##     construction" from the data shape (6 worlds, all non-empty) — wrong guard, and the
##     distinction matters: "by construction" says nothing could expose it, "locally guarded" says
##     a later edit could. Corrected after cowir-cutscenes read the actual branch.
##
##   BY CONSTRUCTION    TitleScreen
##     menu_items is built with four rows. No arm — a pin on "the builder appends at least one"
##     would red on a legitimate change, and the builder says it more clearly than a pin could.
##
## ⚠️ EVERY CHECK BELOW IS SITE-SCOPED, AND THAT IS NOT STYLE — MY FIRST VERSION WAS VACUOUS TWICE
## OVER, caught by mutation rather than by reading:
##   · RadialPicker carries `maxi(0, _options.size() - 1)` at :45 and an UNGUARDED clamp at :172.
##     A file-scoped `contains(maxi…)` is satisfied by the guarded SIBLING — the within-file
##     asymmetry that makes this shape interesting is exactly what blinded the instrument to it.
##   · `if _chats.is_empty():` occurs TWICE in PartyChatMenu, so deleting one left `contains()` true.
##   · the guard count missed the `>= 0` spelling, which is half of the guards in play.
##   · and `if not world_items.is_empty():` occurs THREE times inside CutsceneGallery's own
##     `_input`, so neither find() NOR function-scoping could tell the guarding occurrence from its
##     siblings — deleting the real one left the arm green twice running.
##
## THAT THIRD ONE IS WHY `_opened_by()` EXISTS. Substring position cannot express "inside this
## branch"; indentation can. The arm walks back from the clamp to the nearest line with LESS
## indentation — its enclosing block's opener — and asks whether that line is the guard. Proved
## both ways: removing the ENCLOSING guard reds, removing a SIBLING copy does not.
##
## 🔑 FOUR VACUOUS VERSIONS OF THIS FILE, ALL THE SAME CLASS: a file-scoped text check standing in
## for a site-scoped property. Every one passed review and was caught only by mutation, and the
## fourth needed a structural test rather than a better pattern. The bug this file is about is
## itself a within-file asymmetry — one guarded line beside an unguarded one — which is precisely
## what a file-wide `contains()` cannot see.

const CONSUMER_GUARDED := [
	{"name": "BossSelectorMenu", "path": "res://src/ui/BossSelectorMenu.gd",
		"list": "_selectable_indices", "idx": "selected_index",
		"unguarded_clamp": "clampi(selected_index + page * MenuPaging.PAGE_ROWS, 0, _selectable_indices.size() - 1)"},
	{"name": "RadialPicker", "path": "res://src/ui/RadialPicker.gd",
		"list": "_options", "idx": "_selected",
		"unguarded_clamp": "clampi(_page * RING_CAPACITY, 0, _options.size() - 1)"},
	{"name": "JukeboxMenu", "path": "res://src/ui/JukeboxMenu.gd",
		"list": "TRACKS", "idx": "selected_index",
		"unguarded_clamp": "clampi(selected_index + page * MenuPaging.PAGE_ROWS, 0, TRACKS.size() - 1)"},
]

## The clamp sits inside an emptiness check rather than carrying a low bound of its own.
const LOCALLY_GUARDED := [
	{"name": "CutsceneGallery", "path": "res://src/ui/CutsceneGallery.gd",
		"list": "world_items", "wrapper": "if not world_items.is_empty():"},
]

const GATE_PROTECTED := [
	{"name": "PartyChatMenu", "path": "res://src/ui/PartyChatMenu.gd", "gate": "_chats"},
	{"name": "BestiaryMenu", "path": "res://src/ui/BestiaryMenu.gd", "gate": "_entries"},
]


func _src(p: String) -> String:
	var s := FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 0, "%s must load" % p)
	return s


## Every function body in the file, so a guard can be attributed to the function that needs it.
func _functions(src: String) -> Array:
	var out: Array = []
	var parts := src.split("\nfunc ")
	for i in range(1, parts.size()):
		out.append("func " + parts[i])
	return out


## The body of `func _input(...)` only — a gate elsewhere in the file protects nothing here.
func _input_body(src: String) -> String:
	var at := src.find("func _input(")
	if at < 0:
		return ""
	var rest := src.substr(at)
	var nxt := rest.find("\nfunc ")
	return rest if nxt < 0 else rest.substr(0, nxt)


## Is `needle` structurally INSIDE the block opened by `opener`? Walks back from the needle to the
## nearest line with LESS indentation — that is its enclosing block's opening line — and asks
## whether that is the guard. Substring position cannot answer this: CutsceneGallery has three
## copies of the opener inside one function, so find() and even rfind() land on a sibling branch.
func _opened_by(src: String, opener: String, needle: String) -> bool:
	var lines := src.split("\n")
	var at := -1
	for i in range(lines.size()):
		if lines[i].contains(needle):
			at = i
			break
	if at < 0:
		return false
	var want := _indent_of(lines[at])
	for i in range(at - 1, -1, -1):
		var line: String = lines[i]
		if line.strip_edges() == "":
			continue
		var ind := _indent_of(line)
		if ind < want:
			return line.contains(opener)
	return false


func _indent_of(line: String) -> int:
	var n := 0
	while n < line.length() and (line[n] == "\t" or line[n] == " "):
		n += 1
	return n


## CONTROL for the whole file: if a clamp with min > max ever returns its MIN, every premise above
## dissolves and these arms defend nothing.
func test_control_a_clamp_with_no_room_returns_the_negative_bound() -> void:
	assert_eq(clampi(5, 0, -1), -1,
		"clampi returned its min — the empty-list hazard this file is about would not exist")
	assert_eq(clampi(0, 0, -1), -1, "…and the same for an index already at zero")


func test_every_dereference_of_a_clamped_index_is_guarded_or_that_clamp_is() -> void:
	for spec in CONSUMER_GUARDED:
		var src := _src(spec["path"])
		var deref := "%s[%s]" % [spec["list"], spec["idx"]]
		var n := src.count(deref)
		assert_gt(n, 0,
			"CONTROL: %s must dereference %s somewhere, or this arm is about nothing"
			% [spec["name"], deref])

		# Site-scoped: has THIS clamp gained a low bound? Not "does the file contain one anywhere".
		var this_clamp_unguarded: bool = src.contains(spec["unguarded_clamp"])
		# ⚠️ PER FUNCTION, not per dereference. Two reads inside ONE guarded function are correct
		# code; a file-wide `guards >= derefs` count calls that a defect. Measured: JukeboxMenu
		# reads TRACKS[selected_index] twice inside _play_selected behind its single `< 0` test,
		# and my first relation would have reddened it.
		var unguarded: Array = []
		for body in _functions(src):
			if not body.contains(deref):
				continue
			if body.contains("%s < 0" % spec["idx"]) or body.contains("%s >= 0" % spec["idx"]):
				continue
			unguarded.append(body.split("(")[0].replace("func ", ""))
		assert_true((not this_clamp_unguarded) or unguarded.is_empty(),
			("%s reads %s in %s with no low-end test, and its clamp has no low bound — an empty "
			% [spec["name"], deref, str(unguarded)])
			+ "list clamps to -1, so one of the two has to hold")


func test_the_gated_menus_still_refuse_to_page_an_empty_list() -> void:
	for spec in GATE_PROTECTED:
		var body := _input_body(_src(spec["path"]))
		assert_ne(body, "",
			"CONTROL: %s must define _input, or this arm reads nothing" % spec["name"])
		var gate_at := body.find("if %s.is_empty():" % spec["gate"])
		var clamp_at := body.find("MenuPaging.PAGE_ROWS")
		assert_gt(gate_at, -1,
			"%s must early-return inside _input while %s is empty — that gate, not the clamp, is "
			% [spec["name"], spec["gate"]] + "what keeps its page jump off a -1")
		assert_gt(clamp_at, -1,
			"CONTROL: %s must page inside _input, or the gate above guards nothing" % spec["name"])
		assert_true(gate_at < clamp_at,
			"%s's empty-list gate sits AFTER its page jump, so the jump runs first" % spec["name"])


## ⛔ CORRECTED after cowir-cutscenes: I filed CutsceneGallery as BY CONSTRUCTION, reasoning from
## the data shape (6 worlds, all non-empty). The real protection is a conditional wrapping the
## clamp — `if not world_items.is_empty():` on the line above it — which means an arm IS available
## and my verdict was derived from the wrong guard. "By construction" says nothing could expose it;
## "locally guarded" says a later edit could.
func test_a_locally_guarded_clamp_keeps_its_emptiness_check() -> void:
	for spec in LOCALLY_GUARDED:
		var src := _src(spec["path"])
		var bound := "%s.size() - 1" % spec["list"]
		# ⚠️ THE ENCLOSING FUNCTION, not the file. `if not world_items.is_empty():` occurs THREE
		# times here, so a file-wide find() returns a SIBLING occurrence and the arm passes with the
		# real one deleted — measured. Third time this exact shape bit an arm in this file.
		var owner := ""
		for body in _functions(src):
			if body.contains(bound):
				owner = body
				break
		assert_ne(owner, "",
			"CONTROL: %s must still clamp against %s inside some function, or this arm is about "
			% [spec["name"], spec["list"]] + "nothing")
		var clamp_guarded: bool = owner.contains("maxi(0, %s)" % bound)
		assert_true(clamp_guarded or _opened_by(src, spec["wrapper"], bound),
			"%s clamps against %s with neither a low bound nor `%s` as the block it sits in"
			% [spec["name"], spec["list"], spec["wrapper"]])


## ⛔ ARM B — PIN THE MECHANISM, NOT THE OUTCOME (cowir-battle's shape, after cowir-sfx measured the
## gap in their own repair). The arm above currently proves `_opened_by` works by RESULT: delete
## CutsceneGallery's enclosing guard and it reds. But revert `_opened_by` to a positional find and
## that same mutation PASSES, because the file's two sibling copies keep any find()-based bound
## satisfied. So the outcome proof cannot see the binding silently reverting to the defect it fixed.
func test_the_locally_guarded_arm_binds_by_indentation_not_by_position() -> void:
	var own := FileAccess.get_file_as_string(
		"res://test/unit/test_an_empty_list_index_is_never_dereferenced.gd")
	assert_gt(own.length(), 0, "this file must be able to read itself")
	var at := own.find("func test_a_locally_guarded_clamp_keeps_its_emptiness_check")
	assert_gt(at, -1, "CONTROL: the arm must exist, or this pin is about nothing")
	var rest := own.substr(at)
	var nxt := rest.find("\nfunc ")
	var arm_body: String = rest if nxt < 0 else rest.substr(0, nxt)
	assert_true(arm_body.contains("_opened_by("),
		"the locally-guarded arm no longer binds structurally — a positional bound cannot tell "
		+ "CutsceneGallery's enclosing guard from its two sibling copies")
	assert_false(arm_body.contains("find(spec[\"wrapper\"])"),
		"the arm is locating its guard by POSITION again; that is the defect _opened_by replaced")


## The mechanism itself, on SYNTHETIC input, because no live file can distinguish a correct bound
## from a lucky one: CutsceneGallery's siblings all precede the clamp, so a positional bound scores
## the same as a structural one there. Constructed input is the only place the difference shows.
func test_opened_by_distinguishes_the_enclosing_block_from_a_sibling() -> void:
	var src := "func demo():\n\tif not items.is_empty():\n\t\tvar a = 1\n\tif true:\n\t\tvar b = TARGET\n"
	assert_false(_opened_by(src, "if not items.is_empty():", "TARGET"),
		"a needle inside a LATER sibling branch must not read as opened by the earlier guard")
	var src2 := "func demo():\n\tif true:\n\t\tvar a = 1\n\tif not items.is_empty():\n\t\tvar b = TARGET\n"
	assert_true(_opened_by(src2, "if not items.is_empty():", "TARGET"),
		"a needle directly inside the guard's block must read as opened by it")
	var src3 := "func demo():\n\tif not items.is_empty():\n\t\tvar a = 1\n\tvar b = TARGET\n"
	assert_false(_opened_by(src3, "if not items.is_empty():", "TARGET"),
		"a needle AFTER the block, at the guard's own indentation, is outside it")
