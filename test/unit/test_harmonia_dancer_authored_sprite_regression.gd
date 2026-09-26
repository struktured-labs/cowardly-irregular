extends GutTest

## Harmonia's Dancing Tonberry still drew its dancers in code while
## assets/sprites/npcs/dancer/frame_0..3.png sat on disk.
## VillageBar already loaded those frames. Two siblings did not:
## TavernInterior's stage sprite (always Image.create 32x48 + _draw_dancer)
## and Aria's OverworldNPC idle / stop_dancing pose (_draw_npc, artist frames
## only while dialogue has start_dancing() running).

const FRAME := "res://assets/sprites/npcs/dancer/frame_%d.png"


func _artist(i: int) -> Image:
	var img := (load(FRAME % i) as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _shown(tex: Texture2D) -> Image:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _assert_same_image(tex: Texture2D, frame: int, who: String) -> void:
	var shown := _shown(tex)
	var art := _artist(frame)
	assert_eq(shown.get_width(), art.get_width(),
		"%s frame %d width — the procedural stage canvas is 32x48; the PNG is 32x32" % [who, frame])
	assert_eq(shown.get_height(), art.get_height(),
		"%s frame %d height — procedural stage dancer is 48px; frame_%d.png is 32" % [who, frame, frame])
	var a := shown.get_data()
	var b := art.get_data()
	var mismatch := -1
	var n := mini(a.size(), b.size())
	for i in n:
		if a[i] != b[i]:
			mismatch = i
			break
	if mismatch < 0 and a.size() != b.size():
		mismatch = n
	assert_eq(mismatch, -1,
		"%s frame %d differs from frame_%d.png at byte %d — still the procedural draw" % [who, frame, frame, mismatch])


func test_stage_dancer_uses_the_authored_frames() -> void:
	var tavern := TavernInterior.new()
	tavern._setup_dancer()
	assert_eq(tavern._dancer_frames.size(), 4, "the stage cycle is the four authored frames")
	for i in range(4):
		_assert_same_image(tavern._dancer_frames[i], i, "stage dancer")
	tavern.free()


func test_aria_stands_in_the_authored_frame_before_dialogue() -> void:
	var npc := _aria()
	_assert_same_image(npc.sprite.texture, 0, "Aria idle")


func test_aria_rest_pose_after_dialogue_stays_authored() -> void:
	var npc := _aria()
	npc.start_dancing()
	npc.stop_dancing()
	_assert_same_image(npc.sprite.texture, 0, "Aria after stop_dancing")


func test_a_missing_stage_frame_loads_nothing() -> void:
	var tavern := TavernInterior.new()
	var ok: bool = tavern._try_load_artist_dancer_frames([
		"res://assets/sprites/npcs/dancer/frame_0.png",
		"res://assets/sprites/npcs/dancer/does_not_exist.png",
		"res://assets/sprites/npcs/dancer/frame_2.png",
		"res://assets/sprites/npcs/dancer/frame_3.png",
	])
	assert_false(ok, "one missing frame must refuse the whole stage cycle")
	assert_eq(tavern._dancer_frames.size(), 0, "a refused load must not leave a partial artist cycle")
	tavern.free()


func _aria() -> OverworldNPC:
	var npc := OverworldNPC.new()
	npc.npc_name = "Aria"
	npc.npc_type = "dancer"
	add_child_autofree(npc)
	return npc
