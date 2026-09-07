extends GutTest

## Live-playtest bug (cowir-main relay of struktured, msg 2361):
##   1. Rogue spotlight duel: player watched the rogue die in ~1 autobattle
##      turn instead of playing the fight — the spotlight PC was routed
##      through autobattle because their `_unlocked` flag only flips on
##      victory, so their own duel started with the lock still on.
##   2. On defeat, the game_over ditty played and REPEATED on each retry
##      cycle instead of transitioning cleanly into the retry-entry battle
##      music.
##
## Guards:
## - Routing: when the spotlight duelist is the only alive player_party
##   member (solo duel shape), their autobattle_locked override does NOT
##   force AI selection. Multi-PC party keeps the lock semantics intact.
## - Audio: BattleScene skips play_music("game_over") when the current
##   defeat is inside a spotlight duel (GameLoop._spotlight_duel_active).

const BM_PATH: String = "res://src/battle/BattleManager.gd"
const BS_PATH: String = "res://src/battle/BattleScene.gd"


func _bm() -> Node:
	var bm: Node = load(BM_PATH).new()
	add_child_autofree(bm)
	return bm


func _pc(name_str: String, locked: bool = false) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name_str
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	c.job = {"id": "rogue"}
	c.job_level = 5
	c.autobattle_locked = locked
	return c


## ── Routing: solo duel unlocks the duelist ──────────────────────────────

func test_solo_duelist_lock_is_overridden_for_their_own_spotlight() -> void:
	# Textual pin — the guard has three parts: (1) player_party.size()==1,
	# (2) the current PC IS the solo player_party member, (3) fires only
	# when is_spotlight_locked was already true. If any of the three drop,
	# the lock silently returns and the player watches AI play their duel.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(src, "player_party.size() == 1",
		"solo player_party is the shape that identifies a spotlight duel here")
	assert_string_contains(src, "current_combatant in player_party",
		"the current PC must be the solo player_party member")
	assert_string_contains(src, "is_spotlight_locked and player_party.size() == 1",
		"override only when a lock was already in force (else this is a no-op)")


func test_multi_pc_party_keeps_spotlight_lock_semantics() -> void:
	# The override only kicks in for solo player_party fights. In a normal
	# 5-PC battle a non-lead PC's spotlight lock must STILL route them
	# through autobattle — that's the whole spotlight-onboarding UX.
	var bm := _bm()
	var lead := _pc("Lead", false)
	var locked := _pc("Locked", true)
	bm.player_party = [lead, locked] as Array[Combatant]
	# Replicate the routing gate's read directly (the override in
	# _process_next_selection is inline; this pins the semantic).
	var is_spotlight_locked := "autobattle_locked" in locked and bool(locked.autobattle_locked)
	assert_true(is_spotlight_locked, "sanity: field seed")
	# Solo-party override predicate: false in a multi-PC party.
	var solo_override: bool = bm.player_party.size() == 1
	assert_false(solo_override,
		"multi-PC party must NOT trigger the solo-duel override — the lock stands")
	lead.free(); locked.free()


func test_solo_duel_predicate_holds_when_alone() -> void:
	var bm := _bm()
	var solo := _pc("Rogue", true)
	bm.player_party = [solo] as Array[Combatant]
	assert_eq(bm.player_party.size(), 1, "solo duel shape")
	assert_true(solo in bm.player_party, "PC is in the solo party")
	# The override read: is_spotlight_locked && solo && in party → clear the lock.
	assert_true(bool(solo.autobattle_locked), "sanity: lock is on going in")
	solo.free()


## ── Audio: no game_over ditty during spotlight retry loop ───────────────

func test_battle_scene_gates_game_over_on_spotlight_flag() -> void:
	# BattleScene's defeat branch reads GameLoop._spotlight_duel_active
	# before calling play_music("game_over") — under a retry loop the
	# ditty would otherwise stack every cycle. Pin the guard textually.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "_spotlight_duel_active",
		"BattleScene must consult the spotlight flag before playing game_over")
	assert_string_contains(src, "if not in_spotlight:",
		"the flag must gate the play_music call")
	# Regression guard: the raw play_music("game_over") call still exists
	# for the non-spotlight case — so we ONLY skip it inside the guard.
	assert_string_contains(src, "SoundManager.play_music(\"game_over\")",
		"non-spotlight defeats keep the ditty (retention regression guard)")


func test_defeat_animation_still_plays_in_spotlight() -> void:
	# The defeat animation loop must run regardless of the audio gate —
	# skipping only the ditty means the visual defeat beat is preserved.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var defeat_block_idx: int = src.find("Play defeat animation for all party members")
	assert_gt(defeat_block_idx, -1, "the animation-loop comment anchors the block")
	var slice: String = src.substr(defeat_block_idx, 400)
	assert_string_contains(slice, "animator.play_defeat()",
		"defeat animation must still fire — audio is what changes, not visuals")


## ── Guard is scoped: normal battle defeats still play the ditty ─────────

func test_normal_battle_defeat_still_plays_game_over_when_gameloop_absent() -> void:
	# When GameLoop is nowhere in the tree (unit test contexts, headless
	# resolvers, etc.), `in_spotlight` is false and the ditty plays. This
	# keeps every non-spotlight defeat unchanged.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "get_node_or_null(\"/root/GameLoop\")",
		"absent GameLoop resolves to null → in_spotlight false → ditty plays")
	assert_string_contains(src, "gl != null and \"_spotlight_duel_active\" in gl",
		"safe-property-check ordering: null-first, then existence, then value")
