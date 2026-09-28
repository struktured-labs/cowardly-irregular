class_name WavFixture
extends RefCounted

## Mono 16-bit PCM WAV bytes for tests; no server or GPU needed.

static func pcm16(samples: PackedInt32Array, rate: int = 24000) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(samples[i], -32768, 32767))
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_u32(36 + data.size()))
	out.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 1)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * 2)
	fmt.encode_u16(16, 2)
	fmt.encode_u16(18, 16)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	out.append_array(_u32(data.size()))
	out.append_array(data)
	return out


## A sine at this peak amplitude; peak 29196 is the supported server's -1 dBFS ceiling.
static func tone(seconds: float, peak: int, rate: int = 24000) -> PackedByteArray:
	var s := PackedInt32Array()
	s.resize(int(seconds * rate))
	for i in s.size():
		s[i] = int(round(sin(i * 0.05) * peak))
	return pcm16(s, rate)


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


## Why a null voice decode was refused BY DESIGN (issue #224), or "" when the null is a real failure.
## Two refusals, not one: the latch clears on mixer progress while an abandoned decode worker can still be alive.
static func decode_refusal_reason(stream: Variant) -> String:
	if stream != null:
		return ""
	var tree := Engine.get_main_loop() as SceneTree
	var sm: Node = tree.root.get_node_or_null("SoundManager") if tree != null else null
	if sm == null:
		return ""
	if sm.mixer_is_wedged():
		return "the headless mixer latch is set"
	if sm.has_method("_voice_decode_still_running") and sm._voice_decode_still_running():
		return "an earlier voice decode is still stuck inside load_from_buffer, so a new one is refused"
	return ""


## The failure text for a by-design refusal: loud, named, and not mistaken for a defect.
static func refusal_note(why: String) -> String:
	return "voice WAV decode refused because %s; the AudioServer.lock guard (issue #224) is working, re-run before debugging" % why
