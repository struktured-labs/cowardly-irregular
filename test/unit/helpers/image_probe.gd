extends RefCounted
## An image read that SURVIVES a null texture, for any arm that measures pixels.
##
## ⛔ A GDScript abort kills its ENCLOSING function only. A read inlined in an arm therefore takes
## that arm's remaining asserts with it and the run stays GREEN — measured 2026-09-17 by injecting
## a typed-null abort at 17 read positions across the sprite guards: 17 of 17 reported Passing,
## EC 0, nothing red. A positive control against a repaired arm reported Failing 1, so the silence
## was the subjects' and not the instrument's.
##
## 🔑 THE RETURN TYPE IS THE POINT. An abort inside this helper returns Array's default — EMPTY —
## which no successful read can produce. A `-> Image` helper would hand back `null`, and a
## `-> float` one `0.0`, both of which a caller can mistake for a measurement.
##
## ⚠️ THIS ANSWERS POSITION, NOT REACHABILITY. Reading through here makes an abort VISIBLE; it does
## not make one possible. 8 of those 17 positions null-check their receiver on the line above and
## can never abort at all — only the sites with no guarded receiver need this.
static func image_of(tex: Texture2D) -> Array:
	return [tex.get_image()]

## The width of one frame of an animation, as a ONE-ELEMENT array.
##
## Same contract as image_of: an abort anywhere in the chain -- a null SpriteFrames, an animation
## that is not there, a frame index past the end -- returns EMPTY rather than a number a caller
## could mistake for a measurement.
static func frame_width_of(sf: SpriteFrames, anim: StringName, idx: int) -> PackedFloat32Array:
	return PackedFloat32Array([sf.get_frame_texture(anim, idx).get_size().x])
