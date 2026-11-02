extends GutTest

## struktured, preview: stop rule "any member dead", and "at the end two yellow texts appeared on top of each other when it
## completed and I couldn't read them — they overlaid almost perfectly aligned". This drives the real end of a grind and walks
## every visible text node GameLoop put up, so any two that land on each other are named by their text.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GL_SRC := "res://src/GameLoop.gd"

var _ag: Dictionary
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_gl = load(GL_SRC).new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	var members: Array[Combatant] = []
	for n in ["Fighter", "Bard"]:
		var c := Combatant.new()
		c.combatant_name = n
		c.max_hp = 50
		c.current_hp = 50 if n == "Fighter" else 0
		c.is_alive = n == "Fighter"
		_gl.add_child(c)
		members.append(c)
	_gl.party = members


func after_each() -> void:
	InputLockManager.pop_all()
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)
	SoundManager.stop_music()


## Every visible, non-empty text node under GameLoop, with its on-screen rect.
func _texts(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var t := ""
		if c is Label:
			t = (c as Label).text
		elif c is RichTextLabel:
			t = (c as RichTextLabel).get_parsed_text()
		if t.strip_edges() == "":
			continue
		var layer: int = 0
		var p: Node = c.get_parent()
		while p != null:
			if p is CanvasLayer:
				layer = (p as CanvasLayer).layer
				break
			p = p.get_parent()
		out.append({"text": t.strip_edges().left(48), "rect": c.get_global_rect(), "node": c, "layer": layer})
	return out


func test_a_rule_stop_puts_up_no_two_texts_on_top_of_each_other() -> void:
	_gl._on_grind_complete("Your rule #1 stopped the grind")
	await wait_frames(3)
	var texts := _texts(_gl)
	assert_gt(texts.size(), 1, "CONTROL: the end of a grind puts text on screen")
	var stacked: Array = []
	for i in texts.size():
		for j in range(i + 1, texts.size()):
			var a: Rect2 = texts[i]["rect"]
			var b: Rect2 = texts[j]["rect"]
			if a.get_area() <= 0.0 or b.get_area() <= 0.0 or not a.intersects(b):
				continue
			if (texts[i]["node"] as Node).is_ancestor_of(texts[j]["node"]) or (texts[j]["node"] as Node).is_ancestor_of(texts[i]["node"]):
				continue
			## Laid-out siblings can touch at an edge; a pile-up covers most of the smaller one, on any layer.
			var overlap: float = a.intersection(b).get_area() / minf(a.get_area(), b.get_area())
			if overlap > 0.5:
				stacked.append("'%s' (layer %d) over '%s' (layer %d), %d%% covered"
					% [texts[i]["text"], texts[i]["layer"], texts[j]["text"], texts[j]["layer"], roundi(overlap * 100)])
	assert_eq(stacked, [], "two texts drawn on top of each other at the end of a grind:\n  %s" % "\n  ".join(stacked))
