extends GutTest

## Regression test for the inter-frame upper-body swivel bug.
##
## Bug history (2026-05-02):
##   Players reported the fighter's face "swivels back and forth like he's
##   looking left and right per step" when walking south (row 0 / DOWN).
##   Initial fix applied a 45% head-lock — heads pixel-identical across the
##   walk cycle, only legs animated. Same-day playtest revealed the chest
##   and shoulders were still drifting ("the body kinda swivels a bit too
##   in an unnatural fashion"). Threshold raised to 65% upper-body lock,
##   matching classic SNES JRPG sprite convention (head + torso + arms
##   locked, only legs alternate).
##
## What we assert:
##   For each row, the upper 65% of the chibi (head + neck + torso + arms)
##   must be pixel-identical across all 4 frames. We detect the chibi's
##   vertical bbox per row from frame 0's alpha channel and compare the
##   upper-body region across frames 1/2/3.
##
## Mirror property is checked separately by test_overworld_facing_regression.gd.

const FRAME_SIZE := 32
const HEAD_FRAC := 0.65
const STARTER_JOBS := ["fighter", "cleric", "rogue", "mage"]
const NPC_ARCHETYPES := [
    "old_man", "old_woman", "young_man", "young_woman", "child",
    "guard", "merchant", "scholar",
    "innkeeper", "blacksmith", "priestess", "noble", "noblewoman",
    "king", "queen", "soldier", "farmer", "fisherman", "monk", "traveler",
    "dr_temporal",
]


func _load_image(path: String) -> Image:
    if not ResourceLoader.exists(path):
        return null
    var tex = load(path) as Texture2D
    if tex == null:
        return null
    return tex.get_image()


func _frame_bbox_y(img: Image, row_idx: int, col_idx: int) -> Vector2i:
    # Returns Vector2i(y_top, y_bot) for the 32x32 frame's opaque bbox.
    # If frame is empty, returns Vector2i(-1, -1).
    var y_top := -1
    var y_bot := -1
    var ox := col_idx * FRAME_SIZE
    var oy := row_idx * FRAME_SIZE
    for y in range(FRAME_SIZE):
        var any_opaque := false
        for x in range(FRAME_SIZE):
            if img.get_pixel(ox + x, oy + y).a > 0.05:
                any_opaque = true
                break
        if any_opaque:
            if y_top < 0:
                y_top = y
            y_bot = y
    return Vector2i(y_top, y_bot)


func _head_pixels_match(img: Image, row_idx: int, col_a: int, col_b: int, y_top: int, y_lock_end: int) -> int:
    # Counts mismatched pixels in the head region between two frames.
    # Compares alpha + only-opaque RGB (Godot's fix_alpha_border setting bleeds
    # RGB into transparent pixels, so RGB on alpha=0 isn't reliable).
    var diffs := 0
    var oy := row_idx * FRAME_SIZE
    var oxa := col_a * FRAME_SIZE
    var oxb := col_b * FRAME_SIZE
    for y in range(y_top, y_lock_end):
        for x in range(FRAME_SIZE):
            var pa := img.get_pixel(oxa + x, oy + y)
            var pb := img.get_pixel(oxb + x, oy + y)
            if abs(pa.a - pb.a) > 0.02:
                diffs += 1
                continue
            if pa.a < 0.05 and pb.a < 0.05:
                continue
            var d: float = abs(pa.r - pb.r) + abs(pa.g - pb.g) + abs(pa.b - pb.b)
            if d > 0.02:
                diffs += 1
    return diffs


func _assert_head_locked(path: String, label: String) -> void:
    var img = _load_image(path)
    if img == null:
        return  # missing asset — skip silently (other tests assert presence)
    if img.get_width() != 128 or img.get_height() != 128:
        return  # not the expected 4x4 grid format
    for row in range(4):
        var bbox := _frame_bbox_y(img, row, 0)
        if bbox.x < 0:
            continue  # row 0 frame is empty — skip
        var head_h := maxi(1, int(float(bbox.y - bbox.x + 1) * HEAD_FRAC))
        var y_lock_end := mini(FRAME_SIZE, bbox.x + head_h)
        for col in [1, 2, 3]:
            var diffs := _head_pixels_match(img, row, 0, col, bbox.x, y_lock_end)
            assert_lt(diffs, 4,
                "%s row %d frame %d: head region (y=%d..%d) should be pixel-identical to frame 0. Got %d diffs (expected <4)." %
                [label, row, col, bbox.x, y_lock_end, diffs])


func test_starter_jobs_head_locked() -> void:
    for job in STARTER_JOBS:
        _assert_head_locked("res://assets/sprites/jobs/%s/overworld.png" % job, "job:" + job)


func test_npc_archetypes_head_locked() -> void:
    for npc in NPC_ARCHETYPES:
        _assert_head_locked("res://assets/sprites/npcs/%s/overworld.png" % npc, "npc:" + npc)
