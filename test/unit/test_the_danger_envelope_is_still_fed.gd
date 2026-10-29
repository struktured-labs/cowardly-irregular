extends GutTest

## The danger envelope's FEED crosses an UNTYPED boundary, so nothing resolves it at parse time.
##
##   BattleScene._update_danger_music()        turns live party HP into music intensity
##   BattleUIManager.update_ui()               its ONLY caller in all of src/
##   SoundManager.set_danger_intensity()       the sink it exists to reach
##
## `_scene` is untyped BY DESIGN ("untyped to avoid circular dependency", BattleUIManager:9), so
## `_scene._update_danger_music()` is not checked by the parser. Rename the method on BattleScene
## and that call still COMPILES: it fails at runtime, and a GDScript error aborts its enclosing
## function, which is `update_ui` — at its LAST statement. Every panel, bar and button updated;
## only the music silently stops tracking party HP. There is no loud direction.
##
## ⛔ WHICH IS WHY THIS FILE EXISTS RATHER THAN A SWEEP. The SINK is well covered and the FEED was
## covered by nothing. Measured on b515f7227 over test/**/*.gd, this file excluded:
##
##   14  touch the envelope API   set_danger_intensity|reset_danger|_apply_danger_intensity|_start_danger_music
##    7  name set_danger_intensity                    -- they drive the sink directly
##    0  name _update_danger_music                    -- nothing names the feed
##    0  name BattleUIManager and danger together     -- control: 39 name BattleUIManager, so the 0 is a real zero
##
## Every one of those 14 reaches SoundManager without going through the feed, so cutting the call
## leaves party HP no longer moving the music with all 14 still green.
##
## 🔑 THE FEED'S NAME IS DERIVED, NOT PINNED. An earlier draft of this file asserted the literal
## `_scene._update_danger_music()` and would have red on a correct lockstep rename — a ratchet on a
## coincidental spelling, which reds on the right change and says nothing about the relationship.
## What is pinned instead is the CHAIN: some call `update_ui` makes on `_scene` resolves to a method
## BattleScene declares whose body reaches the sink. A lockstep rename passes; a one-sided rename,
## a deleted call site or a discarded intensity each red, and each reds with its own message.
##
## Prose naming a symbol cannot satisfy any arm — every read goes through GdSource — and the
## extractor carries its own controls, because a body it failed to find and a body with the call
## removed are the same empty string.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const SCENE := "res://src/battle/BattleScene.gd"
const UIM := "res://src/battle/BattleUIManager.gd"
const SOUND := "res://src/audio/SoundManager.gd"
const CALLER := "update_ui"
const SINK := "set_danger_intensity"

## A token authored INSIDE update_ui, and one authored only AFTER it: the extractor's two bounds.
const INSIDE_CALLER := "update_character_status"
const BELOW_CALLER := "bg_color"


## One top-level func's own code: from its `func <name>(` line to the next column-0 `func`.
## Anchored on the exact declaration rather than on the first mention, because a first-mention
## anchor returns the whole file whenever the symbol is named above any `func` — which reads as a
## very thorough extraction and is this lane's own measured instrument bug.
func _func_code(path: String, fname: String) -> String:
	var out := PackedStringArray()
	var inside := false
	for raw in GdSource.code_of(path).split("\n"):
		var line: String = raw
		if line.begins_with("func %s(" % fname) or line.begins_with("static func %s(" % fname):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out.append(line)
	return "\n".join(out)


## Every method name this body invokes on the untyped `_scene`.
func _scene_calls_in(body: String) -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.create_from_string("_scene\\.([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	for m in rx.search_all(body):
		var name: String = m.get_string(1)
		if not out.has(name):
			out.append(name)
	return out


## The call in update_ui that actually reaches the sink, named by the code rather than by this file.
func _derived_feed() -> String:
	for name in _scene_calls_in(_func_code(UIM, CALLER)):
		var body := _func_code(SCENE, name)
		if body != "" and ("SoundManager.%s(" % SINK) in body:
			return name
	return ""


func test_control_the_extractor_is_bounded_and_can_say_no() -> void:
	var body := _func_code(UIM, CALLER)
	assert_true(INSIDE_CALLER in body,
		"extractor found no %s body — every arm below would pass vacuously on an empty string" % CALLER)
	assert_false(BELOW_CALLER in body,
		"extractor ran past %s into the next function; an unbounded body accepts any call in the file" % CALLER)
	assert_eq(_func_code(UIM, "a_function_this_file_does_not_declare"), "",
		"extractor must return nothing for a function that is absent, or absence reads as presence")
	assert_true(_scene_calls_in("\t_scene.some_call()\n\t_scene.other(1)").size() == 2,
		"the _scene call reader must find both calls in a two-call body, or its zero means nothing")


func test_the_ui_path_still_reaches_the_music() -> void:
	var feed := _derived_feed()
	assert_ne(feed, "",
		("no call %s() makes on _scene resolves to a BattleScene method reaching SoundManager.%s — " +
		"party HP has stopped feeding the music, and the 14 envelope guards cannot see it. " +
		"_scene calls found: %s") % [CALLER, SINK, str(_scene_calls_in(_func_code(UIM, CALLER)))])


func test_every_crossing_in_that_path_resolves_to_a_real_method() -> void:
	var scene_code := GdSource.code_of(SCENE)
	var calls := _scene_calls_in(_func_code(UIM, CALLER))
	assert_true(calls.size() > 0, "no _scene calls found in %s — the arm below would pass vacuously" % CALLER)
	for name in calls:
		assert_true("func %s(" % name in scene_code,
			("%s() calls _scene.%s() and BattleScene declares no such method. The call is untyped, " +
			"so this is a RUNTIME error that aborts %s at that statement — the UI finishes, the " +
			"music does not.") % [CALLER, name, CALLER])


func test_the_sink_still_answers_under_that_name() -> void:
	assert_true("func %s(" % SINK in GdSource.code_of(SOUND),
		"SoundManager no longer declares %s, so the feed computes an intensity nothing receives" % SINK)
