extends GutTest

## msg 2634 Fable-pass #1: _animate_melee_attack lunged to a fixed 40-pixel
## offset from target CENTER regardless of target sprite width. For a
## 256-px artist goblin @ scale 1.0 (half-width 128), that puts the
## attacker 88 pixels INSIDE the goblin's visible body — the weapon
## contact-frame reads misaligned. For a thin procedural sprite the
## opposite: attacker stops short and the weapon never reaches contact.
##
## Fix: replace the constant with a per-cast computation:
##   contact_gap = attacker_half_width + target_half_width + mercy(12)
##
## Fallback preserved: if either sprite can't be measured (missing idle
## frames, non-AnimatedSprite2D), returns the pre-fix 40 constant so
## procedurals without a full frame set don't regress.
##
## Downstream effect: cowir-main's incoming hitstop first-cut lands the
## attacker at the visible edge, which lets the impact frame register
## visually instead of vanishing inside the target sprite.

const BS_PATH: String = "res://src/battle/BattleScene.gd"
const SceneScript = preload("res://src/battle/BattleScene.gd")


## ── Source pins ────────────────────────────────────────────────────────

func test_hardcoded_40_removed_from_melee_animation() -> void:
	# The exact pre-fix pattern that has to be gone: `direction * 40`.
	# If someone reverts to the constant this test flags it in one line.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _animate_melee_attack(attacker_sprite: Node2D, target_sprite: Node2D")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2500)
	assert_false(body.find("direction * 40") > -1,
		"the pre-fix `direction * 40` hardcode must be gone — replaced by _melee_contact_gap(...)")
	assert_string_contains(body, "_melee_contact_gap(attacker_sprite, target_sprite)",
		"attack_pos computation must call the new helper")


func test_helper_and_mercy_constant_declared() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "_melee_contact_gap(attacker_sprite: Node2D, target_sprite: Node2D) -> float:",
		"the contact-gap helper must exist with the exact signature")
	assert_string_contains(src, "const MELEE_CONTACT_MERCY_PX: float = 12.0",
		"mercy margin must be a named tunable const, not a magic literal")
	assert_string_contains(src, "const MELEE_CONTACT_FALLBACK_PX: float = 40.0",
		"fallback must equal the pre-fix constant so unreadable sprites don't regress")


func test_helper_sums_both_reaches_plus_mercy() -> void:
	# The formula shape: both sprites' reach + mercy, never max() or one side. The halves became FIGURE
	# edges in 2026-09 — frame halves are padding, and measured live every attacker stopped 209-221 px
	# short (test_the_lunge_stops_at_the_body_not_the_frame). Same intent, pinned on the shape that
	# replaced it; the arithmetic itself is checked against the real sheets over there.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("_melee_contact_gap(attacker_sprite: Node2D, target_sprite: Node2D) -> float:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1000)
	assert_string_contains(body, "attacker_lead + target_lead + MELEE_CONTACT_MERCY_PX",
		"formula must sum both sprites' reach + mercy — max() or single-side would misalign one edge")
	assert_string_contains(body, "sprite_figure_lead(attacker_sprite, toward)",
		"and each reach must be measured from the FIGURE on the side that faces the other sprite")


func test_fallback_when_either_sprite_unmeasurable() -> void:
	# Belt-and-suspenders: if either sprite returns 0 half-width, return
	# the pre-fix constant. Prevents contact_gap = 12 (mercy alone) which
	# would put attacker practically on top of target.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("_melee_contact_gap(attacker_sprite: Node2D, target_sprite: Node2D) -> float:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1000)
	assert_string_contains(body, "return MELEE_CONTACT_FALLBACK_PX",
		"unmeasurable case must return the fallback const, not the mercy value or zero")
	assert_string_contains(body, "attacker_lead <= 0.0 or target_lead <= 0.0",
		"guard must trip on EITHER sprite being unmeasurable, not both")


## ⛔ The reach helper's claims, asked of the REAL helper. This file used to assert them against a
## hand-written `_WidthStub` COPY of the production code — a second implementation, which cannot notice
## the original changing. `sprite_figure_lead` is static, so the test can call the thing that ships.
func test_the_reach_helper_reads_the_resting_silhouette() -> void:
	var frames := HybridSpriteLoader.load_sprite_frames(null, "fighter", "", "", "", "")
	var a := AnimatedSprite2D.new()
	a.sprite_frames = frames
	a.animation = &"idle"
	a.scale = Vector2(1.5, 1.5)
	add_child_autofree(a)
	var resting: float = SceneScript.sprite_figure_lead(a, -1.0)
	assert_gt(resting, 0.0, "a real sheet measures a reach")
	if frames.has_animation(&"attack"):
		a.animation = &"attack"
		assert_almost_eq(SceneScript.sprite_figure_lead(a, -1.0), resting, 0.01,
			"and it stays the IDLE silhouette while an attack plays — a wider swing frame must not move the lunge's destination mid-tween")
	a.flip_h = true
	assert_gt(SceneScript.sprite_figure_lead(a, -1.0), 0.0,
		"a flipped sprite still reports a positive reach — the figure mirrors, the number does not go negative")
	a.scale = Vector2(-1.5, 1.5)
	assert_gt(SceneScript.sprite_figure_lead(a, -1.0), 0.0, "and a negative scale is read by its magnitude")


func test_non_animated_sprite_returns_zero_reach() -> void:
	# Non-AnimatedSprite2D nodes trigger the fallback path in the caller.
	var n := Node2D.new()
	add_child_autofree(n)
	assert_eq(SceneScript.sprite_figure_lead(n, -1.0), 0.0,
		"plain Node2D returns 0.0 — signaling the caller to use the fallback")
	var empty := AnimatedSprite2D.new()
	empty.sprite_frames = SpriteFrames.new()
	add_child_autofree(empty)
	assert_eq(SceneScript.sprite_figure_lead(empty, -1.0), 0.0, "and so does a sprite with no frames")


