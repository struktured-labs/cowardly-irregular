extends GutTest

## 🐛 CLICKING ONE INTERACTABLE TALKS TO A DIFFERENT ONE. The click path finds what you clicked,
## checks you are close enough to it, and then throws the target away:
##
##     OverworldPlayer:523   var target_npc = _find_clicked_interactable(click_pos)
##                  :526     if dist_to_npc < INTERACT_ARRIVE_DIST:
##                  :528         interaction_requested.emit()      <- carries NO target
##     OverworldController:223  _on_interaction_requested() re-picks the NEAREST to the PLAYER
##
## So with two interactables in reach, a click on the FARTHER one interacts with the nearer one.
## The intent is computed and discarded.
##
## 🔑 WHY THIS IS A DEFECT RATHER THAN A DESIGN. The controller's nearest-wins arbitration is
## deliberate (2026-07-18 audit) and correct for a KEY PRESS, which carries no target — the player
## said "interact" and the game picks. A CLICK carries a target; the player said "that one". The
## click path already measures distance to that specific node, so the code expresses the intent and
## then fails to honour it.
##
## ⚠️ SCOPE, stated because this game is gamepad-first: clicking is a secondary path (CLAUDE.md:
## "NO MOUSE/CLICKING required"), and it is reachable — `OverworldPlayer:521` handles
## MOUSE_BUTTON_LEFT, and click-to-move is the primary use. The defect needs two interactables
## within INTERACT_ARRIVE_DIST (40px) of the player with the clicked one farther, which Harmonia's
## npcs container reaches easily (24 children measured).

const PLAYER := "res://src/exploration/OverworldPlayer.gd"
const CONTROLLER := "res://src/exploration/OverworldController.gd"


class Probe extends Area2D:
	var hits: int = 0
	func _init() -> void:
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 8.0
		cs.shape = sh
		add_child(cs)
		add_to_group("interactables")
	func interact(_who) -> void:
		hits += 1


func _source(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	assert_ne(raw, "", "CONTROL: %s must be readable" % path)
	var code: String = str(GdSource.split(raw)["code"])
	assert_true(code.contains("func "), "CONTROL: the strip must keep real code from %s" % path)
	assert_false(code.contains("##"), "CONTROL: a comment survived into %s's code half" % path)
	return code


## The signal that loses the target. If this ever gains a parameter the defect is structurally gone
## and this arm should be revisited rather than deleted.
func test_the_signal_the_click_path_uses_carries_no_target() -> void:
	var code := _source(PLAYER)
	assert_true(code.contains("signal interaction_requested()"),
		"the click path routes through interaction_requested; a target-carrying signal would change this guard's subject")
	var at := code.find("MOUSE_BUTTON_LEFT")
	assert_gt(at, -1, "the click path must exist, or this guard has no subject")
	var slice := code.substr(at, 420)
	assert_true(slice.contains("_find_clicked_interactable"),
		"the click path must still choose a target")
	assert_true(slice.contains("interaction_requested.emit()"),
		"and still route through the parameterless signal — this is the discard")


## ⛔ THE ARM THAT MATTERS: the controller must honour a target the click path handed it.
##
## ⚠️ MY FIRST VERSION OF THIS ARM ASSERTED A SCENARIO IT NEVER CONSTRUCTED. It called
## `_find_clicked_interactable` — a pure query with no side effect — and then emitted a BARE
## `interaction_requested`, which is a KEY PRESS. Nearest-wins is correct for a key press, so the
## arm was red against correct behaviour and would have stayed red after any fix. The hand-off is
## the subject, so the hand-off has to be in the setup.
##
## 📌 The real mouse handler is not driven here: it reads `get_global_mouse_position()`, which a
## headless SubViewport does not let a test place. So this arm drives the HAND-OFF the handler
## performs, and `test_the_click_path_hands_its_target_over` pins that the handler performs it.
func test_the_controller_honours_a_handed_over_target() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)

	var player = load(PLAYER).new()
	vp.add_child(player)
	player.global_position = Vector2(100, 100)
	var controller = load(CONTROLLER).new()
	controller.player = player
	vp.add_child(controller)

	var near := Probe.new()
	near.name = "NearProbe"
	near.global_position = Vector2(112, 100)
	vp.add_child(near)
	var far := Probe.new()
	far.name = "FarProbe"
	far.global_position = Vector2(130, 100)
	vp.add_child(far)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_lt(player.global_position.distance_to(near.global_position),
		player.global_position.distance_to(far.global_position),
		"CONTROL: the near probe must be nearer, or this arm tests nothing")
	assert_eq(player._find_clicked_interactable(far.global_position), far,
		"CONTROL: a click at the far probe must SELECT the far probe")

	## A KEY PRESS carries no target, so nearest-wins must still apply — the control that stops this
	## fix from becoming "clicks and presses both reach whatever was clicked last".
	player.interaction_requested.emit()
	await get_tree().physics_frame
	assert_eq(near.hits, 1, "a bare press must still reach the NEAREST (near=%d far=%d)" % [near.hits, far.hits])
	assert_eq(far.hits, 0, "a bare press must not reach the far one")

	## Now the click path's hand-off: the target travels with the request.
	player.pending_click_target = far
	player.interaction_requested.emit()
	await get_tree().physics_frame
	assert_eq(far.hits, 1,
		"a handed-over target must be honoured; near=%d far=%d — the clicked node is being discarded and nearest-to-player wins" % [
			near.hits, far.hits])
	assert_eq(near.hits, 1, "and the nearer one must not answer a click aimed past it (near=%d)" % near.hits)

	## Consumed ONCE: a later press must fall back to nearest, not re-fire the stale click.
	assert_null(player.pending_click_target, "the target must be cleared when consumed")
	player.interaction_requested.emit()
	await get_tree().physics_frame
	assert_eq(far.hits, 1, "a stale click target must NOT be honoured twice (far=%d)" % far.hits)
	assert_eq(near.hits, 2, "the later press falls back to nearest (near=%d)" % near.hits)


## The handler must actually hand the target over — the half the arm above cannot drive.
func test_the_click_path_hands_its_target_over() -> void:
	var code := _source(PLAYER)
	var at := code.find("MOUSE_BUTTON_LEFT")
	assert_gt(at, -1, "the click path must exist")
	var slice := code.substr(at, 700)
	assert_true(slice.contains("pending_click_target = target_npc"),
		"an immediate click must hand its chosen node to the controller")
	assert_true(slice.contains("_click_walk_target = target_npc"),
		"a click-walk must remember WHICH node it is walking to, not just where it stood")
	var arrival := code.find("_interact_on_arrival = false")
	assert_gt(arrival, -1, "the arrival path must exist")
	assert_true(code.substr(arrival, 200).contains("pending_click_target = _click_walk_target"),
		"arrival must hand over the node it walked to — otherwise you walk to a distant NPC and talk to whatever you end up beside")
