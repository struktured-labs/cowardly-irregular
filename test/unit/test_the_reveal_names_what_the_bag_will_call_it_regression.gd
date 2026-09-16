extends GutTest

## ⛔ 16 of the 21 authored key-item reveals announce a name `items.json` does not use:
##
##   arbiter_grade_fragment            reveal "Arbiter's Final Paper"      bag "Grade Fragment"
##   curator_budget_fragment           reveal "Curator's Final Ledger"     bag "Budget Fragment"
##   world3_fragment_tempo_steampunk   reveal "Tempo's Impossible Timecard" bag "Escapement Fragment"
##
## `_step_grant_item` passes the STEP's `name` to the popup, and all 16 items are category 4 (key
## items), which `ItemsMenu` lists — it filters only OFFENSIVE. So the player is told one name at the
## reveal and shown another in the bag, on the only two surfaces that ever name the thing.
##
## 🔑 WHICH name is canonical is cowir-story's call and this file does not touch it. That the player
## can FIND the item is not a style question, so when the two differ the bag's name is shown under the
## flavour name. The line DISAPPEARS on its own if the names are ever aligned — equal names render
## nothing — so this fix cannot outlive the divergence it exists for.

const PopupScript = preload("res://src/ui/KeyItemPopup.gd")
const CUTSCENE_DIR := "res://data/cutscenes"


func _popup(item: Dictionary) -> Node:
	var host := Node.new()
	add_child_autofree(host)
	var p = PopupScript.show_item(host, item)
	return p


func _labels_of(popup: Node) -> Array:
	var out: Array = []
	for n in popup.find_children("*", "Label", true, false):
		out.append(str(n.text))
	return out


## A divergent reveal must name the bag as well as the drama.
func test_a_divergent_reveal_names_the_bag_too() -> void:
	var canonical: String = PopupScript._canonical_name("arbiter_grade_fragment")
	assert_ne(canonical, "", "PRECONDITION: the fixture item must resolve in ItemSystem")
	if canonical == "":
		return
	var popup := _popup({"item_id": "arbiter_grade_fragment", "name": "Arbiter's Final Paper",
		"description": "A torn corner."})
	assert_not_null(popup)
	if popup == null:
		return
	var texts: Array = _labels_of(popup)
	var joined: String = " | ".join(texts)
	assert_true(joined.contains("Arbiter's Final Paper"), "the authored flavour name still headlines")
	assert_true(joined.contains(canonical),
		"and the bag's name must appear, or the player cannot find what they were just given: %s" % joined)


## The new line must not sit ON the description, and nothing may run into the hint row. My first
## arms compared only TEXTS, so the mutation that skipped moving the description stayed green — a
## label overlap is invisible to a text assert.
func test_the_bag_line_does_not_overlap_the_description() -> void:
	var canonical: String = PopupScript._canonical_name("arbiter_grade_fragment")
	if canonical == "":
		return
	var popup := _popup({"item_id": "arbiter_grade_fragment", "name": "Arbiter's Final Paper",
		"description": "A torn corner of a report card, kept because the grade is illegible."})
	var bag: Label = null
	var desc: Label = null
	for n in popup.find_children("*", "Label", true, false):
		var t: String = str(n.text)
		if t.begins_with("In your bag:"):
			bag = n
		elif t.begins_with("A torn corner"):
			desc = n
	assert_not_null(bag, "PRECONDITION: the divergent fixture must render the bag line")
	assert_not_null(desc, "PRECONDITION: and its description")
	if bag == null or desc == null:
		return
	assert_gte(desc.position.y, bag.position.y + bag.size.y,
		"the description must start below the bag line (bag ends %.0f, desc starts %.0f)" % [
			bag.position.y + bag.size.y, desc.position.y])
	# Against the REAL panel height, not the const — the card grows by a line when this line exists.
	var panel_h: float = popup._panel.size.y
	assert_gt(panel_h, PopupScript.PANEL_H,
		"a card carrying the extra line must be taller than the base card (%.0f vs %.0f)" % [panel_h, PopupScript.PANEL_H])
	assert_lte(desc.position.y + desc.size.y, panel_h - 22.0,
		"and nothing may run into the hint row at the bottom of the panel")


## CONTROL: an AGREEING reveal must NOT grow the line — otherwise every reveal says its name twice.
func test_an_agreeing_reveal_says_it_once() -> void:
	var canonical: String = PopupScript._canonical_name("arbiter_grade_fragment")
	if canonical == "":
		return
	var popup := _popup({"item_id": "arbiter_grade_fragment", "name": canonical, "description": "x"})
	var joined: String = " | ".join(_labels_of(popup))
	assert_false(joined.contains("In your bag:"),
		"names that already agree must render no second line: %s" % joined)
	assert_eq(popup._panel.size.y, PopupScript.PANEL_H,
		"and the card must stay its base height — the growth belongs to the extra line, not to every reveal")


## Case and whitespace are not a divergence.
func test_case_and_spacing_do_not_count_as_a_divergence() -> void:
	var canonical: String = PopupScript._canonical_name("arbiter_grade_fragment")
	if canonical == "":
		return
	var popup := _popup({"item_id": "arbiter_grade_fragment",
		"name": "  " + canonical.to_upper() + " ", "description": "x"})
	assert_false(" | ".join(_labels_of(popup)).contains("In your bag:"),
		"the comparison must be trimmed and case-insensitive, or shouting a name reads as a different item")


## An unknown id must not invent a bag name or throw.
func test_an_unknown_id_shows_no_bag_line() -> void:
	assert_eq(PopupScript._canonical_name("zzq_no_such_item"), "",
		"an unregistered id has no canonical name")
	assert_eq(PopupScript._canonical_name(""), "", "and neither does an empty one")
	var popup := _popup({"item_id": "zzq_no_such_item", "name": "Mystery", "description": "x"})
	assert_false(" | ".join(_labels_of(popup)).contains("In your bag:"),
		"nothing known about the item means nothing to promise about the bag")


## THE CORPUS, recorded rather than asserted into agreement: how many authored reveals diverge, and
## that every one of them at least RESOLVES — a reveal naming an unregistered id would grant nothing.
func test_every_authored_reveal_resolves_and_the_divergence_is_counted() -> void:
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir)
	if dir == null:
		return
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	var total: int = 0
	var divergent: Array = []
	var unresolved: Array = []
	for f in names:
		var d = JSON.parse_string(FileAccess.get_file_as_string(CUTSCENE_DIR + "/" + f))
		if not (d is Dictionary):
			continue
		for s in d.get("steps", []):
			if not (s is Dictionary) or str(s.get("type", "")) != "grant_item":
				continue
			var iid: String = str(s.get("item", ""))
			var shown: String = str(s.get("name", ""))
			if shown == "":
				continue
			total += 1
			var canonical: String = PopupScript._canonical_name(iid)
			if canonical == "":
				unresolved.append("%s: %s" % [f, iid])
			elif canonical.strip_edges().to_lower() != shown.strip_edges().to_lower():
				divergent.append(iid)
	gut.p("authored reveals with a name: %d · divergent from items.json: %d" % [total, divergent.size()])
	assert_eq(unresolved.size(), 0,
		"a reveal naming an id ItemSystem does not know grants nothing and promises something: %s" % str(unresolved))
	assert_gt(total, 15, "PRECONDITION: the authored reveals must load")
	# ANTI-VACUITY: if the corpus is ever aligned, this file's fix renders nothing and should be
	# retired deliberately rather than sitting here asserting a mechanism nothing reaches.
	assert_gt(divergent.size(), 0,
		"no authored reveal diverges any more — the names were aligned, so retire this file and the bag line with it")
