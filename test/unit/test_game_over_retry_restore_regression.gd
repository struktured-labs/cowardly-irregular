extends GutTest

## Retry-path audit 2026-07-03: the game-over Retry block hand-rolled
## its restore (is_alive=true + full HP/MP), which (a) carried status
## effects from the losing fight into the retry — poison ticking on a
## "fresh" attempt — and (b) resurrected PERMAKILLED party members,
## a wipe-on-purpose loophole around the tick-421 permadeath promise
## (worse: they came back still wearing the permakilled marker).
## Retry now routes through _restore_duelist, the duel system's
## canonical full restore.

const GameLoopScript = preload("res://src/GameLoop.gd")


func _member(dead: bool, statuses: Array) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "T"
	c.max_hp = 100
	c.current_hp = 0 if dead else 40
	c.is_alive = not dead
	for s in statuses:
		c.status_effects.append(str(s))
	return c


func test_restore_clears_statuses_and_revives() -> void:
	var c := _member(true, ["poison", "curse"])
	GameLoopScript._restore_duelist(c)
	assert_true(c.is_alive, "dead member must revive on retry")
	assert_eq(c.current_hp, c.max_hp)
	assert_false(c.status_effects.has("poison"),
		"losing fight's statuses must not tick on the retry attempt")
	assert_false(c.status_effects.has("curse"))


func test_permakilled_stay_dead_on_retry() -> void:
	var c := _member(true, ["permakilled", "poison"])
	GameLoopScript._restore_duelist(c)
	assert_false(c.is_alive,
		"permadeath survives a wipe-and-retry — the old brute is_alive=true was a loophole")
	assert_true(c.status_effects.has("permakilled"),
		"the marker itself must survive the restore's status strip or a later Raise undoes permadeath")
	assert_false(c.status_effects.has("poison"),
		"ordinary statuses still clear even on a permakilled member")


func test_retry_block_uses_canonical_restore() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var block: int = src.find("# Retry the same battle with the same enemy formation")
	assert_gt(block, -1)
	var window: String = src.substr(block, 700)  # widened 2026-07-18: boss-spec re-arm lines now precede the restore loop
	assert_true(window.contains("_restore_duelist(member)"),
		"retry must route through the canonical restore, not a hand-rolled heal")
	assert_false(window.contains("member.is_alive = true"),
		"raw is_alive=true is the permadeath loophole")
