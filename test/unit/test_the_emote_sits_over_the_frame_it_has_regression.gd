extends GutTest

## MY OWN INCONSISTENCY, introduced by the branch under this one. `62dc0776` made `_load_sheet`
## MEASURE the frame it cuts (159 of 159 overworld sheets are 32px, so the old hardcode held) — and
## left `show_emote` and `say` computing their height from the CONSTANT. So a 48px sheet would be
## sliced correctly and then have its emote glyph 8px inside the figure's head, and its aside bubble
## overlapping the same head, because half of 32 is not half of 48.
##
## 🔑 One half derived and one half guessing is worse than both guessing: the sizes now disagree only
## for the sheets the fix was FOR. Everything positioned off "the frame" reads the frame this actor
## was actually cut at.

const ActorScript = preload("res://src/cutscene/CutsceneActor.gd")


## ⛔ `_load_sheet` takes a PATH and gates on `ResourceLoader.exists`, so a runtime-written
## `user://` PNG cannot drive it — a saved fixture is not an imported resource and the loader
## correctly refuses it. So the two halves are driven separately, which is also the honest split:
## the SLICER storing what it measured is guarded on the branch below this one; here the question is
## whether the emote READS it.
func _actor_at(frame_px: int) -> Node:
	var a = ActorScript.new()
	add_child_autofree(a)
	a._frame_px = frame_px
	return a


## A real 32px sheet from the shipped corpus, for the one case the live path can be driven with.
const REAL_SHEET := "res://assets/sprites/npcs/blacksmith/overworld.png"


func _emote_y(a: Node) -> float:
	a.show_emote("exclaim", 0.0)
	assert_not_null(a._emote_label, "the emote label must exist")
	return a._emote_label.position.y


## The emote must clear a TALLER frame by more than it clears the conventional one.
func test_a_taller_sheet_pushes_the_emote_higher() -> void:
	var small := _actor_at(ActorScript.FRAME_SIZE)
	var large := _actor_at(48)
	var y_small: float = _emote_y(small)
	var y_large: float = _emote_y(large)
	assert_lt(y_large, y_small,
		"a 48px figure is taller, so its emote must sit HIGHER (got %.1f vs %.1f)" % [y_large, y_small])
	assert_almost_eq(y_small - y_large, 8.0, 0.01,
		"and higher by exactly half the extra frame — 8px for 32->48")


## CONTROL: the conventional sheet is unchanged, which is every authored actor today.
func test_the_conventional_sheet_is_where_it_always_was() -> void:
	var a := _actor_at(ActorScript.FRAME_SIZE)
	assert_almost_eq(_emote_y(a), -float(ActorScript.FRAME_SIZE) * 0.5 - 22.0, 0.01,
		"159 of 159 overworld sheets are 32px and none of them may move")


## The aside bubble reads the same frame, or it overlaps the head the emote just cleared.
func test_the_aside_bubble_reads_the_same_frame() -> void:
	var large := _actor_at(48)
	large.say("Testing.", 0.0)
	assert_not_null(large._bubble, "the aside bubble must exist")
	if large._bubble == null:
		return
	var bubble_bottom: float = large._bubble.position.y + large._bubble.size.y
	assert_lte(bubble_bottom, -float(48) * 0.5 - 8.0 + 0.01,
		"the bubble must sit above the 48px figure's head (bottom %.1f)" % bubble_bottom)


## A sprite with no sheet keeps the convention rather than inheriting a stale measurement.
func test_the_placeholder_resets_to_the_convention() -> void:
	var a := _actor_at(48)
	assert_eq(a._frame_px, 48, "PRECONDITION: set to 48 first")
	a._build_placeholder()
	assert_eq(a._frame_px, ActorScript.FRAME_SIZE,
		"the placeholder IS the convention, so it must say so — a stale 48 would float the emote")


## The positions must not read the CONSTANT any more; that is the drift this closes.
func test_nothing_positions_off_the_constant() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneActor.gd")
	for fn in ["func show_emote", "func say"]:
		var i := src.find(fn)
		assert_gt(i, -1, "%s must exist" % fn)
		var next: int = src.find("\nfunc ", i + 1)
		var body := src.substr(i, (next - i) if next > -1 else 1400)
		assert_false("float(FRAME_SIZE)" in body,
			"%s must read the frame this actor was cut at, not the convention" % fn)
		assert_true("_frame_px" in body, "%s must read the measured frame" % fn)


## THE LIVE PATH, on a shipped sheet: the slicer must store the frame it measured, or the emote reads
## a default that happens to be right. Only the 32px case is drivable — no 48px sheet ships — so the
## taller case is driven through `_frame_px` above and the LINK is pinned here and in source.
func test_the_live_slicer_stores_what_it_measured() -> void:
	var a = ActorScript.new()
	add_child_autofree(a)
	a._frame_px = 999  # a value the loader must overwrite
	assert_true(ResourceLoader.exists(REAL_SHEET), "PRECONDITION: the shipped fixture sheet must exist")
	assert_true(a._load_sheet(REAL_SHEET), "the shipped 128x128 sheet must load")
	assert_eq(a._frame_px, ActorScript.FRAME_SIZE,
		"the slicer must record the frame it cut at — 999 surviving means the emote reads a stale number")
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneActor.gd")
	var i := src.find("func _load_sheet")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("_frame_px = frame" in body,
		"and it must record the MEASURED frame, not the convention")
