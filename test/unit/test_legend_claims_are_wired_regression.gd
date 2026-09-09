extends GutTest

## Every on-screen control legend must name only inputs the screen actually binds.
##
## This is the class that cost struktured's artist his rules: AutobattleGridEditor's legend read
## "B:Delete", which was TRUE and lethal, and later "Click:Edit" nearly vanished from the same
## fixed-width line while left-click editing stayed wired at 7 sites. A legend is the only place
## most players learn the controls, and nothing has ever forced it to agree with the input handler.
##
## Swept 2026-09-09: 28 claims across 4 files, 0 unresolved. This pins that, it does not fix it.
##
## MECHANICAL BY CONSTRUCTION — no word list, no threshold, no similarity score. A claim resolves
## if the file contains the binding symbol for the token it names. A token is allowed to resolve
## through EITHER a keyboard or a pad binding, so the test never has to guess which kind it is;
## that keeps a wrong guess from inventing a failure.

const LEGEND_FILES := [
	"res://src/ui/SaveScreen.gd",
	"res://src/ui/VirtualKeyboard.gd",
	"res://src/ui/autobattle/AutobattleGridEditor.gd",
	"res://src/ui/autogrind/AutogrindGridEditor.gd",
]

## token -> any one of these symbols present in the file satisfies the claim
const BINDING := {
	"A": ["ui_accept"], "B": ["ui_cancel"], "X": ["JOY_BUTTON_X"], "Y": ["JOY_BUTTON_Y"],
	"L": ["battle_defer"], "R": ["battle_advance"], "Start": ["ui_menu"],
	"Select": ["battle_toggle_auto", "JOY_BUTTON_BACK"],
	"D-Pad": ["ui_up"], "Up/Dn": ["ui_up"], "RStick": ["JOY_AXIS_RIGHT_X"],
	"RClick": ["add_right_click_cancel"], "Click": ["make_clickable"],
	"Esc": ["ui_cancel"], "Del": ["KEY_DELETE"], "Tab": ["KEY_TAB"],
	"Sel": ["battle_toggle_auto", "JOY_BUTTON_BACK"],
}


func _legend_lines(src: String) -> Array:
	var out := []
	var re := RegEx.new()
	re.compile('\\.text\\s*=\\s*"([^"]*)"')
	for m in re.search_all(src):
		var t := m.get_string(1)
		if t.split(":").size() >= 3:  # 2+ Token:Verb pairs
			out.append(t)
	return out


func _claims(line: String) -> Array:
	var out := []
	for chunk in line.split(" ", false):
		if not chunk.contains(":"):
			continue
		var tok := chunk.split(":")[0]
		if tok != "" and not tok.begins_with("\\u"):
			out.append(tok)
	return out


func _resolves(src: String, tok: String) -> bool:
	if BINDING.has(tok):
		for sym in BINDING[tok]:
			if src.contains(sym):
				return true
		return false
	# composite ("Del/Y", "B/Esc", "W/S", "Sh+Tab") resolves if ANY part does
	if tok.contains("/") or tok.contains("+"):
		for part in tok.replace("+", "/").split("/", false):
			if _resolves(src, part):
				return true
		return false
	if tok.length() == 1:
		return src.contains("KEY_%s" % tok.to_upper())
	return src.contains("KEY_%s" % tok.to_upper())


## THE RATCHET. A legend naming an input the screen does not bind is a lie the player pays for.
func test_every_legend_claim_resolves_to_a_real_binding() -> void:
	var checked := 0
	for path in LEGEND_FILES:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 0, "CONTROL: %s must be readable, else this sweep proves nothing" % path)
		for line in _legend_lines(src):
			for tok in _claims(line):
				checked += 1
				assert_true(_resolves(src, tok),
					"%s advertises '%s' and binds nothing for it — legend: %s" % [path.get_file(), tok, line])
	# 39 when written. A regex-based version of this same check read 6 of 11 claims on one line —
	# its verb pattern allowed spaces, so "K:Compose  Sel" parsed as one claim and swallowed the
	# next token. It reported a clean sweep over half the corpus. Splitting on whitespace has no
	# such gap, and this floor makes a shrinking population fail rather than pass quietly.
	assert_gt(checked, 30,
		"the sweep must inspect the whole corpus (39 claims when written), got %d" % checked)


## CONTROL: the resolver must be able to say NO, or the arm above passes on anything.
func test_the_resolver_can_report_absence() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindGridEditor.gd")
	assert_true(_resolves(src, "K"), "a key the file DOES bind must resolve")
	assert_true(_resolves(src, "D-Pad"), "and a pad token the file DOES bind")
	assert_false(_resolves(src, "Q"), "a key the file does NOT bind must not resolve")
	assert_false(_resolves(src, "Zed"), "nor a fabricated multi-character token")


## CONTROL: the extractor must find the legends. If it returned nothing the ratchet is vacuous
## and would stay green through any lie.
func test_the_extractor_finds_a_legend_in_every_listed_file() -> void:
	for path in LEGEND_FILES:
		var lines := _legend_lines(FileAccess.get_file_as_string(path))
		assert_gt(lines.size(), 0, "%s must yield at least one legend, else it is silently unswept" % path)
