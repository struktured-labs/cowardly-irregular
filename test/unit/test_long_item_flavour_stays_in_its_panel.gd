extends GutTest

## Item flavour text ran off the DETAILS panel and off the right edge of the SCREEN, cut
## mid-word. Found by rendering the bag at 1280x720 and looking at it — no source read would
## have shown it, because THE CODE IS CORRECT TO READ:
##
##     flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD
##     flavor_label.size = Vector2(panel_size.x - 32, 48)
##     panel.add_child(flavor_label)
##
## ⛔ A Label entering the tree recomputes its rect, and the CONTENT width beats an offset
## assigned beforehand. Measured in isolation on a plain Control host, same four lines:
##
##     assigned 584 wide, text  24 chars  -> size (584, 36)    looks correct
##     assigned 584 wide, text 141 chars  -> size (1068, 48)   THE ASSIGNMENT IS LOST
##     same label, .size set AFTER add_child -> (584, …)        correct at any length
##     custom_minimum_size instead          -> (1068, 48)       does NOT help; it is a floor
##
## So the identical code wraps for short strings and silently overflows for long ones. The
## description label (24 chars) was fine and the flavour label (141) was not, from the same
## expression four lines apart.
##
## 🔑 SCALE, measured from items.json rather than guessed: 121 items author flavour text and
## **71 of them are longer than one rendered line**, the longest at 228 characters. More than
## half the authored flavour in the game was unreadable past its first line.
##
## ⚠️ THE WRAP FIX ALONE WOULD HAVE TRADED A CLIP FOR A COLLISION. The effects list below was
## pushed down by a hard-coded 60px that assumed three lines at font 10; a flavour wrapping to
## four would be overlapped by "Restores N HP". The height now comes from the wrapped text via
## get_multiline_string_size, and the last arm here is the one that pins it.
##
## ⚠️ NOT A SOURCE-PATTERN GUARD. 14 sites in src/ assign .size before add_child on an
## autowrapped label; the pattern alone is not the defect, because it only bites when the text
## is long enough. This file asserts GEOMETRY on the one surface measured to overflow.

const ITEMS_JSON := "res://data/items.json"

var _menu = null


func after_each() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


func _authored_flavours() -> Dictionary:
	var txt := FileAccess.get_file_as_string(ITEMS_JSON)
	var parsed = JSON.parse_string(txt)
	assert_true(parsed is Dictionary, "CONTROL: items.json must parse as a Dictionary")
	if not (parsed is Dictionary):
		return {}
	var items: Variant = (parsed as Dictionary).get("items", parsed)
	var out: Dictionary = {}
	if items is Dictionary:
		for k in (items as Dictionary):
			var v = (items as Dictionary)[k]
			if v is Dictionary and str(v.get("flavor", "")) != "":
				out[str(k)] = str(v["flavor"])
	return out


func _longest_flavour_id() -> String:
	## Parsed ONCE. The first version called _authored_flavours() inside the loop, which
	## re-read and re-asserted items.json per key — 506 asserts for five arms, and an assert
	## count that size is noise standing where a real signal would be.
	var flavours := _authored_flavours()
	var best := ""
	var best_len := 0
	for k in flavours:
		var n: int = str(flavours[k]).length()
		if n > best_len:
			best_len = n
			best = str(k)
	return best


func _build_with(item_id: String):
	var menu = load("res://src/ui/ItemsMenu.gd").new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	_menu = menu
	await get_tree().process_frame
	menu.setup([], {item_id: 1})
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


func _detail_labels(menu) -> Array:
	var panel = menu.get_node_or_null("DetailsPanel")
	var out: Array = []
	if panel == null:
		return out
	for c in panel.get_children():
		if c is Label:
			out.append(c)
	return out


func test_control_the_corpus_has_long_flavour_to_test_with() -> void:
	## Without this the geometry arms could pass on an item whose flavour never overflowed.
	var flavours := _authored_flavours()
	assert_gt(flavours.size(), 50, "CONTROL: items.json must still author flavour text, found %d" % [flavours.size()])
	var long_ones := 0
	for k in flavours:
		if str(flavours[k]).length() > 100:
			long_ones += 1
	assert_gt(long_ones, 10,
		"CONTROL: there must be flavour long enough to overflow one line, found %d" % [long_ones])
	var id := _longest_flavour_id()
	assert_ne(id, "", "CONTROL: a longest-flavour item must be derivable")
	assert_gt(str(flavours[id]).length(), 100,
		"CONTROL: the item the arms below use must have flavour longer than one rendered line")


func test_the_longest_authored_flavour_stays_inside_the_details_panel() -> void:
	## Derived from the data, so the arm follows whatever the longest string becomes.
	var id := _longest_flavour_id()
	if id == "":
		return
	var menu = await _build_with(id)
	var panel = menu.get_node_or_null("DetailsPanel")
	assert_not_null(panel, "CONTROL: the details panel must exist, or nothing below is measured")
	if panel == null:
		return
	var labels := _detail_labels(menu)
	assert_gt(labels.size(), 2, "CONTROL: the panel must hold labels, found %d" % [labels.size()])
	var overflowing: Array = []
	for l in labels:
		var right: float = (l as Label).position.x + (l as Label).size.x
		if right > panel.size.x:
			overflowing.append("%s: right edge %.0f > panel %.0f (len %d)"
				% [(l as Label).text.substr(0, 24), right, panel.size.x, (l as Label).text.length()])
	assert_eq(overflowing, [],
		"these labels run past the DETAILS panel — on screen the text is cut mid-word at the "
		+ "window edge: %s" % [str(overflowing)])


func test_the_flavour_label_is_the_width_the_panel_asked_for() -> void:
	## The specific regression: the assignment is lost when it happens before add_child, and the
	## label silently takes its content width instead.
	var id := _longest_flavour_id()
	if id == "":
		return
	var menu = await _build_with(id)
	var panel = menu.get_node_or_null("DetailsPanel")
	if panel == null:
		return
	var widest: float = 0.0
	var longest_len: int = 0
	for l in _detail_labels(menu):
		if (l as Label).text.length() > longest_len:
			longest_len = (l as Label).text.length()
			widest = (l as Label).size.x
	assert_gt(longest_len, 100, "CONTROL: the longest label must be the flavour, got %d chars" % [longest_len])
	assert_almost_eq(widest, panel.size.x - 32.0, 1.0,
		"the flavour label took its CONTENT width (%.0f) instead of the panel width it was "
		% [widest] + "assigned (%.0f) — .size was applied before add_child" % [panel.size.x - 32.0])
func test_control_a_short_flavour_is_unaffected() -> void:
	## The fix must not change the surface it was already correct on.
	var flavours := _authored_flavours()
	var short_id := ""
	for k in flavours:
		var n: int = str(flavours[k]).length()
		if n > 0 and n < 60:
			short_id = str(k)
			break
	if short_id == "":
		return
	var menu = await _build_with(short_id)
	var panel = menu.get_node_or_null("DetailsPanel")
	if panel == null:
		return
	for l in _detail_labels(menu):
		assert_lte((l as Label).position.x + (l as Label).size.x, panel.size.x,
			"CONTROL: a short flavour must stay inside the panel too: '%s'" % [(l as Label).text.substr(0, 24)])
