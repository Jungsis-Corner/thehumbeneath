# THE HUM BENEATH – Story Bible

Working title for a first-person, turn-based, grid-based dungeon crawler for the Sinclair QL (expanded memory, 256 KB+). All in-game text is English. Setting: an original cat-clan world (own names, own terms).

---

## 1. Setting

The **Emberfen Clan** lives at the edge of a moor, beside an abandoned farmstead. Every spring the thaw brings fog, frogs and good hunting. This year it also brings **the Hum**: a deep, steady sound from under the earth that only the young cats can hear.

The elders tell of the **Deepwardens**, a sept that walked below the earth generations ago and never came home. Nobody knows why they left. Nobody has followed them.

Four young cats slip away from camp one night. The cellar door of the farmstead is open.

### Clan terms (original, do not replace with terms from other works)

| Term | Meaning |
|---|---|
| Emberfen Clan | The player's clan |
| The Hum | The sound from below |
| Deepwardens | The lost sept |
| Pale Ones | Eyeless descendants of the Deepwardens |
| Starfolk | Ancestor spirits of the Emberfen |
| Hollow-Keeper | Final guardian |
| Scratch-Marks | Messages carved by the Deepwardens |
| Fen Moss | Healing moss, used by healers |

### Ranks (level progression)

1. Kit
2. Pounce
3. Fenwalker
4. Emberguard
5. Deepwalker (max)

---

## 2. The Party

Four young cats. Names are placeholders and can be changed.

| Role | Cat | Strengths | Weakness |
|---|---|---|---|
| Fighter | **Ashclaw** | High HP, strong melee | Slow, poor at finding things |
| Healer | **Mossfern** | Moss, herbs, protective charm | Weak attack |
| Scout | **Quickwhisker** | Finds traps and secret passages, acts first | Low HP |
| Hunter | **Sedgepelt** | Pounce attack, finds prey | Needs space to attack |

### Healer: Moss and Bleeding

Moss is the healer's signature resource.

**Bleeding (status effect)**
- Caused by claws, bites, thorns, glass shards and some traps.
- A bleeding cat loses 1-2 HP per step and per combat round until treated.
- Bleeding can stack with severity: *Scratch* (1 HP), *Gash* (2 HP), *Deep Wound* (3 HP, also lowers max HP until treated).

**Fen Moss**
- Found in damp areas (Drain Tunnels, Old Cistern, Glowcap Caverns, Heart Hollow).
- Only Mossfern can use it at full effect: **Moss Pack** stops bleeding at once and restores a little HP.
- Other cats can apply moss too, but it only stops *Scratch* level bleeding and takes a full turn.
- Mossfern carries up to 9 moss, the others up to 3.
- Dry moss from the Bone Halls is weaker (stops *Scratch* and *Gash*, not *Deep Wound*).
- Glowcap moss from level 5 is the strongest: stops all bleeding and cures poison.

**Healer skills**

| Skill | Effect |
|---|---|
| Moss Pack | Stop bleeding, heal 3 HP. Uses 1 moss. |
| Press and Hold | Free: reduces bleeding by one level for the rest of the fight. |
| Herb Chew | Cure poison. Uses 1 herb. |
| Starfolk Charm | Party takes less damage for 3 rounds. |
| Gather | Search the current tile for moss or herbs (once per tile). |

---

## 3. Levels

Eight levels, each 32x32 cells. Every level has: an entrance stair, a way down, 1-2 shortcuts, 3-5 Scratch-Marks, moss and herb spots (where noted), a mini-boss or hazard.

### Level 1: The Root Cellar
- **Mood:** Dusty, cramped, the smell of old apples.
- **Enemies:** Rats, Giant Spiders (bleed: Scratch)
- **Hazards:** Loose boards, cobwebs (slow)
- **Mini-boss:** Old Whiskerless, a huge one-eared rat
- **Features:** Tutorial area. No moss, but herbs in crates.

### Level 2: The Drain Tunnels
- **Mood:** Wet, dripping, echoing.
- **Enemies:** Sewer Rats, Eels (water tiles), Leeches
- **Hazards:** Flooded corridors (cold: lower speed), broken grates
- **Mini-boss:** The Gate Rat, guards the sluice gate
- **Features:** First Fen Moss on the walls.

### Level 3: The Old Cistern
- **Mood:** Huge stone halls, long echoes, pale light from above.
- **Enemies:** Bats, Cave Crickets, Water Snakes
- **Hazards:** Echo traps (noise wakes enemies), slippery stone
- **Puzzle:** Three valve wheels open the cistern door.
- **Features:** Moss in the corners, first Scratch-Marks of the Deepwardens.

### Level 4: The Rail Tunnel
- **Mood:** Rusted rails, collapsed ceilings, old lanterns.
- **Enemies:** Foxes, Crows (near shafts), Rust Beetles
- **Hazards:** Falling rubble, broken glass (bleed: Gash)
- **Mini-boss:** Vixen Redbrush, a fox who has claimed the tunnel
- **Features:** Shortcut via a handcar track.

