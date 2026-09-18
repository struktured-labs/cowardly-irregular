extends GutTest

## `duck_music_for_dialogue` gated the -6 dB dialogue duck with ONE bool while MULTIPLE holders
## exist: `OverworldNPC:1226` creates its own `NPCDialogue` per NPC (each with its own
## `CutsceneDialogue`), and `CutsceneDirector` creates another. So the second holder's release ended
## the first holder's duck, and the first's own later release was an idempotent no-op.
##
## ⛔ DRIVEN, NOT DERIVED — two real CutsceneDialogue instances, 2026-09-18:
##     A.show_dialogue   db -6.00   A.visible true
##     B.show_dialogue   db -6.00   A.visible true  B.visible true
##     B._finish_dialogue -> db 0.00, A STILL VISIBLE     <- the bed returns mid-conversation
##
## 🔑 AND THE PLAYER PATH IS REACHABLE, each link checked rather than assumed:
##   NPC dialogue pushes NO InputLockManager lock — all four push/pop sites are CutsceneDirector's.
##     It freezes the player with set_can_move(false), which is _can_move's LAYER 3 (movement only).
##   A visible CutsceneDialogue does NOT consume `party_chat` — driven: consumed=false, while
##     ui_accept and ui_cancel both consumed=true.
##   GameLoop:1102 gates Party Chat on EXPLORATION / is_locked() / _transition_in_progress /
##     has_available_chats() — nothing there blocks it while a dialogue is up.
##   PartyChatMenu calls play_cutscene, which shows the DIRECTOR's own dialogue.
##
## ⚠️ OWNERSHIP, NOT A REFCOUNT, AND THE DIRECTION IS WHY. A refcount fails toward "ducked FOREVER"
## when a holder leaks; ownership's exposure is "the OWNER never releases", which is exactly the
## single-holder risk that exists today — and `CutsceneDialogue._exit_tree` already releases if it
## ducked, so that path is closed on the holder side (@cowir-sfx swept it: zero siblings, and the
## other two bool setters in this file are state MIRRORS with no holder protocol, not latches).

const CD := preload("res://src/cutscene/CutsceneDialogue.gd")


func before_each() -> void:
	SoundManager.duck_music_for_dialogue(false)


func after_each() -> void:
	SoundManager.duck_music_for_dialogue(false)


func _db() -> float:
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx == -1:
		return 999.0
	var amp = AudioServer.get_bus_effect(idx, 0)
	return amp.volume_db if amp else 999.0


