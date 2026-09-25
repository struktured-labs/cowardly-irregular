extends GutTest

## The map avatar is whoever GameState.party_leader_index points at. GameLoop
## applies that person on every area entry and on every leader swap, but only
## through has_method("set_player_appearance") (job-only is the fallback).
## Villages, caves, and overworlds answer. Interiors do not, so the room keeps
## the OverworldPlayer default: a fighter with no customized hair.
##
## What the player sees: make the cleric the leader (even while she is KO'd),
## walk into the chapel, and the figure in the room is still the fighter.
## Swap to the mage without leaving and the figure does not change. The same
## door is how a save that loads inside the room rebuilds the scene.

const ROOMS: Array[String] = [
	"res://src/maps/interiors/BaseInterior.gd",
	"res://src/maps/interiors/HarmoniaChapelInterior.gd",
	"res://src/maps/interiors/ShopInterior.gd",
	"res://src/maps/interiors/InnInterior.gd",
	"res://src/maps/interiors/TavernInterior.gd",
]

var _rooms: Array = []


func after_each() -> void:
	for room in _rooms:
		if is_instance_valid(room):
			room.free()
	_rooms.clear()


func _avatar() -> Node:
	var player = load("res://src/exploration/OverworldPlayer.gd").new()
	add_child_autofree(player)
	return player


func _leader(who: String, job_id: String, hair: Color, alive: bool) -> Combatant:
	var member := Combatant.new()
	member.combatant_name = who
	member.job = {"id": job_id, "name": job_id.capitalize()}
	member.is_alive = alive
	member.max_hp = 100
	member.current_hp = 100 if alive else 0
	var custom := CharacterCustomization.new()
	custom.hair_color = hair
	member.customization = custom
	add_child_autofree(member)
	return member


## The exact gate in GameLoop._start_exploration and _on_party_leader_changed.
func _apply_like_gameloop(scene: Node, leader: Combatant) -> void:
	if scene.has_method("set_player_appearance"):
		scene.set_player_appearance(leader)
	elif scene.has_method("set_player_job"):
		var job_id := "fighter"
		if leader.job is Dictionary:
			job_id = str((leader.job as Dictionary).get("id", "fighter"))
		scene.set_player_job(job_id)


func test_an_interior_shows_the_leader_after_a_swap() -> void:
	var checked := 0
	for path in ROOMS:
		var room = load(path).new()
		_rooms.append(room)
		var avatar = _avatar()
		room.player = avatar
		assert_eq(str(avatar.current_job), "fighter",
			"%s builds the default fighter until GameLoop names the leader" % path)
		assert_false(bool(avatar._use_custom_colors),
			"%s has not picked up a leader's colors yet" % path)

		var fallen := _leader("Mira", "cleric", Color(0.85, 0.15, 0.45), false)
		_apply_like_gameloop(room, fallen)
		assert_eq(str(avatar.current_job), "cleric",
			"a KO'd cleric made leader must be who walks in %s" % path)
		assert_true(bool(avatar._use_custom_colors),
			"her hair has to come with the job, or a customized hero still reads as the generic fighter in %s" % path)
		assert_eq(avatar._custom_hair_color, Color(0.85, 0.15, 0.45),
			"the KO'd leader's hair color is part of the sprite in %s" % path)

		var gone := _leader("Lyra", "bard", Color(0.95, 0.75, 0.2), false)
		gone.status_effects.append("permakilled")
		_apply_like_gameloop(room, gone)
		assert_eq(str(avatar.current_job), "bard",
			"a permakilled bard made leader must be who walks in %s" % path)
		assert_eq(avatar._custom_hair_color, Color(0.95, 0.75, 0.2),
			"permakilled does not keep the previous leader's hair in %s" % path)

		var standing := _leader("Vex", "mage", Color(0.2, 0.35, 0.9), true)
		_apply_like_gameloop(room, standing)
		assert_eq(str(avatar.current_job), "mage",
			"swapping to the mage while still inside %s has to replace the sprite" % path)
		assert_eq(avatar._custom_hair_color, Color(0.2, 0.35, 0.9),
			"the living leader's hair replaces the previous one in %s" % path)
		checked += 1
	assert_eq(checked, ROOMS.size(), "every interior owner was driven")
