extends GutTest

## The option that ends the conversation sat on the row the cursor starts on.
##
## `_ensure_farewell` promised, in its own docstring AND at its call site, that the
## menu "always ends with a farewell option". Its body returned the moment it found
## one ANYWHERE:
##
##     ["I should go.", "What happened here?", "Who is the Chancellor?"]
##          ^ an exit, and _ensure_farewell leaves it exactly there
##
## `DialogueChoiceMenu.present()` sets `_selection = 0`, so row 0 is pre-highlighted
## when the menu opens. A leading exit therefore put the player ONE CONFIRM-PRESS
## from leaving a conversation they had just chosen to start — the most reflexive
## input a JRPG dialogue menu takes.
##
## ⛔ AND LEAVING IS NOT RECOVERABLE. Per `_is_farewell`'s own comment, a farewell
## "ends the conversation, banks the memory and settles the reward claim." The
## player does not get the exchange back by walking up to the NPC again.
##
## 🔑 NOTHING READ AS WRONG because the two comments already stated the correct
## behaviour — only the body disagreed. Same class as the LLMService late-reply
## comment and the LLMContext party note: a claim that is right about intent and
## wrong about mechanism survives review, because review checks the claim.
##
## ⚠️ LATENT FOR THE SHIPPED DEFAULT, measured rather than assumed. Live llama3 on
## the real combined-reply prompt, three conversation states, six samples each:
## **0 of 18 offered an exit at all** — every sample took the append path, which was
## already correct. This defends the BYOK surface, where any OpenAI-compatible
## model can be attached from Settings and a terse one opening with "I should go."
## is exactly the shape. Same standing as the dedupe that shipped before it.
##
## The fix also drops a SECOND exit rather than keeping it: two ways to leave is
## not two choices, and the menu has only REQUESTED_CHOICES + 1 rows to spend.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const MENU_SRC := "res://src/llm/DialogueChoiceMenu.gd"

var _dc: DynamicConversation


func before_each() -> void:
	_dc = DynamicConversation.new()
	_dc.name = "ExitRowConversation"
	add_child_autofree(_dc)


## The real pair, in the real order, as _do_player_turn calls them.
func _menu_for(initial: Array[String]) -> Array[String]:
	var choices: Array[String] = initial.duplicate()
	_dc._ensure_something_to_say(choices)
	_dc._ensure_farewell(choices)
	return choices