func _settle(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _dialogue() -> Node:
	var d = CD.new()
	add_child_autofree(d)
	return d


func _line(t: String) -> Dictionary:
	return {"speaker": "Probe", "text": t}


func test_control_one_dialogue_ducks_and_releases() -> void:
	## The single-holder contract, unchanged. Without this arm the ownership arms below could pass on
	## a duck that never engages.
	var a := _dialogue()
	await get_tree().process_frame
	a.show_dialogue([_line("only one talking")])
	await _settle(0.45)
	assert_almost_eq(_db(), -6.0, 0.35, "CONTROL: one dialogue must duck (got %.2f)" % _db())
	a._finish_dialogue()
	await _settle(0.45)
	assert_almost_eq(_db(), 0.0, 0.35, "CONTROL: and its own release must lift the duck (got %.2f)" % _db())


func test_a_second_dialogue_finishing_does_not_lift_the_first_duck() -> void:
	var a := _dialogue()
	var b := _dialogue()
	await get_tree().process_frame
	a.show_dialogue([_line("A is talking")])
	await _settle(0.45)
	assert_almost_eq(_db(), -6.0, 0.35, "CONTROL: A ducked (got %.2f)" % _db())
	b.show_dialogue([_line("B is talking")])
	await get_tree().process_frame
	assert_true(a.visible and b.visible, "CONTROL: both dialogues must be visible, or there is no conflict")

	b._finish_dialogue()
	await _settle(0.55)
	assert_true(a.visible, "CONTROL: A must still be on screen when B finishes")
	assert_almost_eq(_db(), -6.0, 0.35,
		"B's release lifted the duck to %.2f dB while A is still talking — the bed returns mid-conversation and A's own later release is an idempotent no-op" % _db())


func test_the_FIRST_dialogue_finishing_does_not_lift_it_either() -> void:
	## ⛔ THE MIRROR CASE, AND IT IS WHY THIS IS A HOLDER SET RATHER THAN AN OWNER. My first design
	## tracked a single OWNER and ignored releases from anyone else — which fixes B-finishes-first and
	## still releases early when A, the owner, finishes while B is on screen. A set is symmetric:
	## ducked while ANYONE holds it, whatever order they leave in.
	var a := _dialogue()
	var b := _dialogue()
	await get_tree().process_frame
	a.show_dialogue([_line("A is talking")])
	await _settle(0.45)
	b.show_dialogue([_line("B is talking")])
	await get_tree().process_frame
	assert_almost_eq(_db(), -6.0, 0.35, "CONTROL: ducked with both up (got %.2f)" % _db())

	a._finish_dialogue()
	await _settle(0.55)
	assert_true(b.visible, "CONTROL: B must still be on screen when A finishes")
	assert_almost_eq(_db(), -6.0, 0.35,
		"the FIRST holder's release lifted the duck to %.2f dB while B is still talking — an owner-only rule fixes one order and not this one" % _db())


func test_the_holder_can_still_release_after_the_other_finishes() -> void:
	## The other direction, so ownership cannot become "the duck never lifts".
	var a := _dialogue()
	var b := _dialogue()
	await get_tree().process_frame
	a.show_dialogue([_line("A")])
	await _settle(0.45)
	b.show_dialogue([_line("B")])
	await get_tree().process_frame
	b._finish_dialogue()
	await _settle(0.3)
	a._finish_dialogue()
	await _settle(0.55)
	assert_almost_eq(_db(), 0.0, 0.35,
		"the holder's own release must still lift the duck (got %.2f) — ownership must not strand it" % _db())


func test_a_freed_holder_still_releases() -> void:
	## CutsceneDialogue._exit_tree releases if it ducked, and that is the path ownership relies on to
	## avoid a stranded duck. Driven rather than trusted to the comment.
	var a := _dialogue()
	await get_tree().process_frame
	a.show_dialogue([_line("A, about to be freed")])
	await _settle(0.45)
	assert_almost_eq(_db(), -6.0, 0.35, "CONTROL: ducked before the free (got %.2f)" % _db())
	a.free()
	await _settle(0.55)
	assert_almost_eq(_db(), 0.0, 0.35,
		"a holder freed mid-line must release its own duck (got %.2f), or the bed stays down for the session" % _db())


func test_a_holder_freed_without_exit_tree_cannot_strand_the_duck() -> void:
	## ⛔ THE ARM THE PRUNE NEEDED. Removing the `is_instance_valid` prune left all five other arms
	## GREEN — an uncovered line in the one direction I rejected a refcount for, so it had to be
	## either covered or deleted.
	##
	## `_exit_tree` is what normally releases a holder, and it cannot fire for a node that was never
	## IN the tree. Driven: holders 1 -> 2, orphan.free(), holders still 2 (the entry is dead), and
	## the prune is the only thing that drops it. Without it `want` stays true forever and the bed
	## never comes back.
	##
	## ⚠️ Production adds every CutsceneDialogue to the tree, so this is defence rather than a live
	## path — but it is defence against "ducked for the rest of the session", which is why it stays
	## and why it is pinned rather than trusted.
	var keeper := _dialogue()
	await get_tree().process_frame
	keeper.show_dialogue([_line("keeper is talking")])
	await _settle(0.45)
	assert_almost_eq(_db(), -6.0, 0.35, "CONTROL: the keeper ducked (got %.2f)" % _db())

	var orphan = CD.new()
	assert_false(orphan.is_inside_tree(), "CONTROL: the orphan must never enter the tree, or _exit_tree would release it")
	SoundManager.duck_music_for_dialogue(true, orphan)
	orphan.free()

	keeper._finish_dialogue()
	await _settle(0.55)
	assert_almost_eq(_db(), 0.0, 0.35,
		"a freed holder stranded the duck at %.2f dB — the keeper released and a dead entry kept it down for the rest of the session" % _db())
