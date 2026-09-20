extends GutTest

## `abort()`'s docstring promises four things; the one that matters most to a
## player has no coverage:
##
##     • player movement → restored (set_can_move(true))
##
## A DynamicConversation freezes the overworld player for its duration. If a
## scene change aborts it and that line does not run, the player is frozen in
## the overworld with no conversation on screen and no input that recovers it —
## a reload. The stakes are entirely OUTSIDE this class, which is why the guard
## was never written here.
##
## ⛔ AND `test_dynamic_conversation.gd` READS AS THOUGH IT COVERS THIS. Its
## header lists "6. Abort — abort() while active cleans up without crash" and
## "7. Player freeze". Measured: `can_move` occurs ZERO times in that file, and
## its one active-state arm sets `_active = true` WITHOUT a `_player`, so the
## branch `if was_active and _player != null` is false and the restore line
## never executes in any existing test.
##
## The `was_active` half is guarded here too, deliberately: abort() must NOT
## unfreeze a player it never froze, or a scene-change abort on an idle
## conversation would hand movement back during someone else's cutscene.

const DC := preload("res://src/llm/DynamicConversation.gd")


class StubPlayer:
	extends Node
	var can_move: bool = true
	var calls: Array[bool] = []

	func set_can_move(v: bool) -> void:
		can_move = v
		calls.append(v)


var _dc = null
var _player: StubPlayer = null


func before_each() -> void:
	_dc = DC.new()
	_dc.name = "AbortRestoreDC"
	add_child_autofree(_dc)
	_player = StubPlayer.new()
	_player.name = "AbortRestoreStubPlayer"
	add_child_autofree(_player)


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_drives_are_reachable() -> void:
	assert_true(_dc.has_method("abort"), "DynamicConversation.abort is gone")
	assert_true("_active" in _dc, "DynamicConversation._active is gone")
	assert_true("_player" in _dc, "DynamicConversation._player is gone — abort's restore target")
	assert_true(_player.has_method("set_can_move"),
		"the stub no longer matches the interface _set_player_movement calls")


# ── the uncovered promise ─────────────────────────────────────────────────────

func test_abort_gives_movement_back_to_the_player_it_froze() -> void:
	## THE DEFECT-SHAPED ARM. Frozen player + active conversation + abort.
	_player.set_can_move(false)
	_player.calls.clear()
	_dc._active = true
	_dc._state = DC.State.PLAYER_TURN
	_dc._player = _player

	_dc.abort()

	assert_true(_player.can_move,
		("abort() left the player frozen (set_can_move calls: %s). A scene change "
		+ "aborts the conversation, the overworld has no dialogue on screen, and "
		+ "no input recovers movement — the player must reload.") % [_player.calls])


func test_abort_does_not_unfreeze_a_player_it_never_froze() -> void:
	## THE OTHER HALF, and the reason abort() tests `was_active` at all. An idle
	## conversation aborted during someone else's cutscene must not hand movement
	## back mid-scene.
	_player.set_can_move(false)
	_player.calls.clear()
	_dc._active = false
	_dc._player = _player

	_dc.abort()

	assert_false(_player.can_move,
		("abort() on an INACTIVE conversation restored movement it never took "
		+ "(calls: %s). Anything else holding the player frozen — a cutscene, a "
		+ "transition — just lost its lock.") % [_player.calls])


func test_a_second_abort_does_not_touch_the_player_again() -> void:
	## abort() is documented idempotent and safe at any state. A second call
	## must be inert, not a second write to a player another system now owns.
	##
	## ⚠️ THIS ARM IS WEAKER THAN ITS SIBLINGS AND THE MEASUREMENT SAYS SO. The
	## property is DOUBLY guarded — `_active = false` and `_player = null` — and
	## each masks the other, so removing either ALONE leaves this green. It reds
	## only when both go (measured: EC=1, "wrote to the player again: [true]").
	## Kept because a restructure of abort() would take both at once, which is
	## exactly when idempotency stops being free.
	_player.set_can_move(false)
	_dc._active = true
	_dc._player = _player
	_dc.abort()
	_player.calls.clear()

	_dc.abort()

	assert_eq(_player.calls.size(), 0,
		"the second abort() wrote to the player again: %s" % [_player.calls])
