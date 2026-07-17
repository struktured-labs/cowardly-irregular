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
	assert_string_contains(src, "func _melee_contact_gap(attacker_sprite: Node2D, target_sprite: Node2D) -> float:",
		"the new contact-gap helper must exist with the exact signature")
	assert_string_contains(src, "const MELEE_CONTACT_MERCY_PX: float = 12.0",
		"mercy margin must be a named tunable const, not a magic literal")
	assert_string_contains(src, "const MELEE_CONTACT_FALLBACK_PX: float = 40.0",
		"fallback must equal the pre-fix constant so unreadable sprites don't regress")


func test_helper_sums_half_widths_plus_mercy() -> void:
	# The formula shape: attacker_half + target_half + mercy. Textual pin
	# guards against a future refactor swapping to a max() or hardcoding.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _melee_contact_gap(attacker_sprite: Node2D, target_sprite: Node2D) -> float:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1000)
	assert_string_contains(body, "attacker_half + target_half + MELEE_CONTACT_MERCY_PX",
		"formula must sum both half-widths + mercy — max() or single-side would misalign one edge")


func test_fallback_when_either_sprite_unmeasurable() -> void:
	# Belt-and-suspenders: if either sprite returns 0 half-width, return
	# the pre-fix constant. Prevents contact_gap = 12 (mercy alone) which
	# would put attacker practically on top of target.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _melee_contact_gap(attacker_sprite: Node2D, target_sprite: Node2D) -> float:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1000)
	assert_string_contains(body, "return MELEE_CONTACT_FALLBACK_PX",
		"unmeasurable case must return the fallback const, not the mercy value or zero")
	assert_string_contains(body, "attacker_half <= 0.0 or target_half <= 0.0",
		"guard must trip on EITHER sprite being unmeasurable, not both")


func test_half_width_helper_reads_idle_frame() -> void:
	# The width read follows the existing convention (BS:929-935 uses idle
	# frame 0 for sprite scale sizing). Same anchor keeps behavior
	# predictable — attack animations often have wider frames (weapon
	# swing) but the LUNGE distance should be pinned to the resting
	# silhouette to avoid the destination shifting mid-tween.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _sprite_visible_half_width(sprite: Node2D) -> float:",
		"the sprite-width helper must exist with the exact signature")
	var idx: int = src.find("func _sprite_visible_half_width(sprite: Node2D) -> float:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1000)
	assert_string_contains(body, "has_animation(&\"idle\")",
		"must gate on the idle animation existing so non-idle sprites don't push_warning")
	assert_string_contains(body, "get_frame_texture(&\"idle\", 0)",
		"read frame 0 of idle for a stable resting silhouette")
	assert_string_contains(body, "absf(a.scale.x)",
		"multiply by absolute scale — a flip_h'd sprite (scale.x < 0) still has positive visible width")


## ── Behavioral: helper against a stub Node2D exercises fallback ────────

func test_non_animated_sprite_returns_zero_half_width() -> void:
	# Non-AnimatedSprite2D nodes trigger the fallback path in the caller.
	# Exercise via a plain Node2D since the helper is scene-agnostic.
	var stub := _make_helper_stub()
	var n := Node2D.new()
	add_child_autofree(n)
	assert_eq(stub._width_of(n), 0.0,
		"plain Node2D returns 0.0 — signaling the caller to use the fallback")


## Minimal subclass that inlines _sprite_visible_half_width so we can
## exercise it without instantiating the full BattleScene.
class _WidthStub extends Node:
	func _width_of(sprite: Node2D) -> float:
		if not is_instance_valid(sprite):
			return 0.0
		if sprite is AnimatedSprite2D:
			var a: AnimatedSprite2D = sprite
			if a.sprite_frames and a.sprite_frames.has_animation(&"idle") and a.sprite_frames.get_frame_count(&"idle") > 0:
				var tex: Texture2D = a.sprite_frames.get_frame_texture(&"idle", 0)
				if tex:
					return tex.get_size().x * 0.5 * absf(a.scale.x)
		return 0.0

func _make_helper_stub() -> _WidthStub:
	var s := _WidthStub.new()
	add_child_autofree(s)
	return s
