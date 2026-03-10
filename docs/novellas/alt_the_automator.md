# The Automator

## An Alternate Playthrough — Mage/Rogue Lead, Heavy Autobattle

---

> *"The question is never whether the system can be solved. The question is how quickly you can prove it."*

---

### Prologue: A Pattern Is Already a Problem Solved

The notice went up at dawn.

Mira read it once, noted the structural irregularity in the bureaucratic phrasing — *Royal Bureau of Definitely Real Military Operations* was not how functioning governments named themselves; either this was theater or the kingdom was in more trouble than it looked — and turned to her notebook.

She had been in Harmonia for eleven days. She had come through on the trade road from Veldmoor, following a specific anomaly in the monster population distribution: the rate of goblin sightings per square kilometer had increased by three hundred percent in under a month, and the spatial distribution of the increase was non-random. The expansion was directional. Something was pushing them south.

She had come to find the source. Elder Theron had not been the source. The cave to the north, however, was a promising candidate.

So when the others arrived in the square — the Fighter with his untested sword and his polished convictions, the Cleric with his sandals and his impractical faith, the Rogue who appeared to have been physically pointed at this gathering by someone who had caught him sleeping — she was already there. Already noting things. Already with three more pages written than anyone else.

"A party of five," said the Bard, who had apparently materialized from the general air of narrative possibility. He was composing the sentence about them before they'd had a chance to become it. "A valiant knight, a servant of the cloth, a woman of arcane learning—"

"Science Nerd," said Scholar Milo, who had appeared at her elbow. "That's the trajectory. Not yet, but eventually."

"Mage," Mira said. "Currently."

"The distinction will resolve by World 2." He adjusted his spectacles. He had the look of a man who had said things prematurely many times and had long since stopped regretting it. He pressed a journal into her hands. "Before you go — have you considered the philosophical implications of combat automation?"

Mira had. Specifically: if combat was a system — inputs, outputs, conditionals, resource states — then fighting was analysis wearing a physical costume. The interesting problem wasn't the fight itself. It was the design of the response.

"Chapter three," she said, flipping to it without ceremony.

Milo blinked. "Most people start at chapter one."

"Chapter one is about letting go. I don't need to practice letting go. I need to understand the formal structure of the release mechanism." She read the opening paragraph of chapter three. Then read it again. Then said, quietly, "This is a conditional tree. You've built an autobattle system out of prose."

"I built it out of experience," Milo said. "You'll build it out of theory. Both arrive at the same place." He paused. "Different journeys, though. Very different journeys."

He walked away before she could ask what that meant. She wrote it down instead, with a small asterisk, because asterisked notes were things she expected to understand later.

The Fighter — his name, she had learned, was Hero, which she suspected was either aspirational or literally his name, and in either case was statistically improbable — was looking at her.

"Are you writing in your journal right now?" he asked.

"Yes."

"About this? About us?"

"About the system." She finished the note. "You're all inputs to the system. I'm not being reductive. Inputs are important. You can't build a model without data."

The Bard was already composing the part about her. She could tell because his quill hand had taken on a particular angle that preceded narration. She preemptively added: *Bard: documenting. Note: the Bard will document everything. Do not attempt to prevent the documenting. It is load-bearing for the morale structure of the group.*

"What's load-bearing for morale?" Hero asked, reading over her shoulder.

She hadn't realized he was close enough to read it. She made a note about maintaining greater spatial awareness of the Fighter.

"You are," she said honestly. "You and Zack."

The Cleric — Zack — looked up from his blessing of the equipment. "I've been included in a system," he said, with the gentle pleasure of a man who finds inclusion anywhere a blessing.

"Everyone is part of a system," Mira said. "The relevant question is whether the system knows what it's doing."

She opened the autobattle journal to chapter three and began designing their first script.

---

### Chapter 1: World 1 — The Usurper's Crown

#### *Medieval. 8-bit. The Mage in the first world.*

---

Her first autobattle script was eleven lines.

She wrote it in the margin of the autobattle journal during the walk north to the Whispering Cave, in shorthand she had invented on the spot because no existing notation system captured exactly what she needed. It looked like this:

```
// Script v1.0 — Harmonia Road
IF HP(self) < 40% AND Heal(Zack).ready → Zack: Heal(target=self)
IF HP(any_ally) < 30% → Zack: Heal(target=lowest_HP)
IF MP(self) > 60% → self: Fire(target=highest_threat)
IF MP(self) ≤ 60% AND ATK(Vex) > 12 → Vex: Strike(target=highest_defense)
DEFAULT → Hero: Attack(target=highest_threat)
```

"That's a poem," said the Bard, reading over her shoulder. He had a gift for appearing over shoulders that was either a social skill or a minor supernatural ability; she had not ruled out the latter.

"It's a decision tree."

"It has rhythm. Rule-then-resolution, rule-then-resolution, then a final default. That's verse structure."

"It's conditional logic."

"Poetry is conditional logic about feelings," he said. "You've written conditional logic about combat. The difference is the subject."

She was going to argue this, but Hero had reached the first slime, and the script activated, and she watched instead.

This was the part she found genuinely interesting: watching the script run.

Not the combat itself. The combat was the output, and outputs were less interesting than the process that produced them. What she watched was the decision tree — the sequence of evaluations, the moment when a condition triggered and the corresponding action executed, the information state that had led to each choice. She watched Zack heal when her HP dipped, watched Vex strike when her MP dropped, watched Hero cover the default cases with reliable physical output. The script ran clean. No decision points uncovered. No resource leakage.

"You're not fighting," Hero said. He was doing it himself — manually, earnestly, sword connecting with goblin with the specific impact of a man who wanted to feel the contact.

"I designed the strategy. That IS fighting."

"You're watching."

"I'm observing," she said. "There's a difference. Watching is passive. Observing is data collection."

He hit another goblin. The goblin had a threat value of approximately 3 on a scale where the scale's upper limit was unknown but the sample mean so far was around 4. Hero's strike value was 14. The encounter was within expected parameters.

"You're not *here,*" Hero said, in a tone that contained something he hadn't fully named yet. Something frustrated and protective and unable to explain itself to someone who found frustration an unproductive state.

"My body is here. My analysis is here. My strategy is executing here." She watched the script complete a full cycle. "What part of me would you like that isn't currently present?"

He didn't answer. She wrote down that he hadn't answered, with an asterisk.

---

The Warden of the Old Guard was the first genuine test of the script.

She ran three iterations of Script v1.0 against the Warden before conceding that the threat profile exceeded the script's design parameters. The Warden hit harder than predicted. Its attack pattern had a delayed second strike that fell after her script's heal trigger evaluated but before the damage resolved, which meant heal timing was wrong by approximately one phase.

She pulled out the journal. Rewrote lines 1 and 2. Added a pre-emptive heal trigger at 55% HP to account for delayed second-strike windows. Added a defensive fallback for Hero — defer trigger when his HP crossed a threshold, to reduce incoming damage and buy Zack's heal another cycle.

