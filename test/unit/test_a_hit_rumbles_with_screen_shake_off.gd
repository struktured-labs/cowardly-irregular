extends GutTest

## Screen Shake off also silenced the pad on every spell (cowir-controller's read, main 23764 thread): EffectSystem's
## shake returned at the Screen Shake setting BEFORE handing the hit to BattleJuice.add_trauma, which is where rumble
## rides. Direct add_trauma callers (melee) still rumbled, so the two halves of one battle disagreed. In battle the
## shake request now always reaches add_trauma: the camera rig refuses the SHAKE itself, should_rumble decides the pad.
## Headless has no pads, so the arms watch BattleJuice.rumble_wanted, emitted once every rumble gate has passed.

var _shake_before := true
var _flags_before: Dictionary = {}
var _rig_before = null
var _wanted: Array = []


func before_each() -> void:
	_shake_before = GameState.screen_shake_enabled
	_flags_before = GameState.battle_fx_flags.duplicate(true)
	_rig_before = BattleJuice.camera_rig
	BattleJuice._last_rumble_at = -1.0
	BattleJuice._last_rumble_amount = 0.0
	BattleJuice.burst_host = null
	Engine.time_scale = 1.0
	_wanted = []
	BattleJuice.rumble_wanted.connect(_on_wanted)


func after_each() -> void:
	BattleJuice.rumble_wanted.disconnect(_on_wanted)
	GameState.screen_shake_enabled = _shake_before
	GameState.battle_fx_flags = _flags_before
	BattleJuice.camera_rig = _rig_before
	BattleJuice._last_rumble_at = -1.0
	Engine.time_scale = 1.0


func _on_wanted(amount: float) -> void:
	_wanted.append(amount)


func _rig() -> BattleCameraRig:
	var rig := BattleCameraRig.new()
	add_child_autofree(rig)
	BattleJuice.camera_rig = rig
	return rig


func test_the_floor_names_every_member_this_file_drives() -> void:
	assert_true(EffectSystem.has_method("_trigger_screen_shake"), "EffectSystem._trigger_screen_shake must exist")
	assert_true(BattleJuice.has_signal("rumble_wanted"), "BattleJuice.rumble_wanted must exist")
	assert_true("camera_rig" in BattleJuice and "_last_rumble_at" in BattleJuice, "BattleJuice.camera_rig / _last_rumble_at must exist")
	assert_true("_trauma" in BattleCameraRig.new(), "BattleCameraRig._trauma must exist")
	assert_true("screen_shake_enabled" in GameState and "battle_fx_flags" in GameState, "GameState carries both settings")


## CONTROL: with Screen Shake on, a spell's shake both moves the rig and wants the pad.
func test_with_shake_on_a_spell_shakes_and_rumbles() -> void:
	var rig := _rig()
	GameState.screen_shake_enabled = true
	EffectSystem._trigger_screen_shake(12.0, 0.3)
	assert_gt(rig._trauma, 0.0, "CONTROL: the rig took the trauma")
	assert_eq(_wanted.size(), 1, "CONTROL: and the pad was wanted once")


func test_with_shake_off_a_spell_still_rumbles_and_the_camera_stays() -> void:
	var rig := _rig()
	GameState.screen_shake_enabled = false
	EffectSystem._trigger_screen_shake(12.0, 0.3)
	assert_eq(_wanted.size(), 1, "Screen Shake off: the spell's hit still reaches the pad")
	assert_eq(rig._trauma, 0.0, "and the camera rig took no trauma")


## The pad's own switch still gates it: Pad Rumble off is silent whatever Screen Shake says.
func test_pad_rumble_off_stays_silent() -> void:
	_rig()
	GameState.screen_shake_enabled = false
	GameState.battle_fx_flags["rumble"] = false
	EffectSystem._trigger_screen_shake(12.0, 0.3)
	assert_eq(_wanted.size(), 0, "Pad Rumble off: nothing wants the motors")


## 4x / turbo / autogrind are the OFF tier: no rumble there, shake setting or not.
func test_the_off_tier_stays_silent() -> void:
	_rig()
	GameState.screen_shake_enabled = false
	Engine.time_scale = 4.0
	EffectSystem._trigger_screen_shake(12.0, 0.3)
	Engine.time_scale = 1.0
	assert_eq(_wanted.size(), 0, "at 4x the tier is OFF and the pad stays still")


## Outside battle (no rig) the legacy camera steps keep their Screen Shake gate, and nothing rumbles.
func test_outside_battle_shake_off_does_nothing() -> void:
	BattleJuice.camera_rig = null
	GameState.screen_shake_enabled = false
	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.make_current()
	var before := cam.offset
	EffectSystem._trigger_screen_shake(12.0, 0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(cam.offset, before, "exploration: Screen Shake off moves no camera")
	assert_false(EffectSystem._is_shaking, "and starts no shake")
	assert_eq(_wanted.size(), 0, "and wants no rumble")


## The motors have ONE caller. A second start_joy_vibration site would skip the flag, the tier and the throttle.
func test_only_battlejuice_starts_the_motors() -> void:
	var hits: Array = []
	var stack: Array = ["res://src"]
	var seen := 0
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for d in DirAccess.get_directories_at(dir):
			stack.append(dir.path_join(d))
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			seen += 1
			var path := dir.path_join(f)
			if FileAccess.get_file_as_string(path).contains("start_joy_vibration") and not path.ends_with("battle/BattleJuice.gd"):
				hits.append(path)
	assert_gt(seen, 100, "CONTROL: the walk read src (%d scripts)" % seen)
	assert_true(FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd").contains("start_joy_vibration"), "CONTROL: the scan finds the one real caller")
	assert_eq(hits, [], "start_joy_vibration lives only in BattleJuice.rumble: %s" % [hits])
