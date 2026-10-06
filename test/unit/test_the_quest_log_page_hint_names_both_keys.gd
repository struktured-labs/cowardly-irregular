extends GutTest

## The Quest Log glued its two page keys together, so pads read "LBRB: Page", "L1R1: Page" or "LR: Page", and keyboards "QW: Page".

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const QUEST_LOG := preload("res://src/ui/QuestLog.gd")
const DEVICES := ["", "Xbox Wireless Controller", "DualSense Wireless Controller", "Nintendo Switch Pro Controller"]


func test_every_family_reads_both_keys_apart() -> void:
	var glued: Array = []
	for dev in DEVICES:
		var defer: String = InputProfileManager.hint_for_action("battle_defer", dev)
		var adv: String = InputProfileManager.hint_for_action("battle_advance", dev)
		assert_ne(defer, "", "CONTROL: %s names the defer shoulder" % [dev if dev != "" else "keyboard"])
		var hint: String = QUEST_LOG.page_hint(dev)
		if not hint.begins_with("%s/%s" % [defer, adv]):
			glued.append("%s: %s" % [dev if dev != "" else "keyboard", hint])
	assert_eq(glued, [], "the page legend must separate the two keys: %s" % [glued])


func test_the_live_footer_shows_that_legend() -> void:
	var log = QUEST_LOG.new()
	add_child_autofree(log)
	if log.has_method("setup"):
		log.setup()
	await get_tree().process_frame
	var found := ""
	var stack: Array = [log]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label and (n as Label).text.contains("Page"):
			found = (n as Label).text
	assert_ne(found, "", "CONTROL: the Quest Log draws a footer naming Page")
	assert_true(found.contains(QUEST_LOG.page_hint()), "the footer must use the separated legend, got: %s" % found)


func test_no_ui_string_glues_two_hints_together() -> void:
	var glued: Array = []
	var d := DirAccess.open("res://src/ui")
	for f in d.get_files():
		if f.ends_with(".gd") and GdSource.code_of("res://src/ui/" + f).contains("%s%s:"):
			glued.append(f)
	assert_true(GdSource.code_of("res://src/ui/QuestLog.gd").contains("func page_hint"), "CONTROL: UI code survives comment-stripping")
	assert_eq(glued, [], "two hints formatted back to back read as one key on a pad: %s" % [glued])
