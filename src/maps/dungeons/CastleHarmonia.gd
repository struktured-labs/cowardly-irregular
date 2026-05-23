extends DragonCave
class_name CastleHarmoniaScene

## Castle Harmonia — Throne Room of Chancellor Mordaine
##
## W1 final boss arena. Reuses the DragonCave base (single-floor variant)
## because the boss-trigger / cutscene / flag-set machinery is identical.
## Mordaine herself is narratively the W1 keystone — defeating her sets
## `cutscene_flag_world1_mordaine_defeated`, which gates the W2 prologue
## cutscene.
##
## Map layout: a stone throne room. No random encounters (boss arena —
## floor_encounter_pools is empty). The throne sits at top-center; boss
## spawn point is just south of it. Two side alcoves contain torches
## for atmosphere. Single staircase D leads back to the overworld.

func _init() -> void:
	cave_name = "Castle Harmonia — Throne Room"
	cave_id = "castle_harmonia"
	boss_id = "chancellor_mordaine"
	boss_cutscene_id = "world1_mordaine_intro"  # Full intro plays before fight
	boss_flag_key = "world1_mordaine_defeated"
	total_floors = 1
	overworld_exit_spawn = "castle_entrance"

	# Setting unlock_world ties victory to W2 unlock via GameLoop's
	# pending_boss_defeat handler — matches the dragon-cave pattern.
	unlock_world = 2

	# Single floor layout — 20×16 grid. `M`=wall (stone), `.`=floor,
	# `T`=torch decoration, `B`=boss spawn marker, `D`=down stairs
	# (exit back to overworld).
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..T............T..M",
			"M..................M",
			"M..MMMM........MMMM.M",
			"M..M..............M.M",
			"M..M......B.......M.M",
			"M..M..............M.M",
			"M..M..............M.M",
			"M..MMMM........MMMM.M",
			"M..................M",
			"M..T............T..M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	# Player spawns at the south-center entrance (the stair tile),
	# facing north toward the throne.
	floor_spawn_points = {
		1: {
			"entrance": Vector2(10, 14),
			"castle_entrance": Vector2(10, 14),
		},
	}

	# Boss arena — no random mobs. The throne fight IS the encounter.
	floor_encounter_pools = {
		1: [],
	}
