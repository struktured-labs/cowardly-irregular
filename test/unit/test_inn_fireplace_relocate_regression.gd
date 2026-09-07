extends GutTest

## Inn fireplace relocation + hearth secret (struktured, msg 2764 item 2).
##
## "in a really stupid place — right next to the innkeeper holding a drink,
## looks like it's going to burn down his place. Move it to the back,
## probably on the back wall." Plus: "add a SECRET on fireplace interact —
## gamepad-interactable, one-time, save-persisted flag."
##
## Pre-fix the hearth sat at grid (4.5, 4.5) with the innkeeper at (2, 3) —
## 2.5 tiles apart, which is what read as "about to burn his place down."
## The whole cluster (surround, mantle shelf, collision body, fire sprite,
## fire light, and the `h` tiles themselves) moved +7 east / -3 north onto
## the north wall, which is the "back" from the south entrance at row 13.
##
## Moving a fireplace means moving SIX coupled things. Missing one leaves
## the fire burning where the hearth used to be, or a collision box in open
## floor — so the test pins them as a set rather than spot-checking one.

const INN := "res://src/maps/interiors/InnInterior.gd"
const SECRET := "res://src/exploration/FireplaceSecret.gd"

## New hearth anchor, in tiles.
const HEARTH_X := 11.5
const HEARTH_Y := 1.5
## Innkeeper's grid position — the thing we're moving AWAY from.
const KEEPER := Vector2(2, 3)
## Far enough that the fire is plainly not on his counter.
const MIN_SAFE_TILES := 6.0


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _layout_rows() -> Array:
	var src := _read(INN)
	var start := src.find("const INN_LAYOUT = [")
	assert_gt(start, 0, "INN_LAYOUT present")
	var body_start := src.find("[", start) + 1
	var body_end := src.find("]", body_start)
	var rows: Array = []
	for m in RegEx.create_from_string("\"([^\"]+)\"").search_all(src.substr(body_start, body_end - body_start)):
		rows.append(m.get_string(1))
	return rows


## The hearth TILES moved to the north wall, and left no strays behind.
func test_hearth_tiles_are_on_the_back_wall() -> void:
	var rows := _layout_rows()
	var hearth_cells: Array = []
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row[x] == "h":
				hearth_cells.append(Vector2i(x, y))
	assert_gt(hearth_cells.size(), 0, "inn still has a hearth")
	for c in hearth_cells:
		assert_lt(c.y, 5,
			"hearth tile at %s must be on the NORTH (back) wall — struktured asked for it moved to the back" % str(c))
		assert_gt(c.x, 8,
			"hearth tile at %s must be clear of the innkeeper's corner" % str(c))


## Distance from the keeper is the actual complaint, so assert the outcome
## rather than just the new coordinates.
func test_hearth_is_no_longer_beside_the_innkeeper() -> void:
	var d: float = Vector2(HEARTH_X, HEARTH_Y).distance_to(KEEPER)
	assert_gt(d, MIN_SAFE_TILES,
		"hearth is %.1f tiles from the innkeeper at %s — was 2.5, which read as 'about to burn his place down'" % [d, str(KEEPER)])
	# And the source must actually carry the new anchor.
	var src := _read(INN)
	assert_true(src.contains("Vector2(11.5 * TILE_SIZE, 1.5 * TILE_SIZE)"),
		"surround + collision body sit at the new hearth anchor")


## All six coupled pieces must travel together. The failure this catches is
## a partial move — fire still burning at the old spot, or an invisible
## collision box left in the middle of the room.
func test_every_fireplace_piece_moved_together() -> void:
	var src := _read(INN)
	for stale in [
		"surround.position = Vector2(4.5 * TILE_SIZE, 4.5 * TILE_SIZE)",
		"shelf.position = Vector2(3.0 * TILE_SIZE, 3.5 * TILE_SIZE)",
		"hearth_body.position = Vector2(4.5 * TILE_SIZE, 4.5 * TILE_SIZE)",
		"_fire_sprite.position = Vector2(4.5 * TILE_SIZE, 5.0 * TILE_SIZE)",
		"_fire_light.position = Vector2(4.5 * TILE_SIZE, 5.5 * TILE_SIZE)",
	]:
		assert_false(src.contains(stale),
			"stale fireplace anchor left behind: %s" % stale)
	# Fire sprite + light stay BELOW the surround (they sit in the hearth
	# mouth, not on the mantle) — pins the relative geometry survived.
	assert_true(src.contains("_fire_sprite.position = Vector2(11.5 * TILE_SIZE, 2.0 * TILE_SIZE)"),
		"fire sprite in the hearth mouth, one half-tile below the surround")
	assert_true(src.contains("_fire_light.position = Vector2(11.5 * TILE_SIZE, 2.5 * TILE_SIZE)"),
		"fire light below the sprite, as before the move")


# ── The secret ─────────────────────────────────────────────────────────

func test_secret_is_one_time_and_save_persisted() -> void:
	var src := _read(SECRET)
	assert_ne(src, "", "FireplaceSecret script exists")
	assert_true(src.contains("inn_fireplace_secret_found"),
		"secret has a named flag")
	assert_true(src.contains("set_story_flag"),
		"flag goes through story_flags, which the save serialises — 'save-persisted' per the directive")
	assert_true(src.contains("is_story_flag_set"),
		"re-examine checks the flag rather than re-granting")
	# The grant must be gated BEFORE it happens — flag first, then pay.
	var flag_pos := src.find("gs.set_story_flag(SECRET_FLAG)")
	var pay_pos := src.find("gs.add_gold(SECRET_GOLD)")
	assert_gt(flag_pos, 0, "flag is set")
	assert_gt(pay_pos, 0, "gold is granted")
	assert_lt(flag_pos, pay_pos,
		"flag must be written BEFORE the grant — a mid-frame re-entry between them would double-pay")


func test_secret_is_gamepad_interactable_with_the_zone_listener_gates() -> void:
	var src := _read(SECRET)
	assert_true(src.contains("ui_accept"),
		"gamepad-interactable per the directive (A button), not mouse-only")
	# Same zone-listener class fix every other interactable carries — my own
	# lint enforces this, so a new one that skips it fails the suite.
	assert_true(src.contains("TutorialHint.is_any_active()"),
		"hint-dismiss press must not also fire the secret")
	assert_true(src.contains("InputLockManager"),
		"cutscene/dialogue A-press must not also fire the secret")


## Re-examining after claiming must stay interactive, not go dead — a
## prompt that stops responding reads as a bug rather than as 'already got it'.
func test_claimed_secret_still_acknowledges() -> void:
	var src := _read(SECRET)
	assert_true(src.contains("ALREADY_LINE"),
		"a claimed hearth still says something when examined")
	var already := src.find("ALREADY_LINE")
	var found := src.find("FOUND_LINE")
	assert_gt(already, 0)
	assert_gt(found, 0)
	assert_true(src.contains("_toast(ALREADY_LINE)"),
		"the already-claimed branch actually surfaces its line")


func test_inn_wires_the_secret() -> void:
	var src := _read(INN)
	assert_true(src.contains("_create_fireplace_secret()"),
		"inn calls the secret factory from _ready")
	assert_true(src.contains("FireplaceSecret.new()"),
		"secret is instantiated by class, not a bare Area2D with a set_script")
	assert_true(src.contains("Vector2(11.5 * TILE_SIZE, 4.0 * TILE_SIZE)"),
		"secret zone sits in FRONT of the hearth (south of it), reachable without standing in the fire")
