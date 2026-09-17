extends GutTest

## The AUTOBATTLE rule grid got hold-to-repeat earlier today as "the last long list with no fast
## route". Its AUTOGRIND twin never did — and that one has NO CAP ON RULES at all and no paging
## either, so every row was one press, forever.
##
## 🔑 THE GATES ARE DERIVED FROM THIS FILE, NOT COPIED FROM THE TWIN. They genuinely differ: the
## autobattle editor has a share picker, an option picker, a simulate panel and a portrait focus;
## this one has none of those and has a reset-confirmation prompt the other lacks. Copying the
## twin's blocker would have guarded four members that do not exist here and missed the one that does.

const GridScript = preload("res://src/ui/autogrind/AutogrindGridEditor.gd")
const SRC := "res://src/ui/autogrind/AutogrindGridEditor.gd"

## Past MenuRepeat.INITIAL_DELAY, so one tick arms the hold and the next fires.
const PAST_DELAY := 0.5

var _saved_persist: bool = false


func before_all() -> void:
	_saved_persist = AutogrindSystem._test_disable_persistence
	AutogrindSystem._test_disable_persistence = true


func after_all() -> void:
	AutogrindSystem._test_disable_persistence = _saved_persist


func after_each() -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")


func _editor(rule_count: int = 20) -> Node:
	var ed: Node = GridScript.new()
	add_child_autofree(ed)
	var rules: Array = ed.get("rules")
	rules.clear()
	for i in range(rule_count):
		rules.append({"conditions": [], "actions": []})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 0)
	ed.visible = true
	return ed


## Drives _process, the real tick — not _nav_step_row. An arm calling the step function would pass
## with nothing wired to it, which is the error three of my guards made today.
func _hold(ed: Node, action: String, ticks: int = 3) -> int:
	var before: int = int(ed.get("cursor_row"))
	Input.action_press(action, 1.0)
	for i in range(ticks):
		ed._process(PAST_DELAY)
	Input.action_release(action)
	return int(ed.get("cursor_row")) - before


func test_holding_down_walks_the_grid() -> void:
	var ed := _editor(20)
	assert_gt(_hold(ed, "ui_down"), 0,
		"a held direction must step the rule grid on its own — this editor caps rules at NOTHING "
		+ "and offers no page jump, so one row per press is the entire vocabulary")


func test_holding_up_walks_back() -> void:
	var ed := _editor(20)
	ed.set("cursor_row", 10)
	assert_lt(_hold(ed, "ui_up"), 0, "a held ui_up must walk back up the grid")


## CLAMPED, not wrapped: a hold at the top must stop, not jump to the bottom.
func test_the_hold_clamps_at_the_top() -> void:
	var ed := _editor(20)
	ed.set("cursor_row", 0)
	assert_eq(_hold(ed, "ui_up", 5), 0, "holding up at row 0 must stay at row 0, not wrap to the end")


func test_the_hold_clamps_at_the_bottom() -> void:
	var ed := _editor(5)
	ed.set("cursor_row", 4)
	assert_eq(_hold(ed, "ui_down", 5), 0, "holding down at the last rule must stay there")


## ⛔ DERIVED FROM `_input`, NOT FROM `_row_nav_blocked`. My first version read the gate list out of
## the blocker it was testing, so DELETING a gate deleted the check for it — mutation confirmed:
## dropping the reset-confirm gate left all nine arms GREEN. Numerator and denominator moved
## together, the same shape @cowir-sprites, @cowir-battle and @cowir-music each found in a coverage
## control within the hour.
##
## `_input`'s early returns are the SPEC: every overlay the press path refuses, the polled path must
## refuse too. Reading them from there means removing a gate from the blocker reds, because the
## spec still names it.
func _input_gates() -> Array:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of(SRC)
	var i: int = code.find("func _input(event: InputEvent)")
	assert_gt(i, -1, "CONTROL: _input must exist")
	var rest: String = code.substr(i + 5)
	var nxt: int = rest.find("\nfunc ")
	var body: String = rest.substr(0, nxt) if nxt > -1 else rest
	var out: Array = []
	for line in body.split("\n"):
		var s: String = line.strip_edges()
		# an overlay refusal: `if _x and is_instance_valid(_x) ...:` guarding a bare `return`
		if not s.begins_with("if _"):
			continue
		if not s.contains("is_instance_valid("):
			continue
		var tok: String = s.substr(3).split(" ")[0]
		if tok != "" and not out.has(tok):
			out.append(tok)
	return out


func test_the_gate_scan_finds_the_overlays() -> void:
	var gates := _input_gates()
	assert_gt(gates.size(), 1,
		"CONTROL: the scan of _input found %s — if it finds nothing the arms below pass over nothing"
			% [gates])


## Every overlay the PRESS path refuses must also be named by the polled path's blocker.
func test_the_blocker_mirrors_every_input_refusal() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of(SRC)
	var i: int = code.find("func _row_nav_blocked")
	assert_gt(i, -1, "CONTROL: _row_nav_blocked must exist")
	var rest: String = code.substr(i + 5)
	var nxt: int = rest.find("\nfunc ")
	var blocker: String = rest.substr(0, nxt) if nxt > -1 else rest
	var missing: Array = []
	for member in _input_gates():
		if not blocker.contains(member):
			missing.append(member)
	# assert_true, not assert_eq: GUT prints an array comparison INSTEAD of the message, and both
	# gate arms then fail with the identical "ARRAY([...]) != ARRAY([])".
	assert_true(missing.is_empty(),
		"_input refuses these overlays and _row_nav_blocked does not name them, so a HELD direction "
		+ "walks the grid behind them: %s" % [missing])


func test_every_overlay_gate_stops_the_hold() -> void:
	var leaked: Array = []
	for member in _input_gates():
		var ed := _editor(20)
		var blocker := Control.new()
		blocker.visible = true
		add_child_autofree(blocker)
		ed.set(member, blocker)
		if _hold(ed, "ui_down") != 0:
			leaked.append(member)
	assert_true(leaked.is_empty(),
		"the hold walked the grid while these overlays were open — MenuRepeat polls Input and "
		+ "inherits none of _input's refusals: %s" % [leaked])


## ⚠️ SCOPE, stated rather than implied: the scan above finds the `_`-prefixed Control overlays.
## `is_editing` is a bool and has its own arm below; `TutorialHint.is_any_active()` is a static call
## on another class, not a member of this one, and no arm here covers it.

func test_a_hidden_editor_does_not_walk() -> void:
	var ed := _editor(20)
	ed.set("cursor_row", 5)
	ed.visible = false
	assert_eq(_hold(ed, "ui_down"), 0, "a hold must not navigate a closed editor")


func test_an_editing_cell_blocks_the_hold() -> void:
	var ed := _editor(20)
	ed.set("is_editing", true)
	assert_eq(_hold(ed, "ui_down"), 0, "while a cell is being edited the hold must not move rows")


## ⛔ RATCHET: the two rule editors are twins and this divergence lasted until today.
func test_both_rule_editors_repeat_on_a_hold() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	for path in [SRC, "res://src/ui/autobattle/AutobattleGridEditor.gd"]:
		var code: String = GdSource.code_of(path)
		assert_ne(code, "", "CONTROL: %s must survive the comment strip" % path)
		assert_true(code.contains("MenuRepeat.new("),
			"%s has no hold-to-repeat — every rule is one press" % path)
		assert_true(code.contains("_nav_repeat.tick("),
			"%s constructs a MenuRepeat and never ticks it" % path)
