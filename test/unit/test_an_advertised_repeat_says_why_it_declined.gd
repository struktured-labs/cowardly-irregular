extends GutTest

## ⛔ THE HINT BAR ADVERTISES REPEAT ON EVERY TURN AND THE PRESS WAS SILENT ON ROUND ONE.
## `Win98Menu.hint_text()` builds its Repeat token unconditionally, so the bar says "Ⓨ Repeat" from
## the first selection phase. `BattleManager.repeat_previous_actions()` declines for three reasons
## and `BattleScene._repeat_previous_actions` had a fourth gate above it — and all four produced
## NOTHING a player could see. The reasons existed, as `print()`, which goes to stdout.
##
## 🔑 THIS IS NOT THE EMPTY-INTERACT CASE, and the distinction is why it is worth fixing. Pressing
## interact on bare ground is SPECULATIVE — the player chose to poke something. Here the GAME
## advertised the control. An advertised action that declines in silence teaches the player that the
## bar lies, and the most common instance is round one of every battle.
##
## ✅ The reasons live in BattleManager, beside the conditions that produce them, because the
## alternative is re-testing those conditions in BattleScene and keeping two sources in step.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

var _bm: RefCounted = null
var _saved_state = null
var _saved_rounds: Dictionary = {}
var _saved_reason: String = ""


## ⛔ THIS FILE WRITES THREE AUTOLOAD FIELDS AND MUST PUT ALL THREE BACK. BattleStateHelper
## CLEANS UP a running battle; it does not restore `current_state` to the value it found, and it
## knows nothing about `previous_round_actions` or `last_repeat_refusal`. Leaning on it left this
## file named by `test_battle_state_not_leaked_by_tests`, whose rule is exactly right: a file whose
## every `current_state` assignment is a LITERAL never restores a saved one.
func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()
	_saved_state = BattleManager.current_state
	_saved_rounds = BattleManager.previous_round_actions.duplicate(true)
	_saved_reason = str(BattleManager.last_repeat_refusal)


func after_each() -> void:
	BattleManager.current_state = _saved_state
	BattleManager.previous_round_actions = _saved_rounds
	BattleManager.last_repeat_refusal = _saved_reason
	if _bm != null:
		_bm.restore()
	_bm = null


func test_round_one_names_the_reason_it_cannot_repeat() -> void:
	BattleManager.previous_round_actions = {}
	BattleManager.last_repeat_refusal = ""
	var ok: bool = BattleManager.repeat_previous_actions()
	assert_false(ok, "PRECONDITION: with no remembered round there is nothing to repeat")
	assert_ne(BattleManager.last_repeat_refusal, "",
		"a refusal the bar advertised must NAME its reason — silence is the defect")
	assert_string_contains(BattleManager.last_repeat_refusal.to_lower(), "first round",
		"and the reason must be the TRUE one for this path, not a generic line: got '%s'"
			% BattleManager.last_repeat_refusal)


## Each refusal path must carry its OWN sentence. One shared string would be honest about the
## refusal and wrong about the cause, which is the thing a player acts on.
func test_the_three_refusals_do_not_share_one_sentence() -> void:
	var seen: Array = []
	## No previous round.
	BattleManager.previous_round_actions = {}
	BattleManager.last_repeat_refusal = ""
	BattleManager.repeat_previous_actions()
	seen.append(BattleManager.last_repeat_refusal)
	## A remembered round, but not in a selection state.
	BattleManager.previous_round_actions = {"pc_0": [{"type": "attack"}]}
	BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
	BattleManager.last_repeat_refusal = ""
	BattleManager.repeat_previous_actions()
	seen.append(BattleManager.last_repeat_refusal)
	for s in seen:
		assert_ne(str(s), "", "every reached path must set a reason; got %s" % [seen])
	assert_eq(seen.size(), seen.reduce(func(acc, x): return acc if acc.has(x) else acc + [x], []).size(),
		"the reasons must differ per cause, or the player is told the wrong thing: %s" % [seen])


## ⛔ THE ARM THE OTHERS DO NOT COVER, AND A MUTATION FOUND IT: every assert above drives
## `BattleManager` DIRECTLY, so deleting BattleScene's log-the-reason branch leaves all of them
## green -- measured, EC=0 -- while the player sees exactly the silence this file is about. The
## reasons are worth nothing unless the scene SAYS them. Second instance of this shape in two ticks
## for me, so it is pinned here rather than remembered.
##
## ⚠️ Read from the CODE half: the explanatory comment beside that branch names the very symbol
## this asserts, so a raw read passes with the branch gone.
func test_the_scene_actually_speaks_every_refusal() -> void:
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	var at: int = code.find("func _repeat_previous_actions")
	assert_gt(at, 0, "PRECONDITION: the handler must be findable in the code half")
	if at <= 0:
		return
	## ⛔ BOUNDED AT THE NEXT `func `, NOT AT A FIXED WIDTH. `substr(at, 900)` overran the
	## 713-char function by 187 chars into `_start_test_battle`, WHICH CALLS `log_message` TWICE --
	## so the log assert below could have passed with every `log_message` deleted from the function
	## it is about. Found by measuring the window, not by a mutation: M1 removes the variable too, so
	## it reds either way and the leak stays invisible. Third fixed-width window to bite me today.
	var upto: int = code.find("\nfunc ", at + 10)
	assert_gt(upto, at, "PRECONDITION: the handler must be followed by another func to bound against")
	if upto <= at:
		return
	var body: String = code.substr(at, upto - at)
	## The three facts, each separately deletable:
	assert_string_contains(body, "last_repeat_refusal",
		"the scene must read the reason BattleManager set, not invent or drop it")
	assert_string_contains(body, "log_message",
		"and must put it in the battle log -- the player-visible channel")
	assert_string_contains(body, "Repeating previous actions",
		"CONTROL: the SUCCESS path must still announce itself; the fix is symmetry, not new noise")
	## And the not-in-selection gate must speak too, which was the fourth silent path.
	var gate: int = body.find("if not is_in_selection")
	assert_gt(gate, 0, "the early gate must be the explaining form, not a bare return")
	if gate > 0:
		assert_string_contains(body.substr(gate, 200), "log_message",
			"pressing Repeat outside selection must say so -- it was the fourth silent path")


## ⛔ THE ARM THAT KEEPS THE PREMISE TRUE. The whole defect rests on the bar advertising Repeat
## unconditionally; if it ever became availability-aware, this file's subject would change and the
## reasons would matter less. Read from the source so a change to that is noticed here.
func test_the_bar_still_advertises_repeat_unconditionally() -> void:
	var code: String = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_ne(code, "", "PRECONDITION: Win98Menu must be readable")
	assert_string_contains(code, "repeat_hint()",
		"the bar must still build a Repeat token — this file exists because it is always advertised")
	## CONTROL: and the success path must still log, or "every path speaks" is only half true.
	var scene: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_string_contains(scene, "Repeating previous actions!",
		"CONTROL: the SUCCESS path must still announce itself; the fix is symmetry, not noise")