### Level 5: The Glowcap Caverns
- **Mood:** Soft green and blue light, spores drifting in the air.
- **Enemies:** Adders, Spore Moths, Cave Toads
- **Hazards:** Poison spores, sinkholes
- **Features:** Glowcap Moss (strongest healing). Safe resting spot with a glowing pool.

### Level 6: The Bone Halls
- **Mood:** Silent catacombs, walls lined with small skulls and carved stone.
- **Enemies:** Bone Rats, Shade Cats (illusions), Wraith Owls
- **Hazards:** Collapsing floors, spike pits (bleed: Deep Wound)
- **Features:** Most Scratch-Marks of the game. The Deepwardens' burial chambers. Dry moss only.

### Level 7: The Silent Warren
- **Mood:** Abandoned burrows and nests. No light, no wind, no sound.
- **Enemies:** **Pale Ones** (eyeless cats, hunt by sound), Warren Rats, Stalker Badgers
- **Hazards:** Sound alerts the Pale Ones. Moving carefully (sneak step) is a mechanic.
- **Mini-boss:** The Elder Pale, who does not want to fight
- **Features:** Emotional heart of the story. A choice: fight the Pale Ones or pass quietly.

### Level 8: The Heart Hollow
- **Mood:** A vast cavern, the Hum is physical, light pulses in time with it.
- **Enemies:** Echo Shades, the **Hollow-Keeper**
- **Hazards:** Hum pulses stun the party at intervals
- **Features:** Moss garden at the centre. Final choice.

---

## 4. Enemies

| Name | Level | HP | Notes |
|---|---|---|---|
| Rat | 1-2 | 4 | Weak, comes in groups |
| Giant Spider | 1 | 6 | Bleed (Scratch) |
| Old Whiskerless | 1 | 18 | Mini-boss |
| Sewer Rat | 2 | 7 | Poison bite |
| Eel | 2 | 8 | Only in water tiles |
| Leech | 2 | 4 | Drains HP over time |
| The Gate Rat | 2 | 24 | Mini-boss |
| Bat | 3 | 5 | Fast, erratic |
| Cave Cricket | 3 | 6 | Jumps, hard to hit |
| Water Snake | 3 | 9 | Poison |
| Fox | 4 | 14 | Strong, bleed (Gash) |
| Crow | 4 | 8 | Attacks from above |
| Rust Beetle | 4 | 10 | High armour |
| Vixen Redbrush | 4 | 30 | Mini-boss |
| Adder | 5 | 10 | Poison, bleed (Scratch) |
| Spore Moth | 5 | 6 | Spreads poison cloud |
| Cave Toad | 5 | 12 | Slow, heavy hits |
| Bone Rat | 6 | 9 | Comes back once |
| Shade Cat | 6 | 12 | Illusions: false targets |
| Wraith Owl | 6 | 16 | Bleed (Deep Wound) |
| Pale One | 7 | 14 | Blind, hunts by noise |
| Warren Rat | 7 | 10 | Pack animal |
| Stalker Badger | 7 | 28 | Very strong |
| The Elder Pale | 7 | 36 | Mini-boss, can be spared |
| Echo Shade | 8 | 20 | Copies the party's last action |
| The Hollow-Keeper | 8 | 60 | Final boss |

---

## 5. Items

**Healing and supplies**
- **Fen Moss:** stops bleeding
- **Dry Moss:** weaker moss
- **Glowcap Moss:** strongest moss
- **Marigold Leaf:** heals 5 HP
- **Cobweb Wrap:** slows bleeding for 10 steps
- **Poppy Seed:** removes fear
- **Fresh Prey:** restores stamina
- **Stale Prey:** restores less, may cause sickness

**Gear**
- **Bramble Collar:** +1 defence
- **Thistle Charm:** resist poison
- **Starfolk Feather:** once-per-level revive
- **Lantern Shard:** brighter view, shows secrets
- **Echo Pebble:** thrown to lure enemies

**Key items**
- **Cellar Key**
- **Valve Wheel** (x3)
- **Handcar Lever**
- **Pale Totem**
- **Heart Stone**

---

## 6. Intro Text

```
The Hum began with the thaw.

Only the young could hear it,
a low sound beneath the moor,
like a heartbeat in the dark.

The elders spoke of the Deepwardens,
who walked below the earth
and never came home.

Tonight, four cats slip past
the camp border.

The cellar door is open.

Follow the Hum.
```

---

## 7. In-Game Texts

Short lines only (max. ~40 characters per line where possible) to save memory.

### Menu and System
```
NEW GAME
LOAD GAME
SAVE GAME
OPTIONS
QUIT

Name your cats.
Choose a role.
Save complete.
No save found.
Game over.
```

### Navigation
```
You step forward.
A wall blocks the way.
The door is locked.
The door creaks open.
You turn left.
You turn right.
Something moves ahead.
You hear dripping water.
The air is cold and still.
```

