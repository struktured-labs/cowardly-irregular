extends GutTest

## struktured 2026-11-07: "make sure nothing ever overlaps unless we intend it". The FIELD half (main 23393/23398): every
## exploration HUD surface, built for real on the player's 1280x720 with its longest real content, judged at every Text
## Size by the shared OverlapAudit (test/unit/helpers/overlap_audit.gd). An overlap passes only when DECLARED below with a reason.

const SCREEN := Vector2i(1280, 720)
const TrackerScript := preload("res://src/exploration/QuestTracker.gd")
const ZoneScript := preload("res://src/exploration/ZoneNamePopup.gd")
const ArrowScript := preload("res://src/exploration/ObjectiveArrow.gd")
const BorderScript := preload("res://src/exploration/MapBorderIndicator.gd")
const MinimapScript := preload("res://src/exploration/OverworldMinimap.gd")
const ThreatScript := preload("res://src/exploration/ThreatMeter.gd")
const ChipScript := preload("res://src/ui/PartyChatIndicator.gd")
const Overlap = preload("res://test/unit/helpers/overlap_audit.gd")
const HINT_ID := "field_overlap_guard_probe"

## Intentional overlaps: "id|id": reason. Filled from the first measured census, never from a guess.
const DECLARED := {}

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved
	GameState.game_constants.erase("tutorial_" + HINT_ID)


## The whole field HUD on a 1280x720 SubViewport, with the widest content each surface can really show.
func _field() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = SCREEN
	add_child_autofree(vp)
	var host := Node2D.new()
	vp.add_child(host)
	var player := Node2D.new()
	host.add_child(player)
	var tracker: Node = TrackerScript.new()
	host.add_child(tracker)
	tracker.setup(host)
	var longest := ""
	for e in TrackerScript.OBJECTIVES:
		if str(e["text"]).length() > longest.length():
			longest = str(e["text"])
	tracker._label.text = "> " + longest
	tracker._side_label.visible = true
	tracker._side_label.text = longest
	tracker._apply_plate()
	var zone: Node = ZoneScript.new()
	host.add_child(zone)
	zone.setup(host)
	zone.show_zone("industrial_overworld")
	var mm: Node = MinimapScript.new()
	host.add_child(mm)
	mm.setup(host, player, 100, 70, 32, {})
	var threat: Node = ThreatScript.new()
	host.add_child(threat)
	var spawner := Node.new()
	host.add_child(spawner)
	threat.setup(host, player, spawner)
	var border: Node = BorderScript.new()
	host.add_child(border)
	border.setup(host, player, 100, 70, 32)
	var arrow: Node = ArrowScript.new()
	host.add_child(arrow)
	arrow.setup(host, player)
	arrow.set_target(Vector2(5000, 0))
	arrow.update(Vector2.ZERO)
	var clock := DayClockWidget.new()
	vp.add_child(clock)
	var chip: Control = ChipScript.new()
	var chip_layer := CanvasLayer.new()
	chip_layer.layer = 45
	vp.add_child(chip_layer)
	chip_layer.add_child(chip)
	# The two transient field surfaces: a tutorial hint (the longest authored body) and a full toast stack.
	GameState.game_constants.erase("tutorial_" + HINT_ID)
	var hint := TutorialHint.new()
	vp.add_child(hint)
	var body := ""
	for id in TutorialHints.HINTS:
		var b := str((TutorialHints.HINTS[id] as Dictionary).get("body", ""))
		if b.length() > body.length():
			body = b
	hint.show_hint(HINT_ID, "Movement", body)
	for i in Toast.MAX_STACK:
		Toast.show(host, "Saved at the Whispering Cave entrance (%d)" % i)
	return vp


func test_nothing_on_the_field_overlaps_unless_declared() -> void:
	var used := {}
	for p in SettingsMenu.TEXT_SIZE_PRESETS:
		GameState.text_size_scale = float(p)
		var vp := _field()
		await get_tree().process_frame
		var surfaces: Array = Overlap.surfaces(vp)
		assert_gt(surfaces.size(), 10, "CONTROL: the field HUD was built (%d surfaces at %s)" % [surfaces.size(), str(p)])
		for s in surfaces:
			gut.p("[FIELD %s] %s %s" % [str(p), s["id"], str(s["rect"])])
		var hits: Array = Overlap.collisions(surfaces, DECLARED, used)
		for h in hits:
			gut.p("[OVERLAP %s] %s" % [str(p), str(h)])
		assert_eq(hits.size(), 0, "field HUD overlaps at Text Size %s: %d (each printed as [OVERLAP])" % [str(p), hits.size()])
	assert_eq(Overlap.stale(DECLARED, used), [], "a declared overlap matched nothing at any Text Size, or has no reason")


## CONTROL: the judge sees a planted overlap on this same field, so an empty list above is a finding and not blindness.
func test_a_planted_panel_over_the_minimap_is_named() -> void:
	GameState.text_size_scale = 1.0
	var vp := _field()
	await get_tree().process_frame
	var before: int = Overlap.collisions(Overlap.surfaces(vp), DECLARED).size()
	var plant := Panel.new()
	plant.name = "PlantedPanel"
	plant.position = Vector2(SCREEN.x - 160, 20)
	plant.size = Vector2(120, 80)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	layer.add_child(plant)
	await get_tree().process_frame
	var after: Array = Overlap.collisions(Overlap.surfaces(vp), DECLARED)
	assert_gt(after.size(), before, "a panel planted on the minimap's corner must add a collision")
	assert_true(str(after).contains("PlantedPanel"), "and the collision names the planted panel: %s" % str(after))

