extends GutTest

## ⛔ A CLAMP DOES NOT PROTECT AN EMPTY LIST. Measured, and it is the premise for everything below:
##
##     clampi(5, 0, -1)  == -1      clampi(0, 0, -1) == -1      clamp(5, 0, -1) == -1
##
## When `max < min` the MAX wins, so `clampi(i, 0, list.size() - 1)` on an empty list yields -1 for
## every non-negative input. Eight sites in src/ui/ spell it that way (cowir-battle's sweep).
##
## 🔑 NONE OF THE SIX SURFACES IS EXPOSED TODAY, and they are safe for THREE DIFFERENT REASONS.
## The clamp is not what protects any of them:
##
##   CONSUMER-GUARDED   BossSelectorMenu · RadialPicker
##     the index DOES become -1 — measured, both reach it on an emptied list via paging AND nav —
##     and every dereference tests the low end first. A stored -1 nobody reads is not a bug
##     (cowir-music's rule), and it stops being true the moment a consumer drops its guard.
##
##   GATE-PROTECTED     PartyChatMenu · BestiaryMenu
##     the handler early-returns while `_chats` / `_entries` is empty, so the clamp is unreachable.
##     Measured: both stay at 0 with every list emptied.
##
##   BY CONSTRUCTION    CutsceneGallery · TitleScreen
##     `_world_order` holds only worlds that HAVE entries; menu_items is built with four rows.
##     Measured headless: 6/6 and 4. No arm — a pin on "the builder appends at least one" would red
##     on a legitimate change, and the builders already say it more clearly than a pin could.
##
## ⚠️ EVERY CHECK BELOW IS SITE-SCOPED, AND THAT IS NOT STYLE — MY FIRST VERSION WAS VACUOUS TWICE
## OVER, caught by mutation rather than by reading:
##   · RadialPicker carries `maxi(0, _options.size() - 1)` at :45 and an UNGUARDED clamp at :172.
##     A file-scoped `contains(maxi…)` is satisfied by the guarded SIBLING — the within-file
##     asymmetry that makes this shape interesting is exactly what blinded the instrument to it.
##   · `if _chats.is_empty():` occurs TWICE in PartyChatMenu, so deleting one left `contains()` true.
##   · and the guard count missed the `>= 0` spelling, which is half of the guards in play.

const CONSUMER_GUARDED := [
	{"name": "BossSelectorMenu", "path": "res://src/ui/BossSelectorMenu.gd",
		"list": "_selectable_indices", "idx": "selected_index",
		"unguarded_clamp": "clampi(selected_index + page * MenuPaging.PAGE_ROWS, 0, _selectable_indices.size() - 1)"},
	{"name": "RadialPicker", "path": "res://src/ui/RadialPicker.gd",
		"list": "_options", "idx": "_selected",
		"unguarded_clamp": "clampi(_page * RING_CAPACITY, 0, _options.size() - 1)"},
]

const GATE_PROTECTED := [
	{"name": "PartyChatMenu", "path": "res://src/ui/PartyChatMenu.gd", "gate": "_chats"},
	{"name": "BestiaryMenu", "path": "res://src/ui/BestiaryMenu.gd", "gate": "_entries"},
]


func _src(p: String) -> String:
	var s := FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 0, "%s must load" % p)
	return s


## The body of `func _input(...)` only — a gate elsewhere in the file protects nothing here.
func _input_body(src: String) -> String:
	var at := src.find("func _input(")
	if at < 0:
		return ""
	var rest := src.substr(at)
	var nxt := rest.find("\nfunc ")
	return rest if nxt < 0 else rest.substr(0, nxt)


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
		# Both spellings count — `idx < 0` and `idx >= 0` are the same guard written two ways.
		var low_guards: int = src.count("%s < 0" % spec["idx"]) + src.count("%s >= 0" % spec["idx"])
		assert_true((not this_clamp_unguarded) or low_guards >= n,
			("%s dereferences %s %d time(s) behind %d low-end guard(s), and its clamp still has no "
			% [spec["name"], deref, n, low_guards])
			+ "low bound — an empty list clamps to -1, so one of the two has to hold")


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
