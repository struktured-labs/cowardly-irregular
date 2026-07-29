extends GutTest

## The cutscene→story-flag mirror was guarded by NINETEEN assertions across
## three files, every one of them a source-text pin. None drove the helper.
##
## `_set_cutscene_flag_and_mirror` writes `game_constants[flag]` AND mirrors
## the *bare* name (prefix stripped) into `story_flags`. QuestLog reads
## `get_story_flag` with no game_constants fallback, so if the mirror breaks,
## objectives the player has completed keep showing as incomplete. That is
## the tick-333 bug this helper exists to prevent.
##
## MEASURED 2026-07-29, two mutations:
##   A  `var bare = flag` (mirror the PREFIXED name)
##      -> 18/19 green. Caught by exactly one assertion, and only because it
##         happens to pin the substr line I chose. @cowir-controller's
##         "caught for the wrong reason".
##   B  wrap the mirror in `if bare.begins_with("world"):`
##      -> 19/19 GREEN. Every pinned string survives; the mirror is dead for
##         every chapter/spotlight/quest flag in the game.
##
## B is a plausible refactor ("scope the mirror to world flags"), shares no
## string with A, and no guard in the codebase noticed. @cowir-ai's class:
## a source-text pin is a claim about the code's SPELLING where we meant its
## BEHAVIOUR. The condition-carrying word here was the mirror's SCOPE — and
## nothing varied it.
##
## The existing source pins are kept. They catch a different class (the call
## being removed outright) and cost nothing. The defect was believing they
## covered behaviour.

const GAMELOOP := "res://src/GameLoop.gd"

var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	if GameState:
		_saved_constants = GameState.game_constants.duplicate(true)
		if "story_flags" in GameState:
			_saved_story = GameState.story_flags.duplicate(true)
		# CLEAR, don't just save. GameState is an autoload and its dicts persist
		# for the whole GUT run, so a flag another test set makes these asserts
		# prove "this flag is set" rather than "this call set it".
		# PROVEN vacuous 2026-07-29: neuter the helper with an early return,
		# pre-stamp chapter1_complete, and test_mirror_writes_the_bare_name
		# PASSES. @cowir-sfx's cooldown-stamp shape (msg-3382) — an accurate
		# assertion unearned by its context.
		GameState.game_constants = {}
		if "story_flags" in GameState:
			GameState.story_flags = {}


## Precondition + action + postcondition. Asserting the flag is ABSENT first is
## what makes the postcondition mean "this call did it" instead of "it is true".
func _assert_mirrors(gl, flag: String, bare: String) -> void:
	assert_false(GameState.get_story_flag(bare),
		"PRECONDITION: '%s' must be clear before the call, or the assertion below proves nothing" % bare)
	gl._set_cutscene_flag_and_mirror(flag)
	assert_true(GameState.get_story_flag(bare),
		"'%s' must mirror — QuestLog reads get_story_flag with no game_constants fallback, so a broken mirror shows completed objectives as incomplete" % bare)


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants
		if "story_flags" in GameState:
			GameState.story_flags = _saved_story


## Bare instance — deliberately NOT added to the tree, so _ready never runs
## and we exercise the helper rather than booting the game.
func _loop():
	var gl = load(GAMELOOP).new()
	assert_not_null(gl, "GameLoop script must instantiate")
	return gl


func test_mirror_writes_the_bare_name_to_story_flags() -> void:
	# THE regression. Mutation A made this write the PREFIXED name; QuestLog
	# reads bare, so the objective stays incomplete forever.
	var gl = _loop()
	_assert_mirrors(gl, "cutscene_flag_chapter1_complete", "chapter1_complete")
	assert_false(GameState.get_story_flag("cutscene_flag_chapter1_complete"),
		"the prefixed name must NOT be what lands in story_flags")
	gl.free()


func test_mirror_is_not_scoped_to_any_flag_family() -> void:
	# Mutation B survived all 19 source pins: wrapping the mirror in
	# `if bare.begins_with("world")` kills it for every chapter, spotlight
	# and quest flag while every pinned string stays present. Drive several
	# families so a scope condition on ANY of them fails here.
	# DERIVED from _CUTSCENE_COMPLETION_FLAGS, not a hand-picked sample. This
	# used to drive four flags I happened to think of; measured 2026-07-29,
	# the map holds 55 flags across 15 leading-token families and those four
	# covered FOUR of them — world2..world6 and `arbiter` were all
	# unrepresented, so `if bare.begins_with("world1")` passed cleanly.
	# @cowir-sfx: the bug report is a sample, the guard should assert the
	# invariant. @cowir-story: incident vocabulary vs the class.
	var gl = _loop()
	var flags := _completion_flags()
	assert_gt(flags.size(), 20,
		"POSITIVE CONTROL: the completion map must yield many flags — an empty or tiny parse makes every assertion below vacuous")
	for flag in flags:
		var bare: String = flag.substr("cutscene_flag_".length())
		_assert_mirrors(gl, flag, bare)
	gl.free()


## Every cutscene_flag_* the completion map can hand the helper.
##
## Derived from the CONSTANT ITSELF, not from GameLoop.gd's source text. The
## first version regex'd the file — which derives the set from HOW THE DICT IS
## WRITTEN rather than from the dict. @cowir-sfx (msg-3489): derive from
## something true of the thing, never true of how the thing is spelled. A flag
## added by any other form — a computed key, different quoting, a merged dict —
## silently leaves the set and takes its own assertion with it.
func _completion_flags() -> Array:
	var script: GDScript = load(GAMELOOP)
	assert_not_null(script, "GameLoop script must load")
	var map = script.get("_CUTSCENE_COMPLETION_FLAGS")
	assert_true(map is Dictionary, "_CUTSCENE_COMPLETION_FLAGS must be a Dictionary")
	var out: Array = []
	for v in (map as Dictionary).values():
		var f := str(v)
		if f.begins_with("cutscene_flag_") and not out.has(f):
			out.append(f)
	return out


func test_mirror_also_writes_game_constants() -> void:
	# Positive control on the OTHER half. Without it, a helper that mirrored
	# to story_flags and stopped writing game_constants would satisfy the
	# tests above while every gate keyed on game_constants silently failed.
	var gl = _loop()
	gl._set_cutscene_flag_and_mirror("cutscene_flag_chapter1_complete")
	assert_true(bool(GameState.game_constants.get("cutscene_flag_chapter1_complete", false)),
		"game_constants must still receive the FULL flag — _get_pending_story_cutscene gates read it there")
	gl.free()


func test_non_cutscene_flags_do_not_mirror() -> void:
	# The prefix check is real behaviour, not decoration: a bare write must
	# not leak a mangled name into story_flags.
	var gl = _loop()
	gl._set_cutscene_flag_and_mirror("some_other_flag")
	assert_true(bool(GameState.game_constants.get("some_other_flag", false)),
		"a non-cutscene flag still lands in game_constants")
	assert_false(GameState.get_story_flag("some_other_flag"),
		"only cutscene_flag_* mirrors — otherwise the prefix strip is meaningless")
	gl.free()


func test_empty_and_null_guards_hold() -> void:
	var gl = _loop()
	var before: int = GameState.game_constants.size()
	gl._set_cutscene_flag_and_mirror("")
	assert_eq(GameState.game_constants.size(), before,
		"an empty flag must write nothing at all")
	gl.free()