### Combat
```
%s attacks!
%s misses.
%s is hit for %d.
%s is bleeding!
The wound is deep.
%s uses a Moss Pack.
The bleeding stops.
%s is poisoned.
%s falls.
Victory!
The party flees.
You cannot flee.
```

### Healer
```
Mossfern presses moss to the wound.
The bleeding slows.
The bleeding stops.
Mossfern gathers moss.
No moss left.
Mossfern chews the herb. The poison fades.
The Starfolk watch over you.
```

### Status
```
Scratch.
Gash.
Deep Wound.
Poisoned.
Stunned.
Afraid.
Tired.
```

### Level Entry Messages
```
1: Dust and old apples.
2: Dark water runs below.
3: Your steps echo for a long time.
4: Rusted rails vanish into the dark.
5: Soft light glows on the walls.
6: The walls are lined with bones.
7: Nothing moves. Nothing sounds.
8: The Hum is in your bones.
```

### Scratch-Marks (found texts)

**Level 1**
```
WE WENT DOWN
WE WERE NOT AFRAID
```
```
The cellar is only the first step.
```

**Level 2**
```
FOLLOW THE WATER
IT KNOWS THE WAY
```
```
The gate rat guards what we left behind.
```

**Level 3**
```
THE HUM IS CALM HERE
WE SLEPT WELL
```
```
Three wheels. Three turns. Do not rush.
```

**Level 4**
```
THE ROOF FELL IN
WE LOST FOUR
```
```
Fox claims the tunnel now.
Perhaps we should have stayed.
```

**Level 5**
```
THE LIGHT HEALS
THE LIGHT FEEDS
WE STAYED TOO LONG
```
```
The glowing moss mends any wound.
Take it. Carry it.
```

**Level 6**
```
HERE WE LAID THEM DOWN
THE HUM TOOK THEIR NAMES
```
```
We could not leave.
We could not stop listening.
```
```
Our kits were born deaf to the sun.
```
```
WE CARVED THEIR FACES
SO THE STONE REMEMBERS
```
```
The young ones no longer ask
what the sky looks like.
```
```
THE OLDEST SAY THE HUM CALLS
THE YOUNGEST SAY IT SINGS
```
```
Lay me facing up.
I want to remember the way home.
```

**Level 7**
```
THEY HAVE NO EYES
THEY HAVE NO FEAR
WE ARE THEIR FATHERS
```
```
Do not run. Do not shout.
They hear everything.
```
```
We did this.
We stayed too long.
```

**Level 8**
```
THE HUM IS NOT A VOICE
IT IS A CALL FOR HELP
```
```
Something below is asking
to be let go.
```
```
WE BOUND IT TO KEEP THE HUM
THE HUM BOUND US TO KEEP IT
```
```
If you read this, you came
further than we dared to go back.
```

### Pale One Encounter (Level 7, spoken as text)
```
A pale shape turns its head.
It has no eyes.
It listens.
It does not attack.
"You are... warm."
"Are you... ours?"
```

### Elder Pale (mini-boss)
```
The Elder Pale rises.
"We were once like you."
"The Hum kept us. It did not let go."

[FIGHT]  [SPARE]
```
Spare outcome:
```
The Elder Pale lowers its head.
"Take the Heart Stone.
 End what we could not."
```

### Hollow-Keeper
```
The Hum stops.
For one breath, the world is silent.
Then something vast opens its eyes.
```
```
THE HOLLOW-KEEPER
Bound here. Bound by the Deepwardens.
```

---

## 8. Endings

### Ending A: The Release (Pale Ones spared, Heart Stone used)
```
The Hum fades.
The Keeper's chains fall away.
Above, the moor is quiet.
The Pale Ones follow you to the surface.
They feel the sun for the first time.
The Emberfen gather at the cellar door.
Some turn away.
Some step forward.
```

### Ending B: The Silence (Keeper defeated, Pale Ones fought)
```
The Hum stops.
The tunnels fall silent.
You return alone.
The clan celebrates.
But at night,
you still listen.
```

### Ending C: The Stay (Heart Stone rejected)
```
You lay down at the Heart.
The Hum welcomes you.
Somewhere above,
a new kit hears it for the first time.
```

---

## 9. Technical Notes for Implementation

- **Text budget:** Keep all strings in one external file (`TEXT.dat` or similar), loaded at startup. Terminate lines with a zero byte; use `%s` / `%d` placeholders for names and numbers.
- **Line width:** Max 32-40 characters per line to fit the HUD text area.
- **Found texts:** Index by `(level, id)`. One Scratch-Mark per map cell flag.
- **Status flags per character:** bleed level (0-3), poison, stun, fear. Bleeding tick per step and per combat round.
- **Moss inventory:** separate counters per type (fen, dry, glowcap), capped per character.
- **Sneak step (Level 7):** movement mode with half speed, no noise; noise level decides if Pale Ones notice the party.
- **Branching:** one flag `elder_spared`, one flag `heart_stone_used` decide the ending.
