extends GutTest

## .775 gate (cowir-main 22580): `_cannot_step(who: Node)` rejected a FREED player at the typed parameter, before its is_instance_valid guard ran, aborting RoamingMonster._process (:305).
## Real exposure: a roamer still processing after its _player_ref is freed by a map change. An elite's aura phase advances only past that check, so a frozen phase means _process aborted.

const RM := "res://src/exploration/RoamingMonster.gd"


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


class HeldPlayer:
	extends Node2D
	var can_move := false
	func set_can_move(v: bool) -> void:
		can_move = v


func _make_elite() -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	var m: Node = load(RM).new()
	m.elite = true
	host.add_child(m)
	return m


## How far one _process tick advanced the elite's aura phase.
func _phase_step(m: Node, delta: float) -> float:
	var before: float = m._aura_phase
	m._process(delta)
	return m._aura_phase - before


func test_a_freed_player_does_not_abort_the_roamer() -> void:
	var m := _make_elite()
	var player := FakePlayer.new()
	add_child(player)
	m.set_player_ref(player)
	player.free()
	assert_false(is_instance_valid(m._player_ref), "PRECONDITION: the roamer must hold a FREED player")
	assert_almost_eq(_phase_step(m, 0.5), 0.5, 0.0001, "a freed player must read as 'can step', so _process runs on past the check")


func test_a_live_player_lets_the_roamer_run() -> void:
	var m := _make_elite()
	var player := FakePlayer.new()
	add_child_autofree(player)
	m.set_player_ref(player)
	assert_almost_eq(_phase_step(m, 0.5), 0.5, 0.0001, "CONTROL: with a live player the probe sees the phase advance")


func test_a_held_player_still_holds_the_roamer() -> void:
	var m := _make_elite()
	var player := HeldPlayer.new()
	add_child_autofree(player)
	m.set_player_ref(player)
	assert_eq(_phase_step(m, 0.5), 0.0, "CONTROL: a held player must still stop the roamer, so the predicate is live after untyping")
