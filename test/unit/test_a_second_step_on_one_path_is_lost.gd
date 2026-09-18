extends GutTest

## `MenuNav.step()` CONSUMES: on an analog event it sets the axis latch as a side effect, so a
## second call for the SAME event returns "" and that cursor step is silently dropped.
##
## ⛔ THE HAZARD IS UNGUARDABLE FROM INSIDE THE HELPER, WHICH IS WHY IT IS GUARDED HERE. Whether two
## call sites are safe depends on where the CALLER's early returns sit — a property of that file's
## control flow, invisible to `step()` and invisible to a menu's own tests, because the dropped step
## looks exactly like a direction the player did not press. MenuNav's docstring says it outright:
## "no guard would see it".
##
## So this file does the one thing that IS mechanical: it notices when a menu GAINS a second call
## site, and makes the author say why it is safe. Four menus have two today and each is correct for
## a reason living in that file. A fifth must be checked by hand — this arm is where that check is
## demanded, not where it is performed.
##
## 📌 The count in MenuNav's own docstring had already gone stale: it read "Five menus" and named
## `DialogueChoiceMenu`, a file no longer in the tree. That is exactly why the set is DERIVED here
## rather than restated there — a hand-maintained membership list goes quietly wrong when a sibling
## change moves the world under it, and this one had.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const CALL := "MenuNav.step("

## Menus that legitimately call step() twice, each with the reason it cannot double-consume.
## ⛔ This is an EXPLANATION list, not a skip list: a new entry is only correct once someone has
## traced that file's early returns, and the entry must say what they found.
const KNOWN_DOUBLE_CALLERS := {
	"JobMenu.gd": "one per mode handler (_handle_slot_input / _handle_job_input), mutually exclusive",
	"ItemsMenu.gd": "one per mode handler (_handle_item_list_input / _handle_target_selection_input)",
	"EquipmentMenu.gd": "one per mode handler (_handle_slot_input / _handle_item_input)",
	"SettingsMenu.gd": "_input dispatches to the quit-confirm's own handler and RETURNS before its own chain",
}


func _gd_files_under(root: String, out: Array) -> void:
	for f in DirAccess.get_files_at(root):
		if f.ends_with(".gd"):
			out.append("%s/%s" % [root, f])
	for d in DirAccess.get_directories_at(root):
		_gd_files_under("%s/%s" % [root, d], out)


func test_a_new_double_caller_must_be_explained() -> void:
	var files: Array = []
	_gd_files_under("res://src", files)

	## CONTROL: the walk must reach the subdirectories. MenuNav consumers live in src/ui,
	## src/ui/autogrind, src/ui/autobattle, src/cutscene, src/exploration and src/llm — a
	## non-recursive listing sees only the first and reports a clean subset of the question.
	assert_gt(files.size(), 200, "CONTROL: the recursive walk must reach the whole tree, got %d" % files.size())

	var callers: Array = []
	var doubles: Dictionary = {}
	for path in files:
		var code: String = GdSource.code_of(path)
		var n: int = code.count(CALL)
		if n >= 1:
			callers.append(path)
		if n >= 2:
			doubles[path.get_file()] = n

	## CONTROL: the derivation must find the consumers at all. An empty scan satisfies every
	## comparison below — the shrinking-corpus shape that makes a derived guard quietly vacuous.
	assert_gt(callers.size(), 20,
		"CONTROL: MenuNav has many consumers; deriving %d means the scan is broken, not that the "
		% callers.size() + "tree changed")

	var unexplained: Array = []
	for name in doubles:
		if not KNOWN_DOUBLE_CALLERS.has(name):
			unexplained.append(name)
	assert_true(unexplained.is_empty(),
		"%s now call MenuNav.step() TWICE and are not explained here. step() CONSUMES: if both " % [unexplained]
		+ "sites can run for ONE event the second returns \"\" and that cursor step is silently lost. "
		+ "Trace the file's early returns; if the sites are mutually exclusive, add it to "
		+ "KNOWN_DOUBLE_CALLERS with the reason — the entry is the explanation, not permission to skip.")


## The other direction, which keeps the list from rotting into a set of names nobody can justify:
## an entry whose file has stopped double-calling is a claim about code that no longer exists.
func test_the_explanation_list_has_no_dead_entries() -> void:
	var files: Array = []
	_gd_files_under("res://src", files)
	var doubles: Array = []
	for path in files:
		if GdSource.code_of(path).count(CALL) >= 2:
			doubles.append(path.get_file())

	assert_gt(doubles.size(), 0, "CONTROL: there must BE double-callers, or this arm measures nothing")
	var dead: Array = []
	for name in KNOWN_DOUBLE_CALLERS:
		if not (name in doubles):
			dead.append(name)
	assert_true(dead.is_empty(),
		"%s no longer call step() twice — drop the entry rather than leaving a stale exemption. " % [dead]
		+ "MenuNav's own docstring named DialogueChoiceMenu long after that file left the tree.")
