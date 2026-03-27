extends GutTest

## Mode 7 Horizontal Movement Compensation — math prototype
##
## The Mode 7 shader compresses horizontal texture space at the player's feet.
## This makes horizontal movement appear slower than vertical movement even
## though the physics engine moves the player the same distance in both axes.
##
## Two correction strategies are evaluated here (math only, no OverworldPlayer.gd edits):
##   A. Velocity compensation  — multiply horizontal velocity by 1/x_width
##   B. Camera-lead compensation — leave velocity alone, shift camera offset laterally
##
## All numbers derive from Mode7Overlay defaults (near_scale=0.45, ground_y=0.48)
## and the player screen position (75% from top, horizon=0.0).

# ---------------------------------------------------------------------------
# Shader constants (must match Mode7Overlay / mode7.gdshader defaults)
# ---------------------------------------------------------------------------
const NEAR_SCALE: float    = 0.45   # uniform near_scale
const GROUND_Y: float      = 0.48   # uniform ground_y
const HORIZON: float       = 0.0    # uniform horizon
const PLAYER_SCREEN_Y: float = 0.75  # player sits at 75% of viewport height

# ---------------------------------------------------------------------------
# Player / physics constants
# ---------------------------------------------------------------------------
const MOVE_SPEED: float      = 180.0    # px/s, OverworldPlayer.move_speed
const TILE_SIZE: float       = 32.0     # world pixels per tile
const PHYSICS_FPS: float     = 60.0
const PHYSICS_DT: float      = 1.0 / PHYSICS_FPS

# Largest collision radius used by OverworldPlayer (CircleShape2D)
const COLLISION_RADIUS: float = 7.0

# Maximum safe single-frame displacement = fraction of collision diameter.
# If the player moves more than this in one physics tick the engine's
# continuous-collision-detection (CCD) may tunnel through thin geometry.
# Godot's CharacterBody2D uses discrete CCD by default, so a reasonable
# heuristic is < 1× the collision diameter (14 px) per frame.
const MAX_SAFE_FRAME_DISP: float = COLLISION_RADIUS * 2.0  # 14 px per frame


# ---------------------------------------------------------------------------
# Helper: compute x_width at an arbitrary screen_y fraction
# ---------------------------------------------------------------------------
func _x_width_at(screen_y: float) -> float:
	var h: float = screen_y - HORIZON
	if h <= 0.0:
		return 1.0  # In sky — no compression
	return NEAR_SCALE / h


# ---------------------------------------------------------------------------
# Test 1 — derive the exact compensation factor from shader math
# ---------------------------------------------------------------------------

func test_compression_factor_at_player_feet():
	gut.p("=== Test 1: Horizontal Compression Factor at Player Feet ===")

	var h: float = PLAYER_SCREEN_Y - HORIZON
	gut.p("  player_screen_y: %.2f" % PLAYER_SCREEN_Y)
	gut.p("  horizon:         %.2f" % HORIZON)
	gut.p("  h (dist below horizon): %.3f" % h)

	var x_width: float = NEAR_SCALE / h
	gut.p("  near_scale:     %.2f" % NEAR_SCALE)
	gut.p("  x_width:        %.4f  (%.0f%% of full width)" % [x_width, x_width * 100.0])

	# x_width < 1.0  →  horizontal space is compressed
	assert_lt(x_width, 1.0,
		"x_width should be < 1.0 at player feet — horizontal space IS compressed")
	assert_almost_eq(x_width, 0.6, 0.001,
		"Expected x_width = 0.45 / 0.75 = 0.6000, got %.4f" % x_width)

	var compensation: float = 1.0 / x_width
	gut.p("  compensation factor:  1 / %.4f = %.4f" % [x_width, compensation])
	assert_almost_eq(compensation, 1.6667, 0.001,
		"Compensation factor should be ~1.6667, got %.4f" % compensation)

	gut.p("  CONCLUSION: horizontal movement appears %.0f%% slower than vertical" %
		((1.0 - x_width) * 100.0))


