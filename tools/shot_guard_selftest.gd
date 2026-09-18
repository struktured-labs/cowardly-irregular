extends SceneTree
## Arms for tools/shot_guard.gd. Run: xvfb-run -a godot --headless -s tools/shot_guard_selftest.gd
##
## Every arm builds an Image with a KNOWN number of distinct colours and asserts what the guard
## does with it -- including the two sides of the boundary, because a floor nobody has watched
## reject anything is a constant, not a threshold.

const ShotGuard = preload("res://tools/shot_guard.gd")
const DIR := "res://tmp/shot_guard_selftest"

var _fails := 0
var _arms := 0


func _arm(label: String, got, want) -> void:
	_arms += 1
	if got == want:
		print("  ok    %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s  got %s want %s" % [label, str(got), str(want)])


func _img(colours: int) -> Image:
	## A 1280x720 image whose 1-in-8 sample grid contains EXACTLY `colours` distinct values.
	## Built on the same grid the scorer walks, so the arm's premise is the scorer's premise --
	## a fixture drawn on a different grid would be testing my arithmetic, not the guard.
	var im := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	im.fill(Color8(0, 0, 0))
	var n := 0
	var y := 0
	while y < 720:
		var x := 0
		while x < 1280:
			# distinct values first, then repeat colour 0 so the count stops growing
			var c := n if n < colours else 0
			im.set_pixel(x, y, Color8(c % 256, (c / 256) % 256, (c / 65536) % 256))
			n += 1
			x += 8
		y += 8
	return im


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var floor_v: int = ShotGuard.CONTENT_FLOOR

	# THE SCORER ITSELF, before anything that depends on it.
	_arm("a flat image scores 1", ShotGuard.content_score(_img(1)), 1)
	_arm("a %d-colour image scores %d" % [floor_v, floor_v],
		ShotGuard.content_score(_img(floor_v)), floor_v)
	_arm("the fixture can exceed the floor",
		ShotGuard.content_score(_img(floor_v + 500)), floor_v + 500)

	# REFUSAL. A blank frame must not land under the deliverable name.
	var blank := "%s/blank.png" % DIR
	var ok_blank: bool = ShotGuard.save_or_refuse(_img(1), blank)
	_arm("a blank frame is REFUSED", ok_blank, false)
	_arm("  ...and no shot is written", FileAccess.file_exists(blank), false)
	_arm("  ...and the evidence is kept as .REJECTED.png",
		FileAccess.file_exists("%s/blank.REJECTED.png" % DIR), true)

	# ACCEPTANCE. A guard that only ever refuses is not a guard.
	var good := "%s/good.png" % DIR
	var ok_good: bool = ShotGuard.save_or_refuse(_img(floor_v + 500), good)
	_arm("a real frame is ACCEPTED", ok_good, true)
	_arm("  ...and the shot IS written", FileAccess.file_exists(good), true)
	_arm("  ...and leaves no .REJECTED twin",
		FileAccess.file_exists("%s/good.REJECTED.png" % DIR), false)

	# THE BOUNDARY, both sides. Without these the floor could be any number at all.
	var lo := "%s/below.png" % DIR
	_arm("floor-1 colours is REFUSED", ShotGuard.save_or_refuse(_img(floor_v - 1), lo), false)
	var hi := "%s/at.png" % DIR
	_arm("exactly floor colours is ACCEPTED", ShotGuard.save_or_refuse(_img(floor_v), hi), true)

	print("[shot-guard selftest] %d arm(s), %d failed" % [_arms, _fails])
	quit(1 if _fails > 0 else 0)