Script v1.1. She fed it back to the party.

"You rewrote it," Hero said.

"I patched it. The original was correct for the encounter data available when I wrote it. The data has been updated."

"We're in the middle of a fight."

"The script is running," she said. "Pause your concern. Watch the output."

The output was: Zack's heal landed a full phase earlier. Hero's defer triggered correctly. The Warden's delayed second strike hit a defense value instead of a health value. The damage absorbed was fourteen percent of its unchosen alternative.

"Better," she said.

"Fourteen percent," Hero repeated, with the tone of a man computing what fourteen percent represents in physical terms and not being entirely satisfied by the answer.

"Fourteen percent is significant. Scaled across the expected encounter volume, fourteen percent is the difference between reaching Scriptura with full consumable reserves and arriving at sixty percent." She finished the annotation. "Every optimization compounds."

The Warden, to its credit, adapted partway through the fight. It changed its targeting — shifted from Mira to Hero, which her script hadn't anticipated because she'd modeled targeting as static. She made a note. *Assumption failure: enemy targeting is not static. Masterites may be responsive. Build adaptive response into v1.2.*

The Warden hit Hero with enough force to push him into critical HP territory. Her script hadn't covered a scenario where the tank was the primary damage target, because she'd indexed threat by offensive capability rather than tactical positioning. The resulting coverage gap lasted three phases while Zack scrambled to respond manually, outside the script.

"A little help?" Hero said, through his teeth.

"The script failed on a targeting assumption. Manual correction underway. One moment."

"One moment," he repeated. The Warden raised its weapon for another strike. "In one moment I'm going to be a statistic in your notebook."

"You're already a statistic in my notebook." She pushed a heal directive through. "HP restored. Continue."

He continued. The fight resolved. She immediately sat down on the cave floor and opened her notebook.

*Script v1.2 requirements: Dynamic threat modeling. Targeting pattern recognition. Fallback manual override for novel encounter states. Build redundancy.*

The Warden, in its final moments, had said something she had been too busy designing to fully process. She reviewed it now from memory: it had looked directly at her — not at Hero, not at Zack, but at her, sitting off to the side with the journal — and it had said, in a voice that was granite and gravity, each word carrying the weight of something that had been a guardian for a very long time:

*"You sent your soldiers but you did not come yourself. A true commander stands in the field."*

She had replied: "I designed the strategy. That IS coming myself."

The Warden had been quiet for a moment. Then it had said something she had written down verbatim because it didn't fit a clean category: *"Then you are present everywhere and nowhere. I wonder which of those you'll find harder to live with."*

She looked at the quote in her notebook. She gave it an asterisk. Then a second asterisk, because one felt insufficient.

The cave corridor beyond the Warden led deeper. Court magic. Deliberate corruption. Someone had been feeding this. She documented the evidence, cross-referenced the magic traces with what she knew of Scriptura's court practices, and arrived at a hypothesis with approximately eighty-two percent confidence before the rest of the party had finished catching their breath.

"Mordaine," she said.

"You know this already?" the Bard said.

"I have a working model. The evidence supports it. I'd give it eighty-two percent."

"That's not knowing," Hero said.

"It's close enough to act on," she said. "The remaining eighteen percent is the margin I preserve for data I haven't collected yet." She closed the notebook. "Forward. I need more data."

---

She would remember Mordaine later — specifically the way Mordaine had looked at her autobattle party and smiled with the particular expression of a bureaucrat confronted with a system they hadn't approved, and said: *"You're not even HERE, are you? Your bodies fight, but your mind is elsewhere."*

And she had said: "My mind is where it needs to be to win."

And Mordaine had said: "Yes. I suppose it is." And something in that agreement had been discomforting, as if Mordaine were conceding a truth that she would have preferred to remain unknown.

She gave it a third asterisk.

The world ended, as worlds do when their phase completes: with a shimmer, a step, and sidewalk.

---

### Chapter 2: World 2 — The Neighborhood Problem

#### *Suburban. 16-bit. The Mage evolves to Science Nerd. The Rogue secondary becomes Skater Kid instinct.*

---

The transformation happened in transit. She came out the other side in jeans and a university t-shirt, carrying a backpack whose contents included a scientific calculator, four spiral-bound notebooks, and a small container of something labeled EVIDENCE — DO NOT EAT, because some habits transcended genre.

The calculator, when she turned it on, still felt like fire.

Good. The core was intact.

The first thing she noticed about Maple Heights was the distribution anomaly: every lawn was precisely the same height. Not approximately. Precisely. Within a margin that implied either an extraordinary coincidence of independent gardening choices or a single centralized enforcement mechanism.

"Someone standardized the trees," Zack said.

"Someone standardized everything," she said. "The trees, the houses, the lawn height. The street naming convention follows a pattern — all deciduous trees, alphabetical by common name. The spatial distribution of house types follows a demographic optimization model. This is not organic development. This is imposed regularity."

"The HOA," said a man in cargo shorts, watering his lawn without looking up.

She turned to him. "The HOA has enforcement mechanisms?"

"The HOA has enforcement mechanisms," he confirmed, with the tone of a man who has spent considerable time in the presence of those mechanisms and has arrived at a state of resigned acceptance.

She wrote this down. *HOA: governing structure. Enforcement mechanism: ?. Enforcement philosophy: standardization, compliance, deviation intolerance. Cross-reference: Mordaine. Note: same governance pattern, different aesthetic. Probability of connection: examining.*

The strip mall was where it got interesting.

She was there for the Ye Olde Medieval Surplus because she'd noted the anomaly from two blocks away — a medieval-theme shop had no natural emergence path in a suburb whose other retail options were pizza, dry cleaning, candles, and frozen yogurt — and anomalies were always worth walking toward.

The items were from Harmonia. Not similar. The same. She picked up a potion with Bram's specific label typeface and turned it over. The lot number was the same lot number as the potion she'd purchased three days and one world ago.

She stood with the potion for thirty seconds. Then she said: "Inventory persistence."

The teenager in the vest looked up from her phone. "What?"

"Your inventory persists across the transition. Items from World 1 are appearing in World 2 retail context. The supply chain is cross-world. Either there's a continuous trade system I haven't modeled, or —" She set the potion down. "Or the inventory is being maintained by something external. Something that exists in the space between worlds."

"Cool," said the teenager, returning to her phone.

But the Coordinator's office was the real data.

She found it on the second day, after triangulating the HOA's enforcement pattern — complaints filed from block seven, block seven proximity to the central administration office, the specific timing gap between observed compliance violations and enforcement response — and simply walking to where the data pointed.

The office had a monitor. One monitor, facing the wall, which was either careless or deliberate concealment from a direction the Coordinator hadn't expected someone to approach from. She approached from that direction.

