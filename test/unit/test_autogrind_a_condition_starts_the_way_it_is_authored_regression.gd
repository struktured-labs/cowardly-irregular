extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file left autoload state for every later file.
var _ag_state: Dictionary

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const UI := "res://src/ui/autogrind/AutogrindUI.gd"

## `_cycle_condition_type` carried its own 12-entry type list, its own value table, and wrote
## `op = "<"` for every numeric type. SIX OF THE NINE that take an operator were wrong and FIVE were
## INVERTED: cycling to Battles produced `battles_done < 50` — true from battle zero, false forever
## after 50 — the exact inverse of "after 50 battles", which is the only reason anyone adds it. Same
## for Reached Lv, Corrupt, Effic and Inv Items: each fired while the quantity was LOW and stopped
## once it reached the number the player typed. Found by @cowir-main in a tree-wide sweep.
##
## ⚠️ NOT SILENT — the card renders the operator, so it reads `Battles < 50` and C cycles it. This is
## a wrong default a player can see and fix, not a dead rule. It is filed as bad defaults on the
## surface that exists to make rules easy, which is why it is worth a guard rather than a shrug.
##
## ⚠️ AND IT WAS STICKY, which is the half a defaults table alone would not fix: the op was written
## only `if not cond.has("op")`, so a cell that began as Party HP% kept `<` through every later type.
## The operator belonged to whichever type the cell was FIRST, not the one it displays.

var _vp: SubViewport = null
var _ed: Node = null


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	## Drives a UI node that reaches AutogrindSystem's savers; the one-hop ratchet cannot see it
	AutogrindSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ed = load(ED).new()
	_vp.add_child(_ed)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null
	AutogrindState.restore(_ag_state)



## Put one condition cell under the cursor and cycle until its type is `want`.
func _cycle_to(want: String) -> Dictionary:
	_ed.rules = [{"conditions": [{"type": "always"}], "actions": []}]
	_ed.cursor_row = 0
	_ed.cursor_col = 0
	## ⚠️ CYCLE FIRST, THEN CHECK. Seeding the cell as `always` and returning early when the type
	## already matches meant the `always` case was never actually PUT THERE by the code under test —
	## the arm read the seed's empty op and reported a defect in the fixture as one in the subject.
	for _i in 40:
		_ed._cycle_condition_type()
		var c: Dictionary = _ed.rules[0]["conditions"][0]
		if str(c.get("type", "")) == want:
			return c
	return {}


func test_every_offered_type_starts_with_the_op_the_system_authors() -> void:
	## THE CORPUS ARM: every type the editor offers, not the six that were wrong.
	var ids: Array = AutogrindSystem.party_level_condition_ids()
	assert_gt(ids.size(), 8, "CONTROL: the system must offer a real party-level set")
	var wrong: Array = []
	for id in ids:
		var c: Dictionary = _cycle_to(str(id))
		if c.is_empty():
			wrong.append("%s: never reached by cycling" % str(id))
			continue
		var want: Dictionary = AutogrindSystem.condition_defaults_for(str(id))
		if str(c.get("op", "")) != str(want.get("op", "")):
			wrong.append("%s: op %s, authored %s" % [str(id), str(c.get("op", "")), str(want.get("op", ""))])
	gut.p("    offered types: %d · wrong starting op: %d" % [ids.size(), wrong.size()])
	assert_eq(wrong, [],
		"the editor starts a condition with an operator the grammar does not author: %s" % str(wrong))


func test_the_five_inverted_ones_by_name() -> void:
	## ⛔ Pinned individually so a regression argues with the player-visible sentence, not a list.
	## `battles_done < 50` is true from battle zero and false forever after — the inverse.
	for id in ["battles_done", "corruption", "efficiency", "inventory_items", "reached_level"]:
		var c: Dictionary = _cycle_to(str(id))
		assert_false(c.is_empty(), "%s must be reachable by cycling" % str(id))
		assert_eq(str(c.get("op", "")), ">=",
			"%s starts with '%s' — a rule that fires while the quantity is LOW and stops once it reaches the number the player typed" % [str(id), str(c.get("op", ""))])
	var alive: Dictionary = _cycle_to("alive_count")
	assert_eq(str(alive.get("op", "")), "<=", "alive_count is authored <=, not <")


func test_the_operator_follows_the_type_rather_than_the_cell_s_first_life() -> void:
	## ⛔ THE STICKY ARM, and the one a defaults table alone does not satisfy. Reach a `<` type
	## FIRST, then cycle on to a `>=` type: the op must change with it. The old code wrote the op
	## only when absent, so this is exactly the path that produced `battles_done < 50` in play.
	var hp: Dictionary = _cycle_to("party_hp_avg")
	assert_false(hp.is_empty(), "CONTROL: party_hp_avg must be reachable")
	assert_eq(str(hp.get("op", "")), "<", "CONTROL: party_hp_avg is authored '<', so the cell really is carrying '<' before we move on")
	var cell: Dictionary = _ed.rules[0]["conditions"][0]
	for _i in 40:
		if str(cell.get("type", "")) == "battles_done":
			break
		_ed._cycle_condition_type()
		cell = _ed.rules[0]["conditions"][0]
	gut.p("    party_hp_avg '<' -> battles_done '%s'" % str(cell.get("op", "")))
	assert_eq(str(cell.get("op", "")), ">=",
		"the operator survived a type change — it belongs to whichever type the cell was FIRST, which is the actual mechanism of this bug")


func test_the_editor_offers_every_party_condition_the_evaluator_supports() -> void:
	## The private list also omitted win_streak and time_elapsed — party-level, evaluated, and
	## already rendered by _format_condition. The editor could DISPLAY conditions it could not offer.
	var ids: Array = AutogrindSystem.party_level_condition_ids()
	var src: String = GdSource.code_of(ED)
	var missing: Array = []
	for id in ids:
		if not src.contains('"%s"' % str(id)):
			missing.append(str(id))
	gut.p("    party-level ids: %s" % str(ids))
	assert_true(ids.has("win_streak") and ids.has("time_elapsed"),
		"win_streak / time_elapsed left the party-level set — they are evaluated and were the two the old private list omitted")
	assert_eq(missing, [],
		"the editor cannot render a party-level condition it now offers: %s" % str(missing))


func test_there_is_one_owner_for_the_defaults() -> void:
	## ⛔ ANTI-DUPLICATION. The console's table held correct defaults that the editor could not reach,
	## so the editor grew its own. Either file carrying them again recreates exactly that.
	var src: String = GdSource.code_of(ED)
	var ui: String = GdSource.code_of(UI)
	assert_false(src.contains('cond["op"] = "<"'),
		"the editor writes a literal operator again — that is the six-of-nine bug")
	assert_false(src.contains("var types = ["),
		"the editor carries its own condition-type list again, which is how it drifted from the grammar")
	for line in ui.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue
		assert_false(t.contains('"default_op"'),
			"AutogrindUI authors default_op again — AutogrindSystem.CONDITION_DEFAULTS is the owner")
	var sys: String = GdSource.code_of("res://src/autogrind/AutogrindSystem.gd")
	assert_true(sys.contains("const CONDITION_DEFAULTS"), "CONTROL: the owner must exist")
