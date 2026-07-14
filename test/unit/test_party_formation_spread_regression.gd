extends GutTest

## Smoke-shot finds 2026-07-11 (duel_smoke.png / game_over.png):
## 1. All 5 party sprites stacked in a near-single column — 50px zigzag
##    under 210px-tall sprites = heavy occlusion, and Player1's head
##    clipped above y=0. Markers now form a real diagonal: >=40px x-step
##    and >=105px y-step between neighbors, top slot low enough to fit.
## 2. "New party chat" toast fired over the GAME OVER screen.

const TSCN := "res://src/battle/BattleScene.tscn"


func _marker_positions() -> Array:
	var src := FileAccess.get_file_as_string(TSCN)
	var out: Array = []
	for i in range(1, 6):
		var node_i := src.find("Player%dPos" % i)
		assert_gt(node_i, -1, "Player%dPos must exist" % i)
		var pos_i := src.find("position = Vector2(", node_i)
		var close := src.find(")", pos_i)
		var parts := src.substr(pos_i + 19, close - pos_i - 19).split(",")
		out.append(Vector2(float(parts[0]), float(parts[1])))
	return out


func test_party_markers_form_a_diagonal() -> void:
	var pts := _marker_positions()
	for i in range(1, pts.size()):
		assert_gte(absf(pts[i].x - pts[i - 1].x), 40.0,
			"slots %d/%d need >=40px horizontal separation — 50px zigzag read as one stacked column" % [i - 1, i])
		assert_gte(pts[i].y - pts[i - 1].y, 105.0,
			"slots must descend >=105px so sprites read as a formation")
	assert_gte(pts[0].y, 55.0,
		"top slot must sit low enough that a 210px sprite's head doesn't clip above the screen")


func test_party_chat_toast_is_exploration_only() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("New party chat: %s")
	assert_gt(i, -1)
	var window := src.substr(maxi(0, i - 700), 700)
	assert_true("current_state != LoopState.EXPLORATION" in window and "_pending_chat_toasts" in window,
		"unlock toasts must defer to a clean exploration moment (they fired over GAME OVER, then the shop)")
