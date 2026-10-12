extends GutTest

## ⛔ THE BANNER RENDERED 16px RIGHT OF CENTRE, EVERY TIME, AND NOTHING COULD HAVE NOTICED.
## `_show_address_banner` anchors PRESET_CENTER_TOP, then sets `size = Vector2(300, 0)` with the
## comment "auto-resize via child". The resize is real and the default grow direction is END, so the
## panel grows RIGHTWARD out of its own centring. Measured on the live node:
##
##     pos.x 490.0   size.x 332.0   centre 656.0   viewport half 640.0   drift +16.0
##     with grow_horizontal = BOTH:  pos.x 474.0   size.x 332.0   centre 640.0   drift  +0.0
##
## 🔑 It is DETERMINISTIC, not occasional: both call sites pass the same fixed literal
## ("⚠ DIRECTIVE OVERRIDE ACCEPTED"), 332px of text in a 300px box. So this was not a rare overflow
## — the banner has never once been centred.
##
## 📌 FOUND AS A SIBLING, AND ONLY BECAUSE THE FIRST ONE WAS WRITTEN DOWN. The hint bar had this
## exact defect (fallback bar, 63.5px right) and the speed panel at BattleScene:666 already carried
## `GROW_DIRECTION_BEGIN` with the comment "wider labels (16x-64x) grow left" — the same class,
## solved once, never generalised. I published this banner as an UNVERIFIED lead rather than
## editing it blind, then measured it. The measurement is what turned a smell into a defect.
##
## ⚠️ DELIBERATELY NOT A DERIVED RULE OVER EVERY CENTRE-ANCHORED PANEL. The honest version of that
## guard requires the hint bar's fix too, which is on a different branch — a guard that goes green
## only once a SECOND branch lands is a fold hazard, not coverage. Consolidate after both land.

## ⛔ INSTANTIATING BattleScene.tscn STARTS A BATTLE, AND A RUNNING BATTLE IN AN AUTOLOAD OUTLIVES
## THIS FILE. cowir-main's pre-fold sweep caught exactly that in my hint-bar file hours ago
## (test_battle_state_not_leaked_by_tests, state=3). I ran this file PAIRED with that guard from the
## first run rather than alone, which is the only arrangement that can see the leak at all.
const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")

var _scene: Node = null
var _bm: RefCounted = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	if _bm != null:
		_bm.restore()
	_bm = null


## The banner is a transient child: find it by the z_index its builder sets, not by name (it has none).
func _banner_of(scene: Node) -> PanelContainer:
	for child in scene.get_children():
		if child is PanelContainer and (child as PanelContainer).z_index == 200:
			return child as PanelContainer
	return null


func test_the_address_banner_is_centred_on_the_viewport() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child_autofree(_scene)
	await get_tree().process_frame
	assert_true(_scene.has_method("_show_address_banner"),
		"PRECONDITION: BattleScene must still build the banner here")
	_scene._show_address_banner("⚠ DIRECTIVE OVERRIDE ACCEPTED")
	await get_tree().process_frame
	await get_tree().process_frame

	var banner := _banner_of(_scene)
	assert_not_null(banner, "PRECONDITION: the banner must be in the tree, or this arm proves nothing")
	if banner == null:
		return

	## POSITIVE CONTROL: the whole defect needs the panel to OUTGROW the 300px its builder sets.
	## Without this, a centred reading could be about a panel that never grew and never could drift.
	assert_gt(banner.size.x, 300.0,
		"CONTROL: the banner must have grown past its declared 300px (got %.1f) — if it fits, there is no drift to catch here" % banner.size.x)

	var centre: float = banner.position.x + banner.size.x / 2.0
	var want: float = banner.get_parent_area_size().x / 2.0
	assert_almost_eq(centre, want, 2.0,
		"the banner must sit on the viewport centre — PRESET_CENTER_TOP centres the BOX, and a panel "
		+ "that outgrows its box grows END-ward unless grow_horizontal says otherwise")
