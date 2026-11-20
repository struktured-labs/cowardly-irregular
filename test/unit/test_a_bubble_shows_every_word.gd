extends GutTest

## struktured 2026-11-19, playing .808: "the speech bubbles cut off text". Every word of a spoken line is inside its bubble
## and the bubble is on screen, judged on the BUILT bubble after layout; the older guards judged the shaper's row count.

const BubbleScript := preload("res://src/battle/BattleSpeechBubble.gd")
const SETTINGS := "res://src/ui/SettingsMenu.gd"
## Where speakers stand: a party slot, the top party slot (ceiling-pinned), an enemy.
const ANCHORS := [Vector2(980, 300), Vector2(980, 90), Vector2(300, 320)]
const SLACK := 0.5

var _saved_time: float = 1.0
var _saved_scale = null


func before_each() -> void:
	_saved_time = Engine.time_scale
	Engine.time_scale = BubbleScript.SUPPRESS_TIME_SCALE * 0.5
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	Engine.time_scale = _saved_time
	GameState.text_size_scale = _saved_scale
	for e in BubbleScript._live:
		if is_instance_valid(e["bubble"]):
			e["bubble"].queue_free()
	BubbleScript._live.clear()


func _presets() -> Array:
	var p: Array = (load(SETTINGS) as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS resolves")
	return p


## How many of the longest scripted lines are judged; all of them took 378 s (10,965 bubbles, 0 faults, 2026-11-20).
const LONGEST := 6


## The longest scripted party lines and the shortest, plus one at the LLM cap.
func _lines() -> Array:
	var all := _scripted()
	all.sort_custom(func(x, y): return x.length() > y.length())
	var out: Array = all.slice(0, LONGEST)
	if all.size() > LONGEST:
		out.append(all[-1])
	var cap := ""
	while cap.length() < DialoguePrompts.MAX_PARTY_LINE_CHARS - 12:
		cap += "calibrating "
	out.append(cap.strip_edges())
	return out


func _scripted() -> Array:
	var out: Array = []
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/job_personas.json"))
	if d is Dictionary and d.has("jobs"):
		for job in (d["jobs"] as Dictionary):
			var tv = d["jobs"][job].get("trigger_voices", {})
			if tv is Dictionary:
				for trig in tv:
					for ln in (tv[trig] if tv[trig] is Array else [tv[trig]]):
						out.append(str(VoiceLines.text_of(ln)))
	return out


## A built, laid-out bubble's faults as text; empty when every word shows.
func _faults(line: String, anchor: Vector2, host: Node) -> Array:
	var out: Array = []
	var bubble = BubbleScript.spawn(host, anchor, "Cleric", line, Color.WHITE, 30.0, "", anchor.x < 640.0)
	if bubble == null:
		return ["no bubble spawned"]
	for f in 4:
		await get_tree().process_frame
	var panel: PanelContainer = bubble.find_children("*", "PanelContainer", true, false)[0]
	var pr: Rect2 = panel.get_global_rect()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	for label in bubble.find_children("*", "Label", true, false):
		var l := label as Label
		var lr: Rect2 = l.get_global_rect()
		if l.get_visible_line_count() < l.get_line_count():
			out.append("%d of %d rows show" % [l.get_visible_line_count(), l.get_line_count()])
		var need: float = float(l.get_line_count()) * float(l.get_line_height())
		if lr.size.y < need - SLACK:
			out.append("label %.0f px tall for %d rows needing %.0f" % [lr.size.y, l.get_line_count(), need])
		if not pr.grow(SLACK).encloses(lr):
			out.append("label %s leaves its panel %s" % [str(lr), str(pr)])
		var widest := 0.0
		var font: Font = l.get_theme_font("font")
		var px: int = l.get_theme_font_size("font_size")
		var tp := TextParagraph.new()
		tp.width = lr.size.x
		tp.add_string(l.text, font, px)
		for i in tp.get_line_count():
			widest = maxf(widest, tp.get_line_width(i))
		if widest > lr.size.x + SLACK:
			out.append("a row is %.0f px wide in a %.0f px label" % [widest, lr.size.x])
		if tp.get_line_count() != l.get_line_count():
			out.append("the label wraps to %d rows, the shaper to %d" % [l.get_line_count(), tp.get_line_count()])
	if pr.position.x < 0.0 or pr.position.y < 0.0 or pr.end.x > vp.x + SLACK or pr.end.y > vp.y + SLACK:
		out.append("panel %s leaves the %s screen" % [str(pr), str(vp)])
	bubble.queue_free()
	BubbleScript._live.clear()
	await get_tree().process_frame
	return out


func test_the_floor_names_what_this_file_drives() -> void:
	assert_true(autofree(BubbleScript.new()).has_method("_present"), "FLOOR: BattleSpeechBubble._present")
	assert_gt(_scripted().size(), 20, "FLOOR: the scripted party lines load")
	assert_eq(_lines().size(), LONGEST + 2, "FLOOR: the judged lines are the longest, the shortest and one at the cap")


func test_every_word_of_every_line_shows_at_every_text_size() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var bad: Array = []
	var judged := 0
	for s in _presets():
		GameState.text_size_scale = float(s)
		for line in _lines():
			for a in ANCHORS:
				judged += 1
				for f in await _faults(line, a, host):
					bad.append("@%s %s \"%s\": %s" % [s, str(a), line.left(28), f])
	assert_gt(judged, 0, "CONTROL: bubbles were judged")
	gut.p("    judged %d bubbles, %d faults" % [judged, bad.size()])
	assert_eq(bad.slice(0, 40), [], "a bubble shows every word (%d faults):\n%s" % [bad.size(), "\n".join(PackedStringArray(bad.slice(0, 40)))])