func _exit_rows(choices: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for i in choices.size():
		if _dc._is_farewell(choices[i]):
			out.append(i)
	return out


# ── the defect ────────────────────────────────────────────────────────────────

func test_an_exit_the_model_led_with_is_moved_to_the_last_row() -> void:
	## THE ARM. This is the shape that put the exit under the starting cursor.
	var menu: Array[String] = _menu_for(
		["I should go.", "What happened here?", "Who is the Chancellor?"])
	assert_false(_dc._is_farewell(menu[0]),
		("the pre-selected row still ends the conversation: %s. DialogueChoiceMenu "
		+ "opens on row 0, so one confirm-press leaves — and leaving banks the memory "
		+ "and settles the reward claim.") % str(menu))
	assert_eq(_exit_rows(menu), ([menu.size() - 1] as Array[int]),
		"the exit must be the last row and the only one: %s" % str(menu))


func test_the_choices_the_player_can_actually_say_keep_their_order() -> void:
	## Moving the exit must not shuffle the rest — the model ordered them.
	var menu: Array[String] = _menu_for(
		["Goodbye.", "What happened here?", "Who is the Chancellor?"])
	assert_eq(menu.size(), 3, "one exit plus the two real options: %s" % str(menu))
	assert_eq(str(menu[0]), "What happened here?", "first real option keeps its place")
	assert_eq(str(menu[1]), "Who is the Chancellor?", "second real option keeps its place")


func test_the_models_own_farewell_wording_is_the_one_kept() -> void:
	## Moving it must not replace it — "Goodbye." is the NPC's register, not ours.
	var menu: Array[String] = _menu_for(["Goodbye.", "Tell me more."])
	assert_eq(str(menu[menu.size() - 1]), "Goodbye.",
		"the model's exit line must survive the move verbatim: %s" % str(menu))


func test_a_second_exit_does_not_take_a_row_from_a_real_choice() -> void:
	## Two ways to leave is not two choices, and rows are scarce.
	var menu: Array[String] = _menu_for(["Goodbye.", "Tell me more.", "Farewell."])
	assert_eq(_exit_rows(menu).size(), 1,
		"only one exit may reach the menu: %s" % str(menu))
	assert_eq(_exit_rows(menu), ([menu.size() - 1] as Array[int]),
		"and it is the last row: %s" % str(menu))


# ── it must not disturb what already worked ───────────────────────────────────

func test_a_menu_with_no_exit_still_gets_one_appended() -> void:
	## CORRECT-WORK, and the path llama3 took 18 of 18 times. This is the behaviour
	## that was already right; the fix must not trade one failure for another.
	var menu: Array[String] = _menu_for(
		["What happened here?", "Who is the Chancellor?", "Tell me more."])
	assert_eq(menu.size(), 4, "three real options plus the appended exit: %s" % str(menu))
	assert_eq(str(menu[3]), "Farewell.", "the appended exit is last")
	assert_eq(_exit_rows(menu), ([3] as Array[int]), "and it is the only exit")


func test_a_menu_of_only_goodbyes_still_gets_real_options_first() -> void:
	## The sibling guard's case, run through the changed function. Its top-up must
	## still land ABOVE the exit rather than being reordered around it.
	var menu: Array[String] = _menu_for(["Farewell.", "Farewell.", "Farewell."])
	assert_gt(menu.size(), 1, "a lone exit is no menu: %s" % str(menu))
	assert_false(_dc._is_farewell(menu[0]),
		"the player must have something to say on the first row: %s" % str(menu))
	assert_eq(_exit_rows(menu), ([menu.size() - 1] as Array[int]),
		"and the exit is still last: %s" % str(menu))


func test_the_menu_never_exceeds_what_the_ui_can_show() -> void:
	## CONTROL on the capacity branch: appending an exit must not push past
	## MAX_CHOICES, whatever arrives.
	for initial in [["a", "b", "c", "d", "e"], ["a", "b", "c", "d"], ["Farewell."], []]:
		var typed: Array[String] = []
		for x in initial:
			typed.append(str(x))
		var menu: Array[String] = _menu_for(typed)
		assert_lte(menu.size(), DP.MAX_CHOICES,
			"a menu of %d rows cannot be shown: %s" % [menu.size(), str(menu)])
		assert_eq(_exit_rows(menu), ([menu.size() - 1] as Array[int]),
			"the exit is last whatever the input size: %s" % str(menu))


# ── the premise, and the call site ────────────────────────────────────────────

func test_the_cursor_really_starts_on_the_first_row() -> void:
	## THE PREMISE. If the menu ever opened on a different row, "the exit is on the
	## pre-selected row" stops being the reason this matters, and the severity
	## argument in the header needs re-reading rather than trusting.
	var src: String = FileAccess.get_file_as_string(MENU_SRC)
	assert_false(src.is_empty(), "CONTROL: DialogueChoiceMenu must load")
	assert_true(src.find("_selection = 0") != -1,
		("DialogueChoiceMenu no longer starts on row 0. The exit-position fix is still "
		+ "correct, but the one-confirm-press severity claim in this file's header "
		+ "was measured against a cursor that started at the top."))


func test_the_exit_pass_still_runs_after_the_top_up() -> void:
	## SOURCE CHECK, named as one. Every arm above calls the pair directly; if the
	## call site ever ran them in the other order, the top-up would append real
	## options AFTER the exit and these arms would not notice.
	var src: String = _code_only(
		FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd"))
	assert_false(src.is_empty(), "CONTROL: source must load")
	var say_at: int = src.find("_ensure_something_to_say(choices)")
	var bye_at: int = src.find("_ensure_farewell(choices)")
	assert_true(say_at != -1 and bye_at != -1, "CONTROL: both calls must exist")
	assert_lt(say_at, bye_at,
		"_ensure_something_to_say must run BEFORE _ensure_farewell, or the exit is not last")


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_farewell_detector_really_fires_on_these_fixtures() -> void:
	## CONTROL: every arm classifies rows with _is_farewell. If it did not recognise
	## the fixtures, "the exit is last" would pass on menus with no exit in them.
	for exit_line in ["I should go.", "Goodbye.", "Farewell.", "Take care."]:
		assert_true(_dc._is_farewell(exit_line),
			"'%s' must read as an exit, or the arms prove nothing" % exit_line)
	for keeper in ["What happened here?", "Tell me more.", "Who is the Chancellor?"]:
		assert_false(_dc._is_farewell(keeper),
			"'%s' must NOT read as an exit" % keeper)


func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)
