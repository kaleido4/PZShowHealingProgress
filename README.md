# Show Healing Progress

Project Zomboid (Build 42) mod that shows how far each wound has healed in the Health tab.

```
Left Forearm
 - Deep Wound
 - Fracture
 - Bandaged
 - Splinted
 - Deep Wound: 62% healed
 - Fracture: 18% healed
```

- One line per wound: scratch, laceration, deep wound, bite, burn, fracture, and stitches.
- The lines are light blue, so they stand apart from the panel's red injury and green treatment lines.
- A healed wound stays at 100% while a bandage, stitches or a splint is still on the body part. Once they are all off, the line goes away.
- Stitches show 100% when they can be removed safely (see below).
- A deep wound that stopped healing says why: it needs a bandage, or there is still glass inside.
- Wounds that were already there when the mod first ran show an estimate, marked `~`. The same goes for another player's wounds the first time you look at them.

## How it works

The game only keeps the time a wound has left (`BodyPart.DamageUpdate`, B42.21). Each wound timer starts at a random value and counts down to 0, which is when the wound is healed:

| Wound | Usual start | Heals faster with |
|---|---|---|
| Scratch | 7-15 | bandage, plantain |
| Laceration | 10-20 | bandage, plantain |
| Deep wound | 15-20 | bandage, plantain |
| Bite | 50-80 | bandage |
| Burn | 50-100 | bandage |
| Fracture | 50-80 (fall), 10-40 (car) | splint, comfrey |

Traits (Thick/Thin Skinned, Fast/Slow Healer) and the Injury Severity sandbox option scale these.

So the mod remembers the value each wound started at and shows `1 - remaining / start`. It checks every in-game minute for local players, so wounds are caught when they happen even if the Health tab is closed, and every frame while a health panel is open. The starting values are kept in the player's mod data, so they survive save and load.

A wound can get worse before it heals: walking barefoot or in broken shoes adds to a foot's scratch or cut, and a new scratch, cut or fracture on the same body part replaces the timer with a new roll. The mod then measures from the worst the wound has been, so the percentage drops instead of starting over. A wound that healed and comes back starts again from 0%.

When it did not see a wound start, it guesses the start as the largest value the game usually rolls (table above) and marks the result with `~`.

Game behavior worth knowing:

- **Deep wounds** stop at a timer of 3 (around 80-85%) unless they are bandaged and have no glass in them. Without a bandage, a deep wound never fully heals.
- **Stitches**: stitching zeroes the deep wound timer, and a stitch timer counts up instead (from 1-27 depending on the doctor's First Aid level, up to 50). Removing stitches below 40 reopens the deep wound. From 40 on, removing them leaves only a small scratch. So stitch progress is `stitchTime / 40`.

## Layout

```
Contents/mods/PZShowHealingProgress/
  42/mod.info
  common/media/lua/
    client/ShowHealingProgress/SHP_Core.lua     wound tracking (unit-tested)
    client/ShowHealingProgress/SHP_Client.lua   health panel lines
    shared/Translate/EN/IG_UI.json
tests/                                          Kahlua test runner and tests
```

The panel lines are added by wrapping `ISHealthBodyPartListBox:doDrawItem`: the vanilla item draws first, then the mod draws below it and returns the new bottom. No vanilla code is copied, so other mods that change the health panel keep working.