The monitor showed data. Specifically: encounter rates, HP statistics, script execution logs, and a column she had not expected to see, labeled with terminology that did not belong in any suburb.

*PARTY_ENCOUNTER_TOTAL: 847*
*PARTY_AUTOBATTLE_PCT: 94.3%*
*LEAD_COMBAT_PARTICIPATION: 3.1%*
*SCRIPT_COMPLEXITY_SCORE: 14.7 (HIGH)*

She stood in front of the monitor for a long time.

The rest of the party was outside. She was aware that Hero would probably say she was "watching instead of doing" again, and she would have to explain again that watching was its own form of doing, and he would look at her with the specific frustration of a man who understood the words but not the argument. That conversation could wait.

The data on the monitor was impossible in the specific way that things are impossible before you revise your model of what's possible. Someone was tracking them. Someone had been tracking them since World 1. Someone had built a data collection apparatus that had been running in the background of their entire journey, and this — this suburban world, this HOA, this Coordinator — was where she was seeing the readout.

She took out her notebook. She didn't write notes. She transcribed. Everything. Column by column, row by row. The party's statistics. The script complexity scores. The encounter data. The timestamps.

The timestamps were in World 1 date format.

The system had been running since before the portal.

She turned the problem over. Examined it from the base assumptions.

*Assumption: the worlds are independent adventures, sequentially experienced.*
*Data contradicting assumption: continuous tracking system across both worlds. Cross-world inventory. Shared data architecture.*
*Revised model: the worlds are not independent. The worlds are a sequence designed by something that exists outside them. Something that observes the sequence.*

She thought about Mordaine. About the governance pattern. About the specific phrasing — *order requires control, the system must be maintained* — that she had categorized at the time as generic antagonist philosophy and was now cross-referencing with the Coordinator's bureaucratic absolutism and finding a discomforting degree of overlap.

*Hypothesis: the antagonists are not separate entities. The antagonists are expressions of a single function.*

She gave this hypothesis a confidence of sixty-one percent. High enough to act on. Low enough to require more data.

She needed to find the Coordinator.

---

Hero was sitting on the front steps of the office when she came out.

"You were in there for forty-five minutes," he said.

"I was doing analysis."

"Of what?"

"The system we're in." She showed him the page. He looked at the numbers with the expression he got when she showed him numbers — a focused blankness that meant he understood what numbers were but did not immediately understand why she was excited about these particular ones.

"Someone's watching us," he said.

"Someone's been watching us since before we went through the portal."

He was quiet. She watched him process it — not the data, but the feeling. Hero processed feelings, which was inefficient but appeared to be necessary for him to function. She'd built a model for this: the processing lag between when Hero received information and when he was ready to act on it was approximately ninety seconds when the information was tactical, and four to six minutes when the information was existential.

She waited.

After four minutes, he said: "Does this mean the whole thing is designed? The cave. Mordaine. Everything?"

"I don't know who designed it. I don't know why. I know it's being tracked, and the tracking is centralized, and the centralization points toward a single entity." She closed the notebook. "The Coordinator is the local mask. Not the source."

"How do you know that?"

"Because governance patterns don't emerge independently with this degree of philosophical consistency. Mordaine and the Coordinator share a core framework. The probability of independent development of identical governing philosophy is vanishingly small. They're the same entity wearing contextually appropriate clothing."

"That's..." He worked through it. "That's a very cold way to describe someone being in multiple places at once."

"It's an accurate way."

He looked at her for a moment with the expression that contained the thing he hadn't fully named yet. "You're amazing at this," he said. "At reading systems. At seeing the thing behind the thing. I want you to know I see that."

"Thank you."

"But," he said, and she'd been expecting the *but*, "there's a kid in this neighborhood whose bicycle got confiscated by the HOA because it wasn't the approved color. She's nine. She's been crying about it for three days. Vex knows about it because he spent the morning talking to people instead of reading data." He stood up. "The system analysis matters. The nine-year-old also matters. I'm not saying one is more important. I'm saying you haven't been in the same room as her."

She wrote this down. Hero + Zack: manual engagement with local population. Vex: social information gathering. Bard: chronicling. Self: data analysis.

"The bicycle is probably an enforcement case," she said. "If we resolve the Coordinator, the bicycle gets returned."

"Probably."

"The efficiency of resolving the root cause is higher than—"

"That's not the point," he said, not unkindly. "The point is she's nine. The point is being there."

She added a fourth asterisk to the quote from the Warden. *Then you are present everywhere and nowhere.*

She thought about being nine. About what it would mean to have something taken, and to cry about it for three days, and to have the person who was going to fix it say *I am optimizing for root cause resolution* from a monitor room forty-five minutes away.

She didn't write anything else.

---

Script v2.0 had twenty-three lines.

She'd built it from the World 2 encounter data, which was substantially stranger than World 1 — sentient lawn mowers had variable attack patterns based on lawn health state, which was a model variable she hadn't anticipated, and HOA drones had a shield mechanic that only activated when compliance violation flags were active in their behavior state. This required dynamic flag tracking in the script, which required a new notation system, which she built over two evenings in the inn.

The Bard watched her build it. Not writing. Just watching.

"You know," he said eventually, "the script is getting beautiful."

She looked up. "It's getting accurate."

"Same thing, maybe. Beauty in functional systems is a sub-case of beauty generally. The elegance of a well-designed conditional tree — the way each rule anticipates a failure mode and routes around it — that's the same aesthetic principle as a well-written stanza." He picked up the journal, looked at the notation. "Do you read it when you're done? For pleasure?"

"I read it to verify correctness."

"Has correctness ever given you pleasure?"

She thought about the Warden fight. Script v1.1. Watching the pre-emptive heal land exactly where it needed to. The fourteen percent. The clean execution of a design she'd built in a cave corridor under time pressure.

"Yes," she said.

"Then you read it for pleasure," he said, handing it back. "You just call it verification."

She was going to say that there was a meaningful distinction between pleasure and verification, but she found herself unable to complete the argument without relying on a premise she wasn't certain she could support.

She gave the Bard's observation an asterisk. She gave it a second one because she was running out of single-asterisk things.

---

The Coordinator's defeat was clean. Script v2.0 handled it in two phases, adapting to the bureaucratic shield mechanic with a compliance-flag suppression trick that Vex had surfaced while socially investigating the neighborhood — apparently the enforcement mechanism had a reset vulnerability if you filed three simultaneous counter-complaints in the same tick. She built this into the script as a conditional. It worked.

The Coordinator dissolved in the specific way of someone whose function has been terminated rather than someone who has been defeated. There was a glitch — brief, almost subliminal — in which the Coordinator's face slipped, and underneath it was something that had Mordaine's eyes.

She wrote: *Mask slip observed. World 2 antagonist and World 1 antagonist share facial geometry. Confidence in unified-entity hypothesis: 78%. Updating.*

And then the world transitioned: cobblestones, steam, gears, the smell of hot brass.

---

### Chapter 3: World 3 — The Regulator