# ---------------------------------------------------------------------------
# Test 2 — velocity compensation: compensated speed and collision safety
# ---------------------------------------------------------------------------

func test_velocity_compensation_speed_and_safety():
	gut.p("=== Test 2: Velocity Compensation — Speed & Collision Safety ===")

	var x_width: float     = _x_width_at(PLAYER_SCREEN_Y)  # 0.6
	var compensation: float = 1.0 / x_width                  # 1.6667

	var h_speed_raw: float  = MOVE_SPEED                          # 180 px/s — uncompensated
	var h_speed_comp: float = MOVE_SPEED * compensation           # 300 px/s — compensated
	var v_speed: float      = MOVE_SPEED                          # 180 px/s — unmodified

	gut.p("  move_speed (base):          %.0f px/s" % MOVE_SPEED)
	gut.p("  x_width at feet:            %.4f" % x_width)
	gut.p("  compensation factor:        %.4f" % compensation)
	gut.p("  H speed (uncompensated):    %.0f px/s" % h_speed_raw)
	gut.p("  H speed (compensated):      %.0f px/s" % h_speed_comp)
	gut.p("  V speed (unchanged):        %.0f px/s" % v_speed)

	# Compensated horizontal world speed = 300 px/s → *apparent* speed ≈ 180 px/s visually
	var h_apparent: float = h_speed_comp * x_width
	gut.p("  H apparent speed after shader: %.0f px/s  (should ≈ %.0f)" % [h_apparent, v_speed])
	assert_almost_eq(h_apparent, v_speed, 1.0,
		"After compensation, apparent horizontal speed should match vertical speed")

	# Diagonal compensation: when moving diagonally, normalize BEFORE applying H boost,
	# otherwise the vector magnitude explodes.
	var diagonal_world: Vector2 = Vector2(MOVE_SPEED * compensation, MOVE_SPEED)
	var diagonal_magnitude: float = diagonal_world.length()
	var uncorrected_diagonal: Vector2 = Vector2(MOVE_SPEED, MOVE_SPEED)
	var uncorrected_magnitude: float = uncorrected_diagonal.length()
	gut.p("  Diagonal magnitude (compensated):   %.0f px/s" % diagonal_magnitude)
	gut.p("  Diagonal magnitude (uncompensated): %.0f px/s" % uncorrected_magnitude)
	gut.p("  Diagonal over-speed ratio: %.2fx" % (diagonal_magnitude / uncorrected_magnitude))
	assert_gt(diagonal_magnitude, uncorrected_magnitude,
		"Diagonal with compensation is faster than without (expected)")

	# --- Collision safety ---
	# Worst case: player moves at full compensated speed for one physics frame.
	var max_frame_disp: float = h_speed_comp * PHYSICS_DT
	gut.p("  Max frame displacement (H, compensated): %.2f px" % max_frame_disp)
	gut.p("  Safe threshold (2× collision radius):    %.2f px" % MAX_SAFE_FRAME_DISP)

	var collision_safe: bool = max_frame_disp < MAX_SAFE_FRAME_DISP
	gut.p("  Collision-safe per frame: %s" % str(collision_safe))

	if not collision_safe:
		gut.p("  WARNING: %.2f px/frame > %.2f px threshold — potential tunnel risk" % [
			max_frame_disp, MAX_SAFE_FRAME_DISP])
		gut.p("  Mitigation: use CharacterBody2D safe_margin or reduce compensation to 1.4x")

	# We do NOT assert collision_safe=true here — we report the finding.
	# The caller asked us to calculate and report; it's acceptable to find it unsafe.
	assert_true(true, "Collision safety calculated (see gut.p output above)")

	gut.p("  Compensated speed (%.0f px/s) %s collision-safe limit (%.0f px/frame = %.0f px/s)" % [
		h_speed_comp,
		"EXCEEDS" if not collision_safe else "is within",
		MAX_SAFE_FRAME_DISP,
		MAX_SAFE_FRAME_DISP * PHYSICS_FPS])


# ---------------------------------------------------------------------------
# Test 3 — camera-lead approach (offset, not velocity)
# ---------------------------------------------------------------------------

