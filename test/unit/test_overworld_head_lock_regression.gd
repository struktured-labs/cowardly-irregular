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

## Advanced/meta job overworld sheets. Added 2026-07-30 — they were on disk and
## the gate never looked at them. All ten measure 0 diffs, so this is coverage,
## not a fix. Joined to the corpus by test_head_lock_coverage_derived.
const OTHER_JOBS := [
    "bard", "guardian", "ninja", "summoner", "speculator",
    "scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter",
]
const NPC_ARCHETYPES := [
    "old_man", "old_woman", "young_man", "young_woman", "child",
    "guard", "merchant", "scholar",
    "innkeeper", "blacksmith", "priestess", "noble", "noblewoman",
    "king", "queen", "soldier", "farmer", "fisherman", "monk", "traveler",
    "dr_temporal",
    # Added 2026-07-30, measured 0 diffs. Named story NPCs were absent entirely.
    "chancellor_mordaine",
    # Added 2026-08-06 with the sheets. Tutorial Fairy Pip and Ghost Barkeep Claude
    # were rendering as generic humans; these are their archetype sheets.
    "fairy", "ghost",
    # Added 2026-07-30 after the exemption-expiry test proved they pass the
    # gate's own metric: bram/elder_theron/marta/phil/scholar_milo measure 0
    # diffs under _frame_bbox_y. My 32-diff reading used a different anchor.
    "bram", "elder_theron", "marta", "phil", "scholar_milo",
	# Added 2026-09-11 with the per-world variant relanding. The coverage test caught that
	# 76 sheets existed that this gate never measured — every _<world> variant plus four base
	# archetypes. Listing them MEASURES them; any that fail the head lock are real findings.
	"blacksmith_digital", "blacksmith_industrial", "blacksmith_steampunk", "blacksmith_suburban", "child_abstract",
	"child_digital", "child_industrial", "child_suburban", "curator", "elder",
	"fairy_abstract", "fairy_digital", "fairy_industrial", "fairy_steampunk", "fairy_suburban",
	"farmer_abstract", "farmer_digital", "farmer_industrial", "farmer_suburban", "fisherman_abstract",
	"fisherman_suburban", "ghost_abstract", "ghost_digital", "ghost_industrial", "ghost_steampunk",
	"ghost_suburban", "guard_digital", "guard_industrial", "guard_suburban", "innkeeper_abstract",
	"innkeeper_suburban", "king_abstract", "king_digital", "king_industrial", "king_steampunk",
	"king_suburban", "merchant_abstract", "merchant_digital", "merchant_industrial", "monk_abstract",
	"monk_industrial", "monk_steampunk", "noble_industrial", "noble_steampunk", "noblewoman_suburban",
	"old_man_abstract", "old_man_digital", "old_man_steampunk", "old_man_suburban", "old_woman_abstract",
	"old_woman_digital", "old_woman_steampunk", "old_woman_suburban", "priestess_digital", "priestess_suburban",
	"queen_digital", "queen_suburban", "scholar_abstract", "scholar_digital", "scholar_industrial",
	"scholar_steampunk", "soldier_abstract", "soldier_steampunk", "soldier_suburban", "tempo",
	"traveler_steampunk", "traveler_suburban", "warden", "young_man_abstract", "young_man_digital",
	"young_man_steampunk", "young_man_suburban", "young_woman_abstract", "young_woman_digital", "young_woman_steampunk",
	"young_woman_suburban",
	# plus the 2026-09-11 regenerated variants (same drop, second pass).
	"blacksmith_abstract", "child_steampunk", "farmer_steampunk", "fisherman_digital", "fisherman_industrial",
	"fisherman_steampunk", "guard_abstract", "guard_steampunk", "innkeeper_digital", "innkeeper_industrial",
	"innkeeper_steampunk", "merchant_steampunk", "merchant_suburban", "monk_digital", "monk_suburban",
	"noble_abstract", "noble_digital", "noble_suburban", "noblewoman_abstract", "noblewoman_digital",
	"noblewoman_industrial", "noblewoman_steampunk", "old_man_industrial", "old_woman_industrial", "priestess_abstract",
	"priestess_industrial", "priestess_steampunk", "queen_abstract", "queen_industrial", "queen_steampunk",
	"scholar_suburban", "soldier_digital", "soldier_industrial", "traveler_abstract", "traveler_digital",
	"traveler_industrial", "young_man_industrial", "young_woman_industrial",
	# the two base archetypes the variant tool cannot make (2026-09-11).
	"arbiter", "mysterious",
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


func _head_pixels_match_shifted(img: Image, row_idx: int, col_a: int, col_b: int, y_top: int, y_lock_end: int, dy: int) -> int:
    # Like _head_pixels_match but frame B is sampled dy pixels lower —
    # a UNIFORM 1px stride bob (2026-07-11 robed-walker fix) is deliberate
    # whole-sprite rhythm, not garble; garbled heads match NO shift.
    var diffs := 0
    var oy := row_idx * FRAME_SIZE
    var oxa := col_a * FRAME_SIZE
    var oxb := col_b * FRAME_SIZE
    for y in range(y_top, y_lock_end):
        var yb := y + dy
        if yb < 0 or yb >= FRAME_SIZE:
            continue
        for x in range(FRAME_SIZE):
            var pa := img.get_pixel(oxa + x, oy + y)
            var pb := img.get_pixel(oxb + x, oy + yb)
            if abs(pa.a - pb.a) > 0.02:
                diffs += 1
                continue
            if pa.a < 0.05 and pb.a < 0.05:
                continue
            var d: float = abs(pa.r - pb.r) + abs(pa.g - pb.g) + abs(pa.b - pb.b)
            if d > 0.02:
                diffs += 1
    return diffs


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


## Returns "" when the sheet was MEASURED, else why it was not. It returned void and bare-returned
## on every skip, so a listed sheet that vanished, changed size, or lost its reference column was
## silently not checked. Measured 2026-09-11: with assets/sprites/npcs deleted entirely this file
## reported EC 0 -- 145 listed archetypes, zero measured, success. Only a sibling file redded, and
## only because it walks DISK rather than the list.
func _assert_head_locked(path: String, label: String) -> String:
    # FileAccess FIRST: load() resolves a retained .ctex for a PNG that has been DELETED, so the
    # null arm below never fires in a tree that has ever imported. Measured 2026-09-11 -- removing
    # monk/overworld.png and re-importing left this gate green until this line existed.
    if not FileAccess.file_exists(path):
        return "%s: no file at %s" % [label, path]
    var img = _load_image(path)
    if img == null:
        return "%s: %s exists but does not load as an image" % [label, path]
    if img.get_width() != 128 or img.get_height() != 128:
        return "%s: %dx%d, not the 128x128 4x4 grid this gate can measure" % [label, img.get_width(), img.get_height()]
    var rows_measured := 0
    for row in range(4):
        var bbox := _frame_bbox_y(img, row, 0)
        if bbox.x < 0:
            continue  # row 0 frame is empty -- skip
        rows_measured += 1
        var head_h := maxi(1, int(float(bbox.y - bbox.x + 1) * HEAD_FRAC))
        var y_lock_end := mini(FRAME_SIZE, bbox.x + head_h)
        for col in [1, 2, 3]:
            var diffs := _head_pixels_match(img, row, 0, col, bbox.x, y_lock_end)
            for dy in [-1, 1]:
                diffs = mini(diffs, _head_pixels_match_shifted(img, row, 0, col, bbox.x, y_lock_end, dy))
            assert_lt(diffs, 4,
                "%s row %d frame %d: head region (y=%d..%d) should be pixel-identical to frame 0. Got %d diffs (expected <4)." %
                [label, row, col, bbox.x, y_lock_end, diffs])
    if rows_measured == 0:
        return "%s: every row-0 reference frame is empty -- nothing to lock the walk cycle against" % label
    return ""


## COUNT WHAT RAN, NOT WHAT FAILED. Every listed name must be MEASURED, not merely visited: the
## per-sheet assertions live inside a loop, so a list whose sheets are all unreadable runs zero of
## them and reports success. Collected and asserted ONCE outside the loop, so a list that drains
## cannot retire the guard either.
func _sweep(names: Array, template: String, kind: String) -> void:
    assert_gt(names.size(), 0, "CONTROL: the %s list is empty -- this gate would pass by doing nothing" % kind)
    var unmeasured: Array = []
    for n in names:
        var why := _assert_head_locked(template % n, kind + ":" + n)
        if why != "":
            unmeasured.append(why)
    assert_eq(unmeasured, [],
        "%d of %d %s sheets were NOT measured by this gate -- a skipped sheet is indistinguishable from a passing one: %s" % [
            unmeasured.size(), names.size(), kind, str(unmeasured)])


func test_starter_jobs_head_locked() -> void:
    _sweep(STARTER_JOBS, "res://assets/sprites/jobs/%s/overworld.png", "job")


func test_other_jobs_head_locked() -> void:
    _sweep(OTHER_JOBS, "res://assets/sprites/jobs/%s/overworld.png", "job")


func test_npc_archetypes_head_locked() -> void:
    _sweep(NPC_ARCHETYPES, "res://assets/sprites/npcs/%s/overworld.png", "npc")