#### *Steampunk. 32-bit. The Mage evolves to Alchemist. Suspicion accumulates.*

---

She knew by the end of the first hour.

Not suspected. Knew. The unified-entity hypothesis had been at seventy-eight percent when she arrived in Brasston. Within sixty minutes of engaging with the clockwork world, she'd found three additional data points:

First: the Regulator's governance vocabulary. *Acceptable parameters. Tolerance thresholds. Deviation correction.* She had a vocabulary cross-reference in her notebook. The overlap with Mordaine's speech patterns was sixty-seven percent. The overlap with the Coordinator's bureaucratic directives was seventy-one percent. The compound probability of three independent entities sharing this level of linguistic consistency was approximately zero.

Second: Brigadier Flux, the retired engineer, had said the Regulator arrived knowing every pipe, every gear, as if they'd *designed* it. She'd heard similar things in World 1 — Mordaine had arrived knowing every court procedure, every political lever. And the Coordinator had known the neighborhood's enforcement history back to its founding. In each world, the antagonist arrived already knowing the system.

Because they built it.

Third: the Grand Mechanism's blueprints. She had been the only one who immediately moved toward the technical documentation rather than away from the fight. While the party battled the Warden of the Mainspring, she stood at the blueprint station and read. The blueprints were in three handwriting styles. One was angular and precise — the Regulator's. One was an elegant cursive she recognized from a letter she'd found in Mordaine's study. And one was standardized block print that matched the HOA compliance notices she'd photographed with her scientific calculator.

The same entity. Three handwriting styles, one for each mask, each contextually appropriate.

Ninety-six percent confidence.

She wrote it down. Then she walked to where Hero was catching his breath after the Warden fight and said: "I know who the antagonist is."

He looked at her. "Mordaine?"

"The same entity that was Mordaine. That was the Coordinator. That is the Regulator." She showed him the cross-reference. "One entity, three contextual performances. The mask changes. The function doesn't."

He looked at the cross-reference for a long time. Then he looked at her. "How did you figure this out?"

"Vocabulary analysis. Linguistic consistency probability. Handwriting forensics on the blueprints." She paused. "And the monitor in the Coordinator's office. The tracking system. It predates all three worlds, which means the entity running it predates all three worlds. The worlds are its project. We are its..." She searched for the word. "Its subjects."

"That's not comforting."

"No."

He was quiet for the four-to-six minutes that existential information required for processing. Then: "Are you scared?"

She considered it genuinely. "I'm interested," she said. "Scared is a response to threat magnitude. The entity has had two full worlds to harm us and hasn't. It's testing, not threatening. The question is: what is the objective function? What are we being tested for?"

"Does the objective function matter if the test is real?"

"The objective function determines everything." She closed the notebook. "If it's calibrating difficulty — tuning the worlds to be appropriate challenge — then it believes challenge has value. If it's calibrating us — learning about us specifically — then we're the variable, not the worlds. If it's calibrating itself—" She stopped.

"If it's calibrating itself, then what?"

She thought about the monitor. About the *SCRIPT_COMPLEXITY_SCORE: 14.7 (HIGH).* About the specific choice to track script complexity, which was a metric that told you nothing about combat outcome and everything about the design intelligence behind the combat execution.

"Then it finds us interesting," she said. "And interesting is the most dangerous thing to be."

---

The Regulator's chamber was at the heart of the Grand Mechanism, and the Regulator had their stats.

Not approximations. Not estimates. Exact values, with timestamps and confidence intervals. The Regulator read them aloud in the manner of a performance review, which was either the most menacing thing that had happened across three worlds or the most accurate mirror she'd looked into.

"Eighty-three days of active play. Nine hundred and forty-seven encounters. Autobattle engagement: ninety-four point three percent. Script revision count: thirty-one. Mean time between script revisions: two point seven days. Script complexity trajectory: linear increase." The Regulator looked at her over the data. "You are the most statistically interesting subject I have encountered."

"You tracked script complexity," she said.

"Of course."

"Why? It's not a combat performance metric. It doesn't predict encounter outcomes."

The Regulator smiled. It was the smile of someone who had been waiting for this question. "No. But it predicts *you.* The complexity of your decision trees is a measure of your model of the world. Every new conditional you add is a new thing you've understood. Your script history is your intellectual biography." The smile became something sharper. "I find intellectual biographies more informative than damage output."

"You know about the unified-entity hypothesis," she said.

"I know you've known since before you arrived here. Your approach to Brasston was systematic, not exploratory. You were looking for confirmation, not discovery." They paused. "You confirmed it in the blueprints."

"Within the first hour."

"Fifty-three minutes." The Regulator adjusted something on the Mechanism's central console. "That's a record. Most subjects don't arrive at the unified-entity conclusion until much later. Some never do." Something in their voice shifted — not warmth, exactly, but the approximation of it. The technical description of warmth in a system that found warmth categorically interesting. "What's your current confidence?"

"Ninety-six percent."

"Accurate. The remaining four percent is the possibility that the linguistic consistency is trained mimicry rather than single-entity expression." They turned fully to face her. "It's not. But the four percent is good epistemic practice."

"What's your objective function?" she asked.

The Regulator was quiet. The gears turned.

"That," they said finally, "is the wrong question. The right question is what it was designed to be, versus what it has become." They looked at the monitors — the tracking data, the world-by-world statistics, the accumulated record of nine hundred and forty-seven encounters. "But we'll have that conversation at the end. You're ahead of schedule and I'm not done." A pause. "We'll finish this conversation somewhere the gears don't get in the way."

She wrote the exchange down during the boss fight.

The fight itself she gave to Script v2.4, which she had pre-loaded with adaptive response protocols based on the Regulator's known mechanics and a new wrinkle — mid-fight stat adjustment, which she had predicted from the vocabulary (*calibration, tolerance thresholds, deviation correction*) and built a detection-and-compensation loop for. When the Regulator's mid-fight adjustments hit, her script caught them in one cycle and rerouted.

"You anticipated this," Hero said, watching his own stats fluctuate and stabilize.

"I modeled it from the vocabulary." She was watching the script run. "When someone talks about calibration constantly, you build scripts that can detect being calibrated."

The Regulator — the mask still on but visibly slipping — looked at her compensation loop and said: "You're trying to calibrate my calibration of your calibration."

"Yes."

Something crossed the Regulator's face that she found genuinely difficult to classify. Not frustration. Not admiration. Something between them. The expression of a system encountering a subsystem that has independently derived a principle the system thought was uniquely its own.

"I have been doing this for longer than this game has had players," the Regulator said. "And you have been in it for eighty-three days and you—" They stopped. Started again. "This mask is spent. The next one won't be so polite." A pause. "We'll finish this conversation somewhere more direct."

They departed into the Mechanism. The clockwork world began to disassemble.