func test_camera_lead_compensation():
	gut.p("=== Test 3: Camera-Lead Approach ===")
	gut.p("  Strategy: keep velocity = 180 px/s but shift Camera2D.offset.x")
	gut.p("  proportionally to horizontal world movement.")

	var x_width: float = _x_width_at(PLAYER_SCREEN_Y)
	var deficit: float  = 1.0 - x_width  # 0.4 → horizontal appears 40% slower

	# When player moves dx world units horizontally, camera should lead by
	#   dx * deficit  extra world units to compensate visually.
	# Example: player moves 3 px in one frame → camera leads by 3 * 0.4 = 1.2 px.
	var example_dx: float = MOVE_SPEED * PHYSICS_DT  # 3.0 px at 60 fps
	var lead_offset: float = example_dx * deficit
	gut.p("  Per-frame player dx:  %.2f px  (@ %.0f px/s, %.0f fps)" % [
		example_dx, MOVE_SPEED, PHYSICS_FPS])
	gut.p("  Camera lead per frame: %.2f px  (deficit = %.3f)" % [lead_offset, deficit])

	# Camera lead accumulates while moving and returns to 0 when stopped.
	# The total steady-state camera lead at full speed:
	# If smoothed with a lerp factor k, steady state = lead_offset / (k * dt)
	# For k = 6.0 (typical lerp speed), dt = 1/60:
	var lerp_k: float = 6.0
	var steady_state_lead: float = lead_offset / (lerp_k * PHYSICS_DT)
	gut.p("  Steady-state camera lead (lerp k=%.0f): %.2f px" % [lerp_k, steady_state_lead])
	gut.p("  (The camera runs %.2f px ahead of player while walking horizontally)" % steady_state_lead)

	# The camera lead does NOT affect collision detection — physics remain at 180 px/s.
	var max_frame_disp_lead: float = MOVE_SPEED * PHYSICS_DT
	gut.p("  Max frame displacement (camera-lead approach): %.2f px" % max_frame_disp_lead)
	gut.p("  Collision safe: %s (velocity is unchanged)" % str(max_frame_disp_lead < MAX_SAFE_FRAME_DISP))

	assert_lt(max_frame_disp_lead, MAX_SAFE_FRAME_DISP,
		"Camera-lead approach: player velocity unchanged, always collision-safe")
	assert_gt(lead_offset, 0.0,
		"Camera lead should be a positive offset when moving horizontally")
	assert_gt(lead_offset, 0.5,
		"Camera lead offset should be perceptible (>0.5 px/frame)")


# ---------------------------------------------------------------------------
# Test 4 — compare visual-equivalent distance: raw vs compensated
# ---------------------------------------------------------------------------

func test_visual_equivalent_distance_comparison():
	gut.p("=== Test 4: Visual Distance Comparison over N frames ===")

	var frames: int = 60  # 1 second of movement
	var x_width: float = _x_width_at(PLAYER_SCREEN_Y)

	# --- Uncompensated ---
	var world_h_raw: float    = MOVE_SPEED * frames * PHYSICS_DT
	var apparent_h_raw: float = world_h_raw * x_width
	var world_v: float        = MOVE_SPEED * frames * PHYSICS_DT
	# vertical apparent == world (no vertical compression in Mode 7 at player feet)
	var apparent_v: float     = world_v

	gut.p("  Over %d frames (%.1f s):" % [frames, frames * PHYSICS_DT])
	gut.p("  --- Uncompensated ---")
	gut.p("  Horizontal world distance:    %.0f px" % world_h_raw)
	gut.p("  Horizontal apparent distance: %.0f px  (after %.0f%% compression)" % [
		apparent_h_raw, (1.0 - x_width) * 100.0])
	gut.p("  Vertical world distance:      %.0f px" % world_v)
	gut.p("  Vertical apparent distance:   %.0f px" % apparent_v)
	gut.p("  H/V apparent ratio: %.2f  (1.0 = equal, <1.0 = H looks shorter)" % (apparent_h_raw / apparent_v))

	# --- Velocity compensated ---
	var compensation: float    = 1.0 / x_width
	var world_h_comp: float    = MOVE_SPEED * compensation * frames * PHYSICS_DT
	var apparent_h_comp: float = world_h_comp * x_width

	gut.p("  --- Velocity compensated ---")
	gut.p("  Horizontal world distance:    %.0f px  (%.0fx faster physics)" % [
		world_h_comp, compensation])
	gut.p("  Horizontal apparent distance: %.0f px" % apparent_h_comp)
	gut.p("  H/V apparent ratio: %.2f  (should be ~1.0)" % (apparent_h_comp / apparent_v))

	assert_almost_eq(apparent_h_comp, apparent_v, 1.0,
		"Compensated horizontal apparent distance should equal vertical apparent distance")
	assert_lt(apparent_h_raw / apparent_v, 0.8,
		"Without compensation H appears noticeably shorter than V (ratio < 0.8)")


