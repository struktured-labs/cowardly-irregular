extends GutTest

## On every victory the VICTORY title rested ON the second and third EXP cards for ~0.45s before docking.
## The overlay's own order is slam -> cards -> strip, but cards fade in from 0.5s while the title holds mid-screen
## until ~0.9s. Seen in a watched real battle (GameLoop party vs goblin+slime): "V I C [Cleric card] R Y".
## A card whose spot overlaps the resting title now waits for the dock; every other card keeps its timing,
## so the slam beat is unchanged.
## The scene here places the party sprites where that battle had them (scaled to this viewport); the arm samples
## every frame and judges what is DRAWN: a visible card against the title's scaled, pivoted rect.

const OverlayScript := preload("res://src/battle/VictoryOverlay.gd")
const MEASURED_VP := Vector2(1280, 720)
## Sprite anchors that put the five cards where the watched battle drew them (card = sprite - (410, 29)).
const SPRITES := [Vector2(974, 178), Vector2(929, 259), Vector2(884, 360), Vector2(839, 461), Vector2(794, 562)]


class FakeScene:
	extends Node2D
	var party_sprite_nodes: Array = []


func _results(n: int) -> Dictionary:
	var crs: Array = []
	for i in n:
		crs.append({"name": "PC%d" % i, "job_name": "Fighter", "is_alive": true, "exp_gained": 100, "leveled_up": false,
			"job_level": 1, "job_exp": 50, "job_exp_before": 0, "exp_to_next": 100})
	return {"char_results": crs, "gold": 30, "items": []}


func _drawn_rect(c: CanvasItem) -> Rect2:
	var ctl := c as Control
	return ctl.get_global_transform() * Rect2(Vector2.ZERO, ctl.size)


func test_no_card_is_drawn_under_the_resting_title() -> void:
	var scene := FakeScene.new()
	add_child_autofree(scene)
	var vp := get_viewport().get_visible_rect().size
	var k := Vector2(vp.x / MEASURED_VP.x, vp.y / MEASURED_VP.y)
	for p in SPRITES:
		var s := Node2D.new()
		s.position = p * k
		scene.add_child(s)
		scene.party_sprite_nodes.append(s)
	var overlay: Control = OverlayScript.new()
	add_child_autofree(overlay)
	overlay.build(_results(SPRITES.size()), scene)
	var title: Label = null
	var cards: Array = []
	for c in overlay.get_children():
		if c is Label and (c as Label).text.replace(" ", "") == "VICTORY":
			title = c
		elif c is Control and absf((c as Control).custom_minimum_size.x - OverlayScript.CARD_W) < 0.5:
			cards.append(c)
	assert_not_null(title, "CONTROL: the overlay slammed its title")
	assert_eq(cards.size(), SPRITES.size(), "CONTROL: one card per party member")
	if title == null:
		return
	var overlaps: Dictionary = {}
	var shown_any := false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1600:
		await get_tree().process_frame
		if title.modulate.a < 0.05:
			continue
		var tr := _drawn_rect(title)
		for i in cards.size():
			var card: Control = cards[i]
			if card.modulate.a < 0.05:
				continue
			shown_any = true
			if _drawn_rect(card).intersects(tr):
				overlaps[i] = true
	assert_true(shown_any, "CONTROL: cards appeared while the title was up")
	assert_eq(overlaps.keys(), [], "cards drawn under the VICTORY title: %s" % str(overlaps.keys()))
