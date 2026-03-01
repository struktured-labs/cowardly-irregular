# Masterites: Agents of the Curator

## Overview
Masterites are boss enemies stationed by the final antagonist (the meta-aware difficulty curator) across each overworld. They test the player's mastery across 4 combat dimensions, scaling in power as the world progresses.

## The 4 Archetypes

### Warden (Defense Tester)
- **Role:** Tank boss with high HP and DEF. Tests the player's ability to sustain damage and outlast a durable foe.
- **Stat Bias:** High HP, High DEF, Moderate ATK, Low SPD
- **Key Abilities:** masterite_iron_guard, masterite_crushing_blow, masterite_endurance_test, masterite_judgment
- **Counter Strategy:** Debuff defense, use magic/elemental damage, attrition over burst

### Arbiter (Offense Tester)
- **Role:** Glass cannon with devastating single-target and AoE damage. Tests DPS optimization and burst timing.
- **Stat Bias:** High ATK, Moderate HP, Low DEF, Moderate SPD
- **Key Abilities:** masterite_precise_strike, masterite_measured_blow, masterite_counter_stance, masterite_execution
- **Counter Strategy:** Race it down before counter_stance activates, keep everyone healed above execution threshold

### Tempo (Speed Tester)
- **Role:** Speed demon that manipulates turn order. Tests mastery of the advance/defer system.
- **Stat Bias:** Very High SPD, Moderate ATK/MAG, Low HP/DEF
- **Key Abilities:** masterite_haste, masterite_slow, masterite_quick_strike, masterite_time_tax
- **Counter Strategy:** Speed buffs, defer for AP then burst, cleanse speed debuffs

### Curator (Resource Tester)
- **Role:** MP drainer and buff stripper. Tests resource management and MP-efficient builds.
- **Stat Bias:** High MAG, Moderate HP/DEF, Moderate SPD
- **Key Abilities:** masterite_mana_drain, masterite_dispel, masterite_audit, masterite_resource_cut
- **Counter Strategy:** Physical-heavy builds, burst before MP runs dry, bring ethers

## World Distribution

| Phase | Overworld | Level Range | Warden | Arbiter | Tempo | Curator |
|-------|-----------|-------------|--------|---------|-------|---------|
| 1 | Medieval | 6-8 | Warden of the Old Guard | Arbiter of Steel | Tempo of the Hunt | Curator of the Flame |
| 2 | Suburban | 9-11 | Warden of Routine | Arbiter of the Grade | Tempo of the Rush Hour | Curator of the Budget |
| 3 | Industrial | 12-14 | Warden of the Assembly Line | Arbiter of Efficiency | Tempo of the Shift | Curator of the Pipeline |
| 4 | Futuristic | 15-17 | Warden of the Firewall | Arbiter of the Benchmark | Tempo of the Clock Cycle | Curator of the Memory Pool |
| 5 | Abstract | 18-20 | Warden of Form | Arbiter of Function | Tempo of Sequence | Curator of Entropy |

## Stat Scaling

Stats scale ~1.5-2x per phase. HP ranges from 420-550 (Phase 1) to 1100-1400 (Phase 5).

## Shared Properties
- All have `masterite: true` and `masterite_type` fields for programmatic identification
- All use `masterite_proclamation` as opening move (self defense buff)
- All have one-shot challenges with specific strategy hints
- All drop `masterite_shard` (100%) plus phase-specific materials
- All have intro dialogue reflecting the antagonist's purpose

## Narrative Role
Masterites are the antagonist's way of measuring the player before the final confrontation. Each one reports back (narratively) on the player's strengths and weaknesses. By the time the player defeats all 20, the antagonist has a complete profile - setting up the meta-aware final boss fight.

## Drop Materials
- Phase 1-2: masterite_shard
- Phase 2-3: masterite_badge
- Phase 3-4: masterite_core
- Phase 4-5: masterite_circuit
- Phase 5: masterite_prism

## Encounter Method
Masterites appear as overworld boss triggers (Area2D interactables) placed in specific locations on each overworld map. They are NOT random encounters - the player must seek them out.
