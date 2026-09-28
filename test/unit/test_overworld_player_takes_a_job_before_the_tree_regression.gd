extends GutTest

## Regression: every overworld, village and dungeon `_setup_player` calls `player.set_job(...)` BEFORE
## `add_child(player)`. `_update_sprite` then wrote `_sprite.texture` while `_sprite` was still null
## (it was built in `_ready`), and struktured's play logs carried
## `SCRIPT ERROR: Invalid assignment of property or key 'texture' ... on a base object of type 'Nil'`
## at `OverworldPlayer._update_sprite` on every overworld load — 24 times across the two logs of
## 2026-09-26. `_ready` repainted, so nothing showed; the cost was an error line per scene load.
##
## A script error inside a callee is contained there and GUT sees nothing, so the arm below does not
## look for the error: it asserts the contract the scenes rely on — the avatar exists and is painted
## as soon as it is given a job, whether or not it is in the tree yet.

const PlayerScript := preload("res://src/exploration/OverworldPlayer.gd")


func _sprites_of(player: Node) -> Array:
	var out: Array = []
	for c in player.get_children():
		if c is Sprite2D:
			out.append(c)
	return out


func test_a_job_set_before_the_tree_paints_the_avatar() -> void:
	var player = PlayerScript.new()
	# The order every _setup_player uses; "bard" differs from the "fighter" default so set_job repaints.
	player.set_job("bard")
	var sprite := player.get_node_or_null("Sprite") as Sprite2D
	assert_not_null(sprite, "set_job before add_child had no sprite to paint — the scenes' own order")
	if sprite:
		assert_not_null(sprite.texture, "the avatar was given a job but no frame")
	player.free()


func test_entering_the_tree_keeps_one_avatar_sprite() -> void:
	# Guards the fix: building the sprite earlier must not leave _ready building a second one.
	var player = PlayerScript.new()
	player.set_job("bard")
	var before = player.get_node_or_null("Sprite")
	add_child_autofree(player)
	var sprites := _sprites_of(player)
	assert_eq(sprites.size(), 1, "the avatar must have exactly one Sprite2D after _ready")
	if sprites.size() == 1:
		assert_not_null((sprites[0] as Sprite2D).texture, "the avatar lost its frame entering the tree")
		if before:
			assert_same(sprites[0], before, "_ready replaced the sprite set_job painted")
