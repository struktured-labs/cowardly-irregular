extends DragonCave
class_name LightningDragonCaveScene

## Stormspire Cavern — Lightning Dragon Voltharion awaits on Floor 3.
## Storm-carved halls, three floors (parity with Fire/Ice/Shadow — pre-2026-07-18
## Lightning was 2-floor, and struktured called the arrangement "silly"
## because the dragon sat almost at the entry: msg 2788).

func _init() -> void:
	cave_name = "Stormspire Cavern"
	cave_id = "lightning_dragon_cave"
	boss_id = "lightning_dragon"
	boss_flag_key = "lightning_dragon_defeated"
	boss_cutscene_id = "world1_voltharion_intro"
	total_floors = 3
	overworld_exit_spawn = "lightning_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMM..........MMM.M",
			"M.M..............M.M",
			"M.M.T..MMMMMM....M.M",
			"M.M....M....M....M.M",
			"M.M....M.T..M...TM.M",
			"M......M....M......M",
			"M......MMMMMM......M",
			"M..................M",
			"M....MM......MM....M",
			"M....M....U...M....M",
			"M....MM......MM....M",
			"M.T.....DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		# Storm-lattice mid floor: open central chamber, tesla-coil pillars,
		# encounters continue. Mirrors Ice/Shadow floor-2 shape so the class
		# reads the same.
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..T...........T...M",
			"M..MMMM.....MMMM...M",
			"M..M....T......M...M",
			"M..M...........M...M",
			"M..MMMM.....MMMM...M",
			"M..................M",
			"M......MM.MM.......M",
			"M.......M..M...T...M",
			"M.......M.UM.......M",
			"M......MM.MM.......M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: _boss_floor_layout(),
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12)},
		2: {"down_stairs": Vector2(10, 14)},
		3: {"down_stairs": Vector2(10, 14)},
	}

	floor_encounter_pools = {
		1: ["goblin", "bat", "skeleton"],
		2: ["goblin", "bat", "skeleton"],
		3: [],
	}


## Shared boss-floor layout — struktured msg 2788: "why is the dragon at
## the very beginning of the cave?" Winding path from the south entry
## (D) to a far-corner boss (B at the top-right), with 4 T treasures on
## the path — two inside the walled north chamber (accessible via a gap
## in the chamber's south wall, a gap in the chamber's north wall for
## the boss corridor, or the east-side corridor). All 4 dragon caves
## share this shape now; the flavor + boss id is per-subclass.
static func _boss_floor_layout() -> Array:
	return [
		"MMMMMMMMMMMMMMMMMMMM",
		"M...............B..M",
		"M..................M",
		"M..MMMMMMM.MMMMMMM.M",
		"M..M.T...........M.M",
		"M..M.............M.M",
		"M..M.......T.....M.M",
		"M..M.............M.M",
		"M..MMMMMMM.MMMMMMM.M",
		"M..................M",
		"M....MMMMM.MMMMM...M",
		"M....M.........M...M",
		"M....M....T....M...M",
		"M..T.M.........M...M",
		"M.........D........M",
		"MMMMMMMMMMMMMMMMMMMM",
	]


func _get_boss_intro_dialogue() -> Array:
	return [
		"Static fills the air. Your hair stands on end.",
		"Lightning arcs between stalactites like a tesla coil.",
		"",
		"Voltharion: 'FINALLYFINALLYFINALLYFINALLY!!!'",
		"Voltharion: 'Do you KNOW how BORING it is waiting?!'",
		"Voltharion: 'I've been counting milliseconds!'",
		"Voltharion: '847,293,461 of them! Give or take!'",
		"",
		"Hero: 'Slow down, I can barely--'",
		"",
		"Voltharion: 'SLOW?! SLOW IS FOR CPUS WITH THERMAL THROTTLING!'",
		"Voltharion: 'I run at CLOCK SPEED baby!'",
		"Voltharion: 'Speaking of which--'",
		"Voltharion: 'Your turn timer starts NOW!'",
		"Voltharion: 'Actually it started 3 lines ago!'",
		"Voltharion: 'YOU'RE ALREADY BEHIND!'",
		"Voltharion: *crackles with barely contained energy*",
	]
