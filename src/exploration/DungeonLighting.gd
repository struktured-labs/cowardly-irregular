class_name DungeonLighting
extends VillageLighting
## A cave has no sky. Same lamp machinery as the village rig, but the ambient is fixed
## per-dungeon instead of tracking the day clock — walking into a cave at noon must not
## light it like a meadow.

const CAVE_AMBIENT := Color(0.30, 0.29, 0.42)

var ambient: Color = CAVE_AMBIENT


## Deliberately ignores day_phase AND phase_override: underground is underground. The
## screenshot tool pins a phase on every scene it loads, and a cave must not answer to it.
func tint_now() -> Color:
	return ambient