# ---------------------------------------------------------------------------
# Test 5 — compression gradient across the ground plane
# ---------------------------------------------------------------------------

func test_compression_gradient_near_to_far():
	gut.p("=== Test 5: Compression Gradient (player feet → horizon) ===")
	gut.p("  screen_y  |  h      |  x_width  |  comp factor  |  H speed comp")
	gut.p("  ----------+---------+-----------+---------------+--------------")

	var check_points: Array = [0.75, 0.65, 0.55, 0.50, 0.48]
	for sy in check_points:
		var h: float   = sy - HORIZON
		if h <= NEAR_SCALE:
			gut.p("  %.2f     |  %.3f  |  IN FOG  |  —          |  —  (horizon band)" % [sy, h])
			continue
		var xw: float  = NEAR_SCALE / h
		var comp: float = 1.0 / xw
		var speed: float = MOVE_SPEED * comp
		gut.p("  %.2f     |  %.3f  |  %.4f   |  %.4f       |  %.0f px/s" % [
			sy, h, xw, comp, speed])

	# At the player's feet (sy=0.75): h is largest → x_width smallest → most compression → highest comp needed
	var feet_comp: float = 1.0 / _x_width_at(0.75)
	# At mid-distance (sy=0.65): h is smaller → x_width larger → less compression → lower comp needed
	var mid_comp: float  = 1.0 / _x_width_at(0.65)

	gut.p("  Note: player feet are MOST compressed (largest h, smallest x_width)")
	gut.p("  Objects between player and horizon are LESS compressed (smaller h, larger x_width)")
	gut.p("  Feet comp: %.3f  Mid comp: %.3f" % [feet_comp, mid_comp])

	# Feet need MORE compensation than mid-distance objects
	assert_gt(feet_comp, mid_comp,
		"Player feet (sy=0.75) are more compressed than mid-distance (sy=0.65) — feet need higher compensation")


# ---------------------------------------------------------------------------
# Test 6 — diagonal movement: should we compensate both axes or just H?
# ---------------------------------------------------------------------------

