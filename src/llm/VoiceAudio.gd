class_name VoiceAudio
extends RefCounted

## WAV bytes from a speech server → a playable stream, plus the clipping count the status line reports.

## A sample at or past this magnitude is pinned at the int16 rail.
const RAIL := 32767
## Pinned runs that mark a line clipped; a single one can be a clean peak.
const CLIPPED_RUNS := 2


## Null unless the bytes are a whole RIFF/WAVE: the engine would play a truncated file short.
static func decode(bytes: PackedByteArray) -> AudioStreamWAV:
	if not is_complete_wav(bytes):
		return null
	return AudioStreamWAV.load_from_buffer(bytes)


static func is_complete_wav(bytes: PackedByteArray) -> bool:
	if bytes.size() < 44:
		return false
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return false
	var pos := 12
	while pos + 8 <= bytes.size():
		var size: int = bytes.decode_u32(pos + 4)
		if bytes.slice(pos, pos + 4).get_string_from_ascii() == "data":
			return size > 0 and pos + 8 + size <= bytes.size()
		pos += 8 + size + (size & 1)
	return false


## Runs of consecutive samples at the rail; 16-bit mono PCM, anything else reports 0.
static func pinned_runs(stream: AudioStreamWAV) -> int:
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return 0
	var d: PackedByteArray = stream.data
	var runs := 0
	var in_run := false
	for i in range(0, d.size() - 1, 2):
		var v: int = d.decode_s16(i)
		var pinned: bool = v >= RAIL or v <= -RAIL
		if pinned and not in_run:
			runs += 1
		in_run = pinned
	return runs


static func is_clipped(stream: AudioStreamWAV) -> bool:
	return pinned_runs(stream) >= CLIPPED_RUNS