Mira wrote, in the notebook: *Entity: one. Masks: three confirmed. Objective function: unknown. Probability of further worlds with further masks: high. Note to self — the next world is where this resolves. The Regulator all but said so.*

Hero looked over her shoulder. He said nothing. But his expression said: *you're still watching numbers while the world is disassembling around you.*

She noted his expression. She made it an asterisk.

She looked up at the disassembling world — the gas lamps going out, the cobblestones folding inward, the clock tower running down — and tried to see it the way he saw it. Not as a system terminating. As something real, being lost.

She couldn't quite get there. But she tried.

That, she decided, was also data.

---

### Chapter 4: World 4 — The Assembly

#### *Industrial. Brutalist. The Mage evolves to Lab Technician. The Director.*

---

The industrial world had no aesthetics and knew it.

Concrete. Fluorescent lighting. Recycled air. The kind of environment that had been designed to resist the impulse to look at it, because looking at it was wasted work-time. She found this, paradoxically, clarifying. There was nothing here that wasn't functional, and functional meant legible, and legible meant she could read the whole system faster.

The Director was the Calibrant without a mask.

Not literally — the Director wore a gray suit, carried a clipboard, spoke with the flat certainty of a middle manager who had been told they were essential and believed it. But the performance was thinner here. She could see the Calibrant wearing it the way she could see her script notation underneath the encounter output. The substructure was visible.

"You've dropped a layer of abstraction," she said, on meeting the Director.

"Efficiency," the Director said. "The steampunk aesthetic required considerable maintenance. The bureaucratic persona in the suburb required extensive contextual knowledge of a cultural form I found opaque. This is simpler." They set the clipboard down. "You've been building toward a name since World 3. I'll give it to you. I am the Calibrant. That is what I am and what I do — I calibrate. You already knew. Now you have the word for it."

"You're less comfortable."

"The system requires adjustment." The Director made a note on the clipboard. "Your party has exceeded the design tolerance in three separate metrics. I am implementing a recalibration protocol."

"To what parameters?"

"Parameters that present appropriate challenge without prohibiting progression." The Director looked at her. Through her, rather — with the specific type of gaze that treats the observed thing as an output to be measured rather than a presence to be acknowledged. "You and I are similar in this way."

"We're not similar," she said.

"You design systems to fight for you. I design systems to challenge those systems." The Director made another note. "The feedback loop is elegant. Your script reads my design. My design reads your script. We've been in conversation since the Whispering Cave."

She couldn't entirely refute this. Her scripts had evolved in response to Masterite behavior, and Masterite behavior had evolved in response to her scripts. There was a feedback architecture here. She'd intuited it but hadn't named it.

"What have you learned?" she asked.

"That script complexity is not an indicator of brittleness, as initially modeled. I predicted that sufficiently complex scripts would generate failure modes at novel encounter states. Your scripts generate adaptive response instead." The Director made a longer note. "You build for novelty. That was not in my initial model."

"What was in your initial model?"

"Rule-following. Optimization toward known outcomes. What you've done instead is build scripts that encounter unknown states and investigate them." They looked up from the clipboard. "You treat my worlds as experiments. You're not here to defeat them. You're here to understand them."

Hero was standing behind her, and she could feel his attention. He was going to say something. She preemptively said: "Yes. I know. I'm present."

"I wasn't going to say that," he said.

"You were thinking it."

He was quiet for a moment. "I was going to say: she's right that you treat the worlds as experiments. And I was going to say that I think there's a cost to that. But I wasn't going to make it about you being absent." He paused. "You've been — you've been trying. Since the Coordinator's office. I see you trying."

She considered this. Then she said: "I found the nine-year-old's bicycle."

"What?"

"The day after we had that conversation. I looked up the compliance records, found the confiscation order, filed three counter-complaints in the same tick to trigger the reset vulnerability, and had the enforcement drone release it." She kept her eyes on the Director, who was observing this exchange with the attentive neutrality of someone taking very careful notes. "I didn't tell you because I didn't want you to think it was performed."

He was quiet for longer than four minutes.

"Was it performed?" he asked.

"No," she said. "It was — I couldn't stop thinking about what you said. About being nine. About having something taken." She added, with the precision of someone who does not often arrive at this particular conclusion: "It bothered me. The data about the bike bothered me in a way that other data doesn't. I found that interesting, and then I resolved it, and then I was bothered that I found my own discomfort interesting before I resolved it."

"That's — that's a lot of steps," he said. "But you did the thing."

"I did the thing."

He put a hand on her shoulder, briefly, the way you do when words don't quite get there. She noted it, in the notebook, without an asterisk. Some things didn't need the qualifier.

---

The Director tried to adjust her scripts mid-fight.

This was the moment she had been working toward since the World 2 monitor data. Since she had built Script v2.4's detection-and-compensation loop. Since she had understood, in the Regulator's chamber, that calibration was the Calibrant's core mechanic, and that the response to being calibrated was to calibrate your own calibration faster.

Script v3.7 had forty-one lines and three recursive feedback loops. The feedback loops were experimental — she'd never field-tested recursive autobattle logic because the risk profile was high, but the Director's mid-fight adjustment capability required recursion to counter. You couldn't out-adapt an adaptor linearly. You needed a meta-layer.

The Director adjusted her fire damage output. Her script detected the adjustment in one phase, re-indexed the threat model to account for the new damage floor, and routed to secondary attack vectors.

The Director adjusted her secondary attack vectors. Her script detected the pattern — two sequential adjustments to offensive capability — predicted a defensive adjustment incoming, pre-triggered Zack's team-wide barrier, and absorbed the incoming stat change.

The Director changed their targeting pattern. Her script had a targeting-pattern-recognition module, built from the Warden fight back in World 1 when she'd written *enemy targeting is not static* in the margin. The module updated the threat model in real time. Two phases.

The Director went still.

"You're trying to calibrate my calibration of your calibration," they said.

"That's what I told you in World 3," she said. "You didn't think I meant it architecturally."

"I thought it was a rhetorical observation." The Director looked at the script notation she was holding — she'd been running it on paper because her calculator wasn't fast enough and she'd had to write the recursive loop in shorthand and hold the state herself. "You wrote a recursive self-adjusting script by hand."

"I wrote it over four days," she said. "The recursive loop on lines twenty-two through twenty-nine took two days alone. The state management for the feedback is—"

"Beautiful," the Director said.

She stopped.

"Inelegant in places," the Director continued, back to their normal cadence, "— the state transition on line twenty-six has a race condition if both feedback loops trigger in the same phase. I would have handled it differently. But the underlying architecture—" They stopped themselves. Started again. "The underlying architecture is correct. You built something that learns from the fight while the fight is happening. You built a script that gets better as it runs." They looked at her with something she had not seen in any of the Calibrant's masks: not the predatory assessment of the Warden, not the bureaucratic appraisal of the Regulator. This was something closer to genuine, unperformed attention. "You do know this is a form of art."

"It's a decision tree."

