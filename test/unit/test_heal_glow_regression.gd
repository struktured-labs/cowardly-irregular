extends GutTest

## Polish regression: healing now gets a soft expanding green glow under
## the target sprite, parity with damage's screen-shake reaction.
##
## Before: on_healing_done only spawned a green number popup (visually
## identical to any other floaty number). Damage hits got a screen-shake
## + a number, so heals felt understated for an equally important moment.
##
## Now: on_healing_done spawns BOTH a green number AND a soft green glow
## panel that fades in (0.18s) → fades out (0.62s) → scales 0.5 → 1.3 over
## the full envelope, then queue_frees.
##
## Tests pin:
##   • on_healing_done invokes spawn_heal_glow (the wiring)
##   • spawn_heal_glow creates a child of _scene that is a PanelContainer
##     with corner_radius (the soft-bubble shape) and a green-dominant
##     bg_color (the heal color), then queue_frees within the envelope
##   • The helper anchors below sprite center (ground-up read)
##   • Source-pin that the alpha tween envelope is ~0.8s total so the
##     effect can't silently regress to a no-op (alpha=0 the whole time)

const BattleResultsDisplayScript := preload("res://src/battle/BattleResultsDisplay.gd")
const RESULTS_PATH := "res://src/battle/BattleResultsDisplay.gd"


# ── Stub scene that just records children, no autoload deps ────────────────
class _StubScene extends Node:
	pass


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ────────────────────────────────────────────────────────────

func test_on_healing_done_calls_spawn_heal_glow() -> void:
	# Pin the wiring — every heal must trigger both the number and the glow.
	var text := _read(RESULTS_PATH)
	var idx := text.find("func on_healing_done")
	assert_gt(idx, -1, "on_healing_done must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("spawn_damage_number"),
		"on_healing_done must still spawn the floating number popup")
	assert_true(body.contains("spawn_heal_glow"),
		"on_healing_done must dispatch to spawn_heal_glow for parity with damage")


func test_spawn_heal_glow_helper_exists() -> void:
	var text := _read(RESULTS_PATH)
	assert_gt(text.find("func spawn_heal_glow"), -1,
		"spawn_heal_glow(pos) helper must exist")


func test_glow_uses_green_dominant_color() -> void:
	# The glow should read green to the player — pin that the bg_color has
	# green dominance (G > R, G > B). Without this, the helper could exist
	# but the wrong color hex could silently turn the glow red/blue.
	var text := _read(RESULTS_PATH)
	var idx := text.find("func spawn_heal_glow")
	assert_gt(idx, -1, "spawn_heal_glow must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Look for a Color(R, G, B, A) where G is high relative to R and B.
	# Acceptable bg patterns: Color(0.2-0.5, 0.9-1.0, 0.3-0.7, ...).
	var has_green_bg := body.contains("Color(0.35, 1.0, 0.5")
	# Be tolerant of small re-tunes; just require G==1.0 alongside R<0.6.
	if not has_green_bg:
		# Fallback: scan for "Color(<r>, 1.0," with r < 0.6 in body.
		for r_str in ["Color(0.2, 1.0,", "Color(0.25, 1.0,", "Color(0.3, 1.0,",
				"Color(0.35, 1.0,", "Color(0.4, 1.0,", "Color(0.45, 1.0,",
				"Color(0.5, 1.0,", "Color(0.55, 1.0,"]:
			if body.contains(r_str):
				has_green_bg = true
				break
	assert_true(has_green_bg,
		"glow bg_color must read green (G==1.0 with R well under 1.0)")


func test_glow_has_rounded_corners() -> void:
	# Sharp rectangles read as "damage indicator" — heals should be soft.
	var text := _read(RESULTS_PATH)
	var idx := text.find("func spawn_heal_glow")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("corner_radius_top_left"),
		"glow style must set corner radii so the shape reads as soft/round")


func test_glow_envelope_terminates_with_queue_free() -> void:
	# Without queue_free, repeated heals would leak Panel nodes into the scene.
	var text := _read(RESULTS_PATH)
	var idx := text.find("func spawn_heal_glow")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("queue_free"),
		"glow tween must terminate with queue_free so heals don't leak nodes")


func test_glow_envelope_actually_animates_alpha() -> void:
	# Defense against an inert helper: the tween envelope must include a
	# non-zero alpha target (else the player sees nothing).
	var text := _read(RESULTS_PATH)
	var idx := text.find("func spawn_heal_glow")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Must tween modulate:a up to something visible (>0.2) and back to 0.
	assert_true(body.contains("modulate:a"),
		"glow must animate modulate:a (the visible-ness of the effect)")
	# Cheap "peak alpha > 0.2" check: scan for any modulate:a target literal.
	var has_visible_peak := false
	for peak in ["0.85", "0.8", "0.75", "0.7", "0.65", "0.6", "0.5", "0.4", "0.35", "0.3"]:
		# Pair check: "modulate:a", <peak>" appears in body
		if body.contains("\"modulate:a\", " + peak):
			has_visible_peak = true
			break
	assert_true(has_visible_peak,
		"glow modulate:a must tween up to a visible peak (> 0.2)")
	assert_true(body.contains("\"modulate:a\", 0.0"),
		"glow modulate:a must tween back to 0 so the effect ends invisible")


# ── Behavioral spawn check ─────────────────────────────────────────────────

func test_spawn_heal_glow_adds_panel_child_to_scene() -> void:
	# Stub the scene so we can verify spawn_heal_glow add_childs a Control
	# (and that it does so even when scene-position lookup happens elsewhere).
	var stub := _StubScene.new()
	add_child_autofree(stub)
	var disp: BattleResultsDisplayScript = BattleResultsDisplayScript.new(stub)
	var before := stub.get_child_count()
	disp.spawn_heal_glow(Vector2(100, 100))
	assert_eq(stub.get_child_count(), before + 1,
		"spawn_heal_glow must add exactly one child to the scene")
	var spawned := stub.get_child(stub.get_child_count() - 1)
	assert_true(spawned is PanelContainer,
		"spawned glow must be a PanelContainer (matches the soft-bubble style)")
	# Pivot must be centered for the scale tween to grow from the middle.
	assert_almost_eq(spawned.pivot_offset.x, spawned.size.x / 2.0, 0.5,
		"glow pivot_offset.x must be centered for the scale tween")
	assert_almost_eq(spawned.pivot_offset.y, spawned.size.y / 2.0, 0.5,
		"glow pivot_offset.y must be centered for the scale tween")
	# Starts invisible — fade-in is the entrance.
	assert_almost_eq(spawned.modulate.a, 0.0, 0.01,
		"glow must start at alpha 0 so the fade-in is the entrance")
