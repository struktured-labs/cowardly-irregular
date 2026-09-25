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