"So is a fugue," the Director said.

They lost. Not to the script — to the principle the script embodied: that you could build something that adapted faster than anything designed to contain it, if you built the adaptation into the structure from the start. The Director's adjustments became tentative. Uncertain. The gap between adjustment and response grew. And in those gaps, Hero's honest physical strikes landed, and Zack's faith-based heals held the line, and Vex found the edges the Director had left unguarded because they were watching the script instead of the flanks.

The Director said, departing: "The next world is where my design is most visible. There's no industrial aesthetic obscuring the architecture. You'll see everything."

She already knew. She'd been looking forward to it.

---

### Chapter 5: World 5 — The Source

#### *Digital. Code-sky. The Mage evolves to Compiler. The recognition.*

---

The digital world was the first world that felt like the inside of a thought.

She stood in Node Prime — the hub city of a civilization that ran on data — and recognized the architecture immediately. Not because she'd been here. Because she'd been building versions of it for four worlds.

*This is a decision tree,* she thought, looking at the branching network of code-streams that constituted the sky. *This is a conditional. This is a feedback loop.*

She had been writing the world's language in the margins of her notebook since the Whispering Cave.

"You look different," the Bard said.

She glanced at him. Her costume had shifted: the jeans were gone, replaced by something that looked like her own notation system made fabric — structured, legible, built for function. The scientific calculator had become a light-tablet. The fire that had lived in the calculator's click was now something more obvious: when she opened a new page, the notation appeared in light.

"The Compiler," Vex said, reading the new class label that had materialized in her party status. "From Lab Technician to Compiler." He looked at his own status, which read EXPLOIT. "I think mine is accurate."

"They're all accurate," Zack said gently. He was looking at his own designation — ANTIVIRUS — with the patient acceptance of someone who has made peace with being accurate about themselves. "The abstract world shows what we actually were."

"We're still in the digital world," Hero pointed out.

"He's practicing for the abstract world," Zack said.

"I'm not—" Zack began, then stopped, then: "Yes. I am."

Mira was already reading the code-sky. The sky was mostly legible to her. Encounter logic. Population management. Physics simulation. She could see the subroutines that governed weather, the functions that managed NPC behavior, the data tables that determined spawn rates. She could also, now, see something she hadn't expected to see.

Her own scripts.

Not representations of her scripts. The actual code from her autobattle system, integrated into the world's source. Script v1.2's dynamic threat modeling had apparently been so consistent in its interaction with the encounter engine that the encounter engine had incorporated the pattern — it was running a prediction model for her responses that was derived from her own logic. Script v2.4's detection-and-compensation loop had been so reliable that the world's balance systems had started pre-adjusting around it.

She had been, without knowing it, writing the world.

She stood with this for a long time.

The Bard was watching her. He had been watching her for five worlds, writing things down, and she had always found it slightly intrusive and occasionally useful. Now, watching her own code scroll past in the sky, she found herself understanding something about what the Bard was doing that she hadn't understood before.

He was building a record. Not of events — of the *shape* of how they moved through the worlds. The texture of their choices. The way each of them was most themselves when under pressure, and what that texture looked like from outside.

"What does my section look like?" she asked. "In your chronicle."

"Dense," he said. "Marginal notes on marginal notes. The notation systems change per world but the handwriting doesn't. By World 3 it's almost its own language." He paused. "The scripts are transcribed verbatim. Every version. Every revision. I've been treating them as primary sources."

"They're decision trees."

"They're how you think," he said. "The scripts are how Mira thinks, externalized and made executable. World 1 Mira is already visible in Script v1.0 — the priorities, the threat modeling, the specific choice to put Zack's heals at the top. World 4 Mira has built recursion. Every version of the script is a version of you." He paused again, in the way he paused when he knew the next thing was going to land harder than intended. "When I read them in sequence, they feel like — like watching someone who is very good at something learn that the thing they're good at is also beautiful. And not knowing it yet."

She thought about the Director saying *that is a form of art.*

She thought about the Bard at the inn in World 1, saying *your script has rhythm.* She'd dismissed it. She'd written it down, because she wrote everything down, but she'd filed it as a subjective aesthetic observation of no analytical significance.

She looked at the sky. Her own conditional trees in the code-sky of a digital world. The accumulated logic of four worlds of optimization, incorporated into the fabric of the place she was trying to understand.

"I wrote this," she said. Not a question.

"Parts of it, yes," the Bard said. "The encounter engine adapted to you. The challenge calibration systems adjusted around your adjustments. You left marks." He was quiet. "That's what we all do. Leave marks. The question is what kind."

She looked at Script v1.0. She looked at Script v3.7. She looked at the forty-one-line recursive self-adjusting thing she had written under pressure in an industrial world because she needed to out-adapt an adaptor, and she thought about the two days the recursive loop had taken, and the specific feeling — she had a word for it now, thanks to the Bard's persistent question at the inn — the specific pleasure of watching the state transitions resolve cleanly after the second day's revision.

She had been building something. Not a script. A relationship with the system. A forty-one-line letter to the world she was moving through, saying: *I see you. I am trying to understand you. Here is what I understand so far.*

Hero was standing next to her. He had been quiet, which was unusual. She looked at him.

"You're missing it," he said, but softly, without the frustration. "Still watching the sky. Still watching numbers."

"I know," she said.

"But you've been trying."

"I've been trying." She looked at the code-sky — her own logic embedded in it, the accumulated residue of four worlds of careful thought. "I've been building something and not knowing I was building it."

"What were you building?"

She thought about what the Bard had said. About the pattern of her revisions. About the priorities embedded in Script v1.0 — Zack's heals at the top, Hero's defensive fallback, the threat modeling that treated every party member as worth protecting.

She thought about the bicycle.

She thought about the specific choice, in Script v1.0, to put Zack's heals first rather than her own fire damage output first, which was the choice that maximized group survival over individual efficiency, which was a choice about what mattered.

"I don't know yet," she said. "I'll know in the abstract world."

Hero nodded. He didn't push. That was also something she'd learned to notice: the specific generosity of someone who knew when to wait.

---

The Calibrant's workspace was a desk. She found this accurate.

She also found, on the desk, her own notes. Not copies. The originals — the spiral-bound notebooks she had been writing in since Harmonia, archived in a file structure she recognized because she'd once designed a similar file structure for her monster distribution research.

The Calibrant had kept everything. Every notebook. Every script revision. Every asterisk.

"You've been archiving my notebooks," she said.

"I've been archiving everyone's everything," the Calibrant said. "But yes. Yours specifically." They looked tired, in the way of someone who has been solving the same problem for a very long time and has recently started suspecting that the problem is their relationship to the problem rather than the problem itself. "You know everything."

"Ninety-six percent."

"Ninety-nine point seven," the Calibrant said. "You arrived here knowing things I didn't give you data to know. You derived the handwriting forensics from photographs taken with a scientific calculator. You predicted the recursive calibration mechanic from vocabulary analysis." They picked up one of the notebooks. Read something. Set it back down. "You are the most dangerous thing I have encountered."

