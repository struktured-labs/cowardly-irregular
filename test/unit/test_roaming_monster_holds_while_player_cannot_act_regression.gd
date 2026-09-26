extends GutTest

## A field monster keeps chasing a player who cannot step aside, then starts the fight on contact.
##
## Reading a landmark pushes an input lock (ReadableProp). Talking to a world-map wanderer
## sets can_move false and pushes nothing. Opening the menu, the autobattle editor, or a
## staged overworld cutscene does the same through OverworldPlayer._can_move(). World 1's
## menu also despawns the spawner; the other holds do not, and Worlds 2-6 never despawn on
## pause. The monster walks into the frozen player. Contact starts a battle (the readable's
## own comment records that sequence — the lock leak on teardown was fixed, the fight was
## not), or the contact is swallowed because a menu or cutscene blocks it and the monster
## is left overlapping when control returns.
##
## OverworldPlayer._can_move() is the predicate the sprite already obeys. A stand-in with
## neither that method nor a can_move flag is free to be chased, which is what the older
## roamer tests rely on.


const RM := "res://src/exploration/RoamingMonster.gd"


class HeldPlayer:
	extends Node2D
	var held: bool = true
	func _can_move() -> bool:
		return not held
	func set_can_move(_v: bool) -> void:
		pass


func _make_pair(held: bool) -> Dictionary:
	var host := Node2D.new()
	add_child_autofree(host)
	var monster: Node = load(RM).new()
	host.add_child(monster)
	var player := HeldPlayer.new()
	player.held = held
	add_child_autofree(player)
	player.global_position = Vector2(50, 0)
	monster.global_position = Vector2.ZERO
	monster.set_player_ref(player)
	monster._state = 2
	monster._mood = monster.Mood.ANGRY
	monster._active = true
	monster._fading = false
	return {"monster": monster, "player": player}


func test_a_chasing_monster_holds_still_while_the_player_cannot_act() -> void:
	var held := _make_pair(true)
	var monster: Node = held["monster"]
	assert_false(held["player"]._can_move(),
		"PRECONDITION: the held player reports it cannot move")
	var start: Vector2 = monster.global_position
	for _i in range(10):
		monster._process(0.1)
	assert_eq(monster.global_position, start,
		"a monster closed %.1fpx on a player who cannot move" % start.distance_to(monster.global_position))

	# CONTROL: the same chase, with the player free, must move — or the assert above
	# is satisfied by a dead _process rather than by the hold.
	var free := _make_pair(false)
	var roamer: Node = free["monster"]
	assert_true(free["player"]._can_move(),
		"CONTROL PRECONDITION: a free player must still be chaseable")
	roamer._process(0.1)
	assert_gt(roamer.global_position.x, 0.0,
		"CONTROL: an angry monster did not step toward a player who can move")


func test_contact_does_not_start_a_fight_while_the_player_cannot_act() -> void:
	var held := _make_pair(true)
	var monster: Node = held["monster"]
	var fired := [0]
	monster.touched.connect(func(_id, _types, _elite): fired[0] += 1)
	assert_false(held["player"]._can_move(),
		"PRECONDITION: contact is being judged against a player who cannot move")
	monster._on_body_entered(held["player"])
	assert_eq(fired[0], 0,
		"contact started a fight while the player could not step aside")

	# CONTROL: the same touch, once the player can move, must still start the fight.
	held["player"].held = false
	assert_true(held["player"]._can_move(),
		"CONTROL PRECONDITION: releasing the hold must make the player chaseable again")
	monster._on_body_entered(held["player"])
	assert_eq(fired[0], 1,
		"CONTROL: an ordinary touch stopped starting fights for a player who can move")
