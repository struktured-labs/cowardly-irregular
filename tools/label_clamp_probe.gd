extends SceneTree

## Four configurations of one Label, to settle which flags defeat the vertical size clamp.
##
## Three lanes measured pieces of this on 2026-10-14 and I relayed one of them into a commit
## message of my own (`86c36e8d1`) without running it. This reproduces the whole table in one
## place so the correction rests on my own numbers.
##
## The claim under test, from my own banked note, which said WIDTH and which I generalised to
## HEIGHT without measuring: "clip_text takes the text out of the minimum size".

const TEXT := "Immense power, but fragile and long enough to wrap if it is allowed to"


func _init() -> void:
	await process_frame
	await process_frame
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)

	print("=== LABEL VERTICAL CLAMP PROBE ===")
	print("one Label, font 48, asked size (400, 4) — does the HEIGHT hold?")
	print("%-34s %-14s %-14s %-14s %s" % ["config", "min", "asked", "settled", "verdict"])

	for cfg in [
		{"name": "baseline", "clip": false, "wrap": TextServer.AUTOWRAP_OFF},
		{"name": "clip_text ALONE", "clip": true, "wrap": TextServer.AUTOWRAP_OFF},
		{"name": "autowrap ALONE", "clip": false, "wrap": TextServer.AUTOWRAP_WORD},
		{"name": "clip_text + AUTOWRAP_WORD", "clip": true, "wrap": TextServer.AUTOWRAP_WORD},
		{"name": "empty text", "clip": false, "wrap": TextServer.AUTOWRAP_OFF, "empty": true},
	]:
		var l := Label.new()
		l.autowrap_mode = cfg["wrap"]
		l.text = "" if cfg.get("empty", false) else TEXT
		l.clip_text = cfg["clip"]
		l.add_theme_font_size_override("font_size", 48)
		host.add_child(l)
		await process_frame
		var mn := l.get_minimum_size()
		l.size = Vector2(400, 4)
		await process_frame
		await process_frame
		var held: bool = is_equal_approx(l.size.y, 4.0)
		print("%-34s %-14s %-14s %-14s %s" % [
			cfg["name"], "(%d,%d)" % [mn.x, mn.y], "(400,4)",
			"(%d,%d)" % [l.size.x, l.size.y],
			"CLAMP DEFEATED" if held else "clamps"])
		l.queue_free()
		await process_frame

	print("=== END ===")
	quit()