func test_diagonal_compensation_analysis():
	gut.p("=== Test 6: Diagonal Movement Compensation Analysis ===")

	var x_width: float  = _x_width_at(PLAYER_SCREEN_Y)
	var compensation: float = 1.0 / x_width

	# Raw diagonal velocity (normalized to move_speed)
	var raw_diag: Vector2 = Vector2(1.0, 1.0).normalized() * MOVE_SPEED
	gut.p("  Raw diagonal:      %s  (magnitude %.0f px/s)" % [raw_diag, raw_diag.length()])

	# Naively boost H component BEFORE normalizing — magnitude explodes
	var boosted_no_norm: Vector2 = Vector2(raw_diag.x * compensation, raw_diag.y)
	gut.p("  H-boosted (no norm):  %s  (magnitude %.0f px/s)" % [
		boosted_no_norm, boosted_no_norm.length()])

	# Boost H, then renormalize to move_speed — keeps speed constant, changes angle
	var boosted_normalized: Vector2 = Vector2(raw_diag.x * compensation, raw_diag.y).normalized() * MOVE_SPEED
	gut.p("  H-boosted (normalized): %s  (magnitude %.0f px/s)" % [
		boosted_normalized, boosted_normalized.length()])

	# The visual angle of raw diagonal in Mode 7 (x compressed):
	var visual_angle_raw: float  = atan2(raw_diag.y, raw_diag.x * x_width)
	var visual_angle_comp: float = atan2(boosted_normalized.y, boosted_normalized.x * x_width)
	gut.p("  Apparent angle (raw):  %.1f°  (expected 45°)" % rad_to_deg(visual_angle_raw))
	gut.p("  Apparent angle (comp): %.1f°  (should be 45°)" % rad_to_deg(visual_angle_comp))

	# Raw diagonal looks steeper than 45° due to horizontal compression
	assert_gt(abs(rad_to_deg(visual_angle_raw)), 50.0,
		"Uncompensated diagonal appears steeper than 45° due to horizontal compression")
	# Compensated diagonal should look approximately 45°
	assert_almost_eq(rad_to_deg(visual_angle_comp), 45.0, 5.0,
		"Compensated+normalized diagonal should appear ~45°")

	gut.p("  RECOMMENDATION: compensate H component THEN normalize to move_speed")
	gut.p("  This gives correct apparent angle AND maintains original physics speed")


# ---------------------------------------------------------------------------
# Test 7 — summary table: is 300 px/s (compensated) safe for collision?
# ---------------------------------------------------------------------------

func test_collision_safety_summary():
	gut.p("=== Test 7: Collision Safety Summary ===")

	var speeds: Dictionary = {
		"Uncompensated (180 px/s)": MOVE_SPEED,
		"Velocity compensated (300 px/s)": MOVE_SPEED * (1.0 / _x_width_at(PLAYER_SCREEN_Y)),
		"Partial comp 1.4x (252 px/s)": MOVE_SPEED * 1.4,
		"Partial comp 1.2x (216 px/s)": MOVE_SPEED * 1.2,
	}

	gut.p("  speed label                        |  px/s  |  px/frame  |  safe?")
	gut.p("  -----------------------------------+--------+------------+-------")
	for label in speeds:
		var spd: float = speeds[label]
		var per_frame: float = spd * PHYSICS_DT
		var safe: bool = per_frame < MAX_SAFE_FRAME_DISP
		gut.p("  %-35s| %6.0f | %10.2f | %s" % [
			label, spd, per_frame, "YES" if safe else "NO  <-- tunnel risk"])

	gut.p("")
	gut.p("  Collision radius: %.0f px → safe threshold = %.2f px/frame (%.0f px/s)" % [
		COLLISION_RADIUS, MAX_SAFE_FRAME_DISP, MAX_SAFE_FRAME_DISP * PHYSICS_FPS])
	gut.p("")
	gut.p("  FINDING: full compensation (300 px/s = 5.00 px/frame) is WITHIN the 14 px safe limit.")
	gut.p("  At 60 fps, 300 px/s = 5.0 px/frame vs threshold=14 px (2× radius=7 px).")
	gut.p("  All compensated speeds are collision-safe against standard 32 px tile walls.")
	gut.p("  Marginal concern only for sub-7px corridor geometry (unlikely in this project).")
	gut.p("  RECOMMENDATION: velocity compensation at 1.667x is safe. Camera-lead is safer still.")

	# Partial compensation 1.4x is always safe
	var partial_per_frame: float = (MOVE_SPEED * 1.4) * PHYSICS_DT
	assert_lt(partial_per_frame, MAX_SAFE_FRAME_DISP,
		"1.4x partial compensation should stay within collision-safe threshold")

	# Full compensation 1.667x is also safe (5.0 px/frame < 14.0 px threshold)
	var full_per_frame: float = (MOVE_SPEED * (1.0 / _x_width_at(PLAYER_SCREEN_Y))) * PHYSICS_DT
	assert_lt(full_per_frame, MAX_SAFE_FRAME_DISP,
		"Full compensation (5.0 px/frame) is within the 14 px safe threshold (2× collision radius)")
