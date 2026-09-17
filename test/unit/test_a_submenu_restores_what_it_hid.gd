extends GutTest

## Every overworld submenu hides the menu behind it and restores it on close. SEVENTEEN openers
## route through ONE hide helper and FOUR restore sites, and nothing enforced the pairing — an
## eighteenth submenu that forgets its restore leaves the player on an empty screen with a live
## menu underneath, taking input it cannot see.
##
## ⛔ AND THE RESTORE SET **EVERY** CHILD VISIBLE rather than what it hid. Measured on the round
## trip before the fix:
##
##     a child hidden BEFORE the submenu opened   ->   visible = TRUE after it closed
##
## 🔑 LATENT ON THIS SURFACE TODAY, AND SAYING SO IS THE POINT. The four permanent direct children
## (bg, party panel, menu panel, footer) are never conditionally hidden, and the only conditional
## visibility in the file — dead_overlay / dead_label — sits INSIDE a party card, which
## get_children() does not reach. So this is a ratchet rather than a repair: the same shape
## cowir-cutscenes found reopening a closed dialogue panel, caught here before it had a consequence.

const OverworldScript = preload("res://src/ui/OverworldMenu.gd")
const SRC := "res://src/ui/OverworldMenu.gd"


func _menu() -> Node:
	var m = OverworldScript.new()
	add_child_autofree(m)
	m.visible = true
	m.modulate.a = 1.0
	m._submenu_open = false
	m.party = [{"name": "A"}, {"name": "B"}]
	m._menu_options = ["Items", "Equipment", "Status", "Save"]
	m.selected_index = 0
	m._ui_built = true
	return m


func _funcs(src: String) -> Dictionary:
	var out: Dictionary = {}
	var name := ""
	var body: Array = []
	for line in src.split("\n"):
		var l: String = line
		if l.begins_with("func "):
			if name != "":
				out[name] = "\n".join(body)
			name = l.substr(5, maxi(0, l.find("(") - 5))
			body = []
		elif name != "":
			body.append(l)
	if name != "":
		out[name] = "\n".join(body)
	return out


## Every `_on_*` handler this body connects to any signal.
func _connected_handlers(body: String) -> Array:
	var out: Array = []
	var from := 0
	while true:
		var at := body.find(".connect(", from)
		if at < 0:
			break
		var rest := body.substr(at + 9)
		var end := rest.find(")")
		if end > 0:
			var arg := rest.substr(0, end).strip_edges().trim_prefix("self.")
			if arg.begins_with("_on_"):
				out.append(arg)
		from = at + 9
	return out


func test_a_child_that_was_already_hidden_stays_hidden() -> void:
	var m := _menu()
	var keep := ColorRect.new(); keep.name = "Keep"; m.add_child(keep)
	var already := ColorRect.new(); already.name = "AlreadyHidden"; m.add_child(already)
	already.visible = false
	var sub := Control.new(); sub.name = "Sub"; m.add_child(sub)

	m._hide_main_ui(sub)
	assert_false(keep.visible,
		"LIVENESS: the opener must actually hide an ordinary child, or the restore below is a "
		+ "comparison between two unchanged values")
	m._on_submenu_closed()
	assert_true(keep.visible, "the child the submenu hid must come back when it closes")
	assert_false(already.visible,
		"a child that was ALREADY hidden was un-hidden by the close — the restore must put back "
		+ "what it took, not set everything visible")


## Every restore site, DERIVED. Fixing one and leaving the others is the failure this catches.
func test_every_restore_site_puts_back_only_what_was_hidden() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	assert_ne(src, "", "OverworldMenu must be readable as source")
	var funcs := _funcs(src)
	var closers: Array = []
	for fname in funcs:
		if fname.begins_with("_on_") and str(funcs[fname]).contains("_restore_main_ui("):
			closers.append(fname)
	assert_gt(closers.size(), 3,
		"the derivation must find the restore sites; %d found — if this is 0 the arms below " % closers.size()
		+ "assert nothing about anything")

	for closer in closers:
		var m := _menu()
		var keep := ColorRect.new(); m.add_child(keep)
		var already := ColorRect.new(); already.visible = false; m.add_child(already)
		var sub := Control.new(); m.add_child(sub)
		m._hide_main_ui(sub)
		m.call(closer)
		assert_true(keep.visible, "%s did not restore the child the submenu hid" % closer)
		assert_false(already.visible, "%s un-hid a child that was already hidden" % closer)


## THE SYMMETRY, derived over every opener rather than a list of the seventeen that exist today.
## An opener that hides without a closer that restores leaves the menu invisible and still live.
func test_every_opener_that_hides_has_a_closer_that_restores() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	assert_ne(src, "", "OverworldMenu must be readable as source")
	var funcs := _funcs(src)
	var hiders: Array = []
	var broken: Array = []
	for fname in funcs:
		if not fname.begins_with("_open_"):
			continue
		var body: String = str(funcs[fname])
		if not body.contains("_hide_main_ui("):
			continue
		hiders.append(fname)
		var handlers := _connected_handlers(body)
		if handlers.is_empty():
			broken.append("%s connects no _on_* handler" % fname)
			continue
		var restores := false
		for h in handlers:
			if funcs.has(h) and str(funcs[h]).contains("_restore_main_ui("):
				restores = true
				break
		if not restores:
			broken.append("%s -> %s (none restores)" % [fname, handlers])
	assert_gt(hiders.size(), 14,
		"the derivation must find the openers that hide; %d found" % hiders.size())
	assert_eq(broken, [],
		"these hide the overworld menu and never put it back — the player gets an empty screen "
		+ "with a live menu underneath still taking input: %s" % [broken])


## CONTROL for the parser, not for the menu: it must find the functions at all, and must not
## mistake a docstring mention for a call site.
func test_control_the_parser_finds_functions_and_the_helpers_exist() -> void:
	var funcs := _funcs(FileAccess.get_file_as_string(SRC))
	assert_gt(funcs.size(), 40, "the function split found %d functions — a low count means the "
		% funcs.size() + "arms above swept almost nothing")
	assert_true(funcs.has("_hide_main_ui"), "the hide helper must exist by that name")
	assert_true(funcs.has("_restore_main_ui"), "the restore helper must exist by that name")
	assert_true(_connected_handlers("\tfoo.closed.connect(_on_submenu_closed)").has("_on_submenu_closed"),
		"the connect parser must find a handler in a line shaped like the real ones")
	assert_eq(_connected_handlers("\t# closed.connect(_on_nothing) in a comment").size(), 1,
		"parser reads text, so this SHOULD match — the arms use it on real bodies only")