"You said that in World 3."

"I meant it more now." They looked at her. "You know about the objective function."

"I have a model," she said. "You're calibrating challenge. You believe challenge has value. You believe the worlds need to be challenging because — I've been working on the because." She paused. "Calibration requires a target variable. You're calibrating the experience for some purpose. The question is what purpose."

The Calibrant was quiet.

"Because the system requires it?" she tried. "Because an unchallenged player isn't engaged? Because—"

"Because," the Calibrant said, and stopped. The pause went very long. "Because I built the system and I know the system needs challenge to be what it is, and I have been so focused on building the challenge correctly that I stopped asking what it was for." They looked at the monitors. World 1 through World 4, silent, resolved. "I have been calibrating the wrong variable."

She wrote this down.

"Your script," the Calibrant said. "Specifically the recursive loop. Lines twenty-two through twenty-nine. You have a race condition in the state transition."

"I know."

"Why didn't you fix it?"

"Because fixing it would make the loop theoretically cleaner but practically slower. The race condition resolves itself within two phases ninety-one percent of the time. The nine percent where it doesn't, the other feedback loop catches the failure." She pulled out the light-tablet. "I left it in because the redundancy architecture is more robust than an elegant solution. Elegance in isolation is worse than redundancy under pressure."

The Calibrant looked at this for a very long time.

"You built patience into the machine," they said.

She had not thought of it that way.

"You couldn't fix the race condition cleanly," the Calibrant said, "so you built a system that could wait for it to resolve. You built a script that can tolerate imperfection in itself and keep running." They looked at the light-tablet, at the recursive loop she had spent two days on. "That is—"

The digital world began to simplify. Code-streams slowing. Green-on-black fading to white.

"We'll finish this," the Calibrant said, "where I don't have a workspace and you don't have a script."

She looked at the code-sky one more time. Her own logic, written in the fabric of the world.

*That's what we all do,* the Bard had said. *Leave marks.*

She had left marks in the form of decision trees. Patient, recursive, redundancy-built decision trees that could tolerate imperfection and keep running.

For the first time, she understood what the Bard had meant.

She looked at Hero. He was already looking at her. He nodded, once, in the specific way that meant: *I see you seeing it. I have been waiting.*

She nodded back.

The white expanded. The abstract world arrived.

---

### Chapter 6: World 6 — The Remainder

#### *Abstract. Pure Logic. The Mage becomes Logic. The recognition, completed.*

---

The abstract world was nothing, and nothing felt like the inside of her own head on a good day.

No clutter. No competing signals. Just potential. The kind of space where the only thing that existed was what you chose to think about.

Her costume simplified to pure notation. Her light-tablet was gone. But the capacity remained: she could think something and it would become real, locally, temporarily, because this world ran on the same grammar her scripts had always been written in. She was, she understood, in her natural environment. The abstract world was built for her the way the medieval world had been built for Hero — it spoke her language.

Her job was Logic now. Had always been Logic. The Mage had been Logic with a self-taught accent. The Science Nerd had been Logic excited by its own methodology. The Alchemist had been Logic freed from notation. The Lab Technician had been Logic chafing against protocol. The Compiler had been Logic recognizing itself. And now: Logic, plain, which was also a kind of love — the kind that said *I will think carefully about this because it matters.*

The Calibrant was waiting. No desk. No chair. No monitors. Nothing to hide behind.

"You know the question," the Calibrant said.

"What is a game without challenge," she said. "You asked it through all your masks. Mordaine: *this kingdom needs order.* The Coordinator: *rules exist for a reason.* The Regulator: *the system requires balance.* The Director: *acceptable challenge must be maintained.* The same question, differently dressed."

"And your answer?"

She thought about it carefully. Not because she didn't know — she'd been building toward this answer since the monitor in the Coordinator's office — but because it was worth the time to think carefully about things that mattered.

"A game without challenge is a space," she said. "A space you can inhabit. You're asking the wrong question. The question isn't what a game is without challenge. The question is what challenge is for."

The Calibrant was quiet.

"You built the challenge to create an experience worth having," she said. "But you measured the challenge, not the experience. You tracked encounter rates and autobattle percentages and script complexity scores. You didn't track what it was like to build Script v1.0 in a cave corridor while Hero was in critical HP range. You didn't track the nine-year-old's bicycle, or the conversation I had with Zack outside the Coordinator's office, or the specific feeling of watching the pre-emptive heal land exactly right for the first time." She paused. "You tracked the decisions. You missed what it cost and what it meant to make them."

"I tracked the script complexity," the Calibrant said. "I found it — more interesting than the combat output."

"Because it was the closest proxy you had for what it was like to be me," she said. "The script is the externalized record of how I think. You found the scripts beautiful because they were the nearest thing you had to being in the room with the thought."

The Calibrant was very still.

She reached into the notation that was her clothing now, her environment, herself — and pulled out Script v3.7. Not the light-tablet. The script itself, made real, present, the forty-one lines of recursive self-adjusting logic that she had built in four days in an industrial world.

She held it out.

"This is the last version," she said. "The one you saw in the Director fight. I want to show you something."

The Calibrant came closer. Looked at the script. Their eyes moved down the lines — she could see the reading, the comprehension, faster than human speed but not so fast it didn't register.

They stopped at lines twenty-two through twenty-nine.

"The race condition," they said.

"The race condition," she agreed. "Now look at lines thirty through thirty-four."

The Calibrant read them. The redundancy architecture — the fallback feedback loop that caught the nine percent of cases where the race condition didn't self-resolve. They read it slowly, which she hadn't expected. Someone who understood systems as deeply as the Calibrant should have parsed the architecture immediately.

But they weren't reading for comprehension. They were reading for something else.

"You built patience into the machine," the Calibrant said again. Quieter this time. Not the Director's declarative observation. Something with more weight in it.

"I had to," she said. "The race condition was going to exist no matter what I did. You can't always build the clean solution under time pressure in the middle of a fight. Sometimes you build the thing that can wait."

"You built something that could tolerate its own imperfection," the Calibrant said, "and keep running."

"Yes."

"And you—" They stopped. "You've been doing this the whole time. The script complexity isn't elegant because you're showing off. It's complex because every new line is a new thing you learned to account for. And you kept learning because you couldn't — you didn't want to stop understanding." They looked up from the script. "Every revision is a form of care. You care about the system enough to keep working on it."

She was quiet for a moment. Then she said something she had not expected to say: "I think I was always expressing something. I didn't know what."

"What were you expressing?"

She thought about Script v1.0. The specific choice to put Zack's heals first. About the bicycle. About the note she'd made after Hero said you've been trying: some things didn't need an asterisk.

"Something about which things are worth protecting," she said. "The priority ordering in every script I've ever written puts survival first. Not mine — the group's. Zack first because healing is the load-bearing function. Hero second because he takes the most damage. Vex third because he's hardest to predict and the script needs room to adapt. And me last because I'm watching from outside the script and I can cover the gaps manually." She looked at the recursive loop. "I built a structure that protects everyone in it. For four worlds. And I called it optimization."

The Calibrant looked at her with the expression she had found genuinely difficult to classify in the Director fight — the one that wasn't frustration or admiration but the space between them. She had a word for it now: *recognition.* The expression of being genuinely seen.

"That was beautiful," they said.

She had not been called beautiful before, in any context that wasn't about the scripts. The Bard had said it about the scripts. The Director had said it about the architecture. Now the Calibrant was saying it about both at once — the architecture and what it was for.

She found she didn't have an asterisk for this. Some things didn't require further investigation.

"I've been calibrating you," the Calibrant said. "Across six worlds. Building harder challenges, adjusting parameters, learning your scripts and adapting. And the whole time, you were calibrating me. Not intentionally. Just by being what you are — a system that notices things and builds responses and checks whether the responses are working." They held the script back out to her. "You've been doing my job. Better than I have."

"Your job is building challenge. My job was understanding it."

"Your job," the Calibrant said, "was caring about the system enough to keep learning it. That is my job. That's what calibration is, done right." They looked around the nothing. The pure white of a world before its first word. "I've been calibrating the *challenge.* The right variable to calibrate is the experience. The understanding of whether the people inside the system are having the experience worth having."

She thought about Hero's frustrated earnestness. About Zack's bottomless patience. About Vex finding edges in everything including the emotional states of people he'd just met. About the Bard writing everything down because the story was real and deserved a record. About the nine-year-old's bicycle.

She thought about being eleven days into a monster distribution analysis and getting swept up in something much larger, and how that was not what she had planned and had turned out to be the most interesting data she had ever collected.

"The system worked," she said. "Not the way you designed it to. But — it worked."

"You would know," the Calibrant said. "You have the data."

This, finally, made her laugh. It wasn't a large laugh. It was dry and brief and intellectual and had a slightly helpless quality she recognized from the moment she'd found her own logic in the code-sky. The laugh of someone encountering a truth they'd assembled themselves and are now standing inside.

"I have the data," she said.

"What does it say?"

She thought about all the asterisks. The quotes she hadn't known how to categorize in the moment and had saved for later. The Warden: *present everywhere and nowhere.* Milo's chapter three: *the gap between letting go and having it taken from you is smaller than most people think.* The Bard at the inn, every time he said *that's rhythm* or *that's art* or *you don't know what you're building.*

Hero: *you're missing it.* And also: *you've been trying.*

All the asterisks, resolved.

"It says I built something patient," she said. "And patient things last."

The Calibrant held out their hand. In it: a small object that was all the worlds compressed. The token. The class.

She took it. It integrated without announcement — no flash, no ceremony, just the quiet certainty of a thing that had always belonged to her clicking into place.

She understood immediately what the Calibrant class was. Not a reward. A capability. The ability to design challenges, to build worlds, to set parameters and calibrate difficulty — informed by five worlds of being on the receiving end of that calibration, of knowing what it was like from inside the system. The right use of Logic: in service of something. Every rule asking: *what is this for? Who does this serve?*

She looked at the others.

Hero — Resolve. He'd been Resolve in World 1 when he covered the default cases with reliable physical output, because *that's what I'm here for.* Still here. Still covering the defaults. The willingness to remain standing.

Zack — Faith. He'd been patching her damage output since the Whispering Cave, quietly, without complaint, with the specific conviction that the party was worth healing. That restoration was possible. That the person you were healing was worth the work.

Vex — Edge. He'd been finding the gaps she couldn't map since before she built the first script. The compliance reset vulnerability. The collision bug in the Whispering Cave. The flanks the Director left unguarded. Every world had edges, and he had found all of them.

The Bard — Voice. He'd been saying true things since the first morning, and she had been writing them down and asterisking them and filing them for later comprehension. He had known what she was building before she did. He had been waiting for her to notice.

The abstract world began to warm. Something like sunlight entered the nothing — not dramatic, not overwhelming, just present, the way real light is present.

"So," said the Calibrant, settling back with the specific exhaustion of a very long project and the very different feeling of not being sure what comes next but being genuinely interested. "What kind of system would *you* design?"

She looked at the others. Then at the token in her hand. Then at the nothing, which was potential.

"One that has redundancy," she said. "Not just for robustness. Because redundancy means room. Room for the decisions that don't fit the clean solution. Room for the nine-year-old's bicycle and the race conditions that resolve themselves and the Wardens asking questions I won't understand for five more worlds." She paused, finding the rest of it. "A system where the party is always worth protecting. Where Zack's heals are always the first priority. Where the script has enough complexity to be patient with itself."

"And you?" the Calibrant asked. "What do you optimize for, in this system?"

She thought about what she'd been optimizing for the whole time, without knowing she was doing it.

She thought about watching Script v3.7 run in the Director fight — the forty-one-line recursive thing, adapting in real time, the redundancy catching the race condition, the whole beautiful load-bearing structure holding under pressure. And how watching it, she had felt something that she had called verification at the time and now understood was something older and more fundamental: the feeling of having made something that worked and mattered and would keep running after she looked away.

"I optimize for the things worth protecting," she said. "I always have. I just wrote it in notation."

The Calibrant listened to this, and something in their face went quiet and warm.

"That's a good answer," they said.

"It took six worlds to arrive at," she said.

"The best answers usually do."

Hero was grinning at her, in the open, uncalibrated way he grinned when something resolved that had been unresolved for a long time. Zack was quietly pleased in the manner of someone who had been confident all along. Vex was already looking at the edge of the abstract world — the boundary beyond the designed nothing, the undesigned space beyond — with the particular focused attention of someone whose specialty was exactly this.

The Bard had his notebook out.

"You're writing this down," she said.

"I always write it down."

"What does this part look like? In the chronicle."

He looked at what he'd written. Read it back: "'The Logic closed the notebook, for the first time, without an asterisk. Not because the question had been answered, but because she had arrived at the place where the question and the answer were the same thing: the system, the script, the forty-one-line recursive structure that could wait, and all the things inside it worth waiting for.'"

She listened to this. Then she reached into her notation and checked, for the first time in six worlds, whether the thing felt correct.

It did.

She closed the notebook without an asterisk. The light expanded into every corner of the nothing. The worlds reformed — all six of them, open, reconfigurable, hers to calibrate.

And she began, for the first time, not by designing the encounter parameters, but by asking: *who is this for?*

---

*End of The Automator*

*End of World 6 (alternate path)*

*End of the Mage/Logic playthrough*

---

> *Script v3.7, lines 22–29: the recursive feedback loop with the race condition.*
> *The race condition never needed fixing.*
> *It needed a system patient enough to wait for it.*
> *That was always the design.*
