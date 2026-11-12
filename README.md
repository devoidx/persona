# Persona

A World of Warcraft addon that watches how your character behaves and writes a personality profile from it. Works on Midnight and WoW: Forever.

Open it with `/persona` or the **Persona** button under the character frame.

The panel has six tabs: **Profile** (your title and traits), **Habits**, **Emotes**, **Lifetime** (from the Statistics panel), **Places** and **Roster** (every character on your account). It remembers the last tab you used.

## What it tracks

| Habit | How |
|---|---|
| Jumps while travelling | Hook on `JumpOrAscendStart`, filtered by `GetUnitSpeed` and swimming/flying |
| Favourite mount by time ridden | `C_MountJournal` active mount, sampled every 0.25s |
| Places | Real zone and subzone time |
| Idling in town | Stationary while `IsResting()` |
| Falls | `IsFalling()` duration, distance estimated from free-fall time |
| When you play | Local hour and weekday |
| Bag fullness | Backpack and ordinary bags, sampled once a minute (profession and reagent bags left out) |
| Where you die | `PLAYER_DEAD` plus current place |
| AFK breaks | `PLAYER_FLAGS_CHANGED` plus `UnitIsAFK` |
| Signature moves | Out-of-combat casts of a fixed list of class and racial spells (`UNIT_SPELLCAST_SUCCEEDED`), plus animal-form travel and stealth time |
| Vanity pets | Summoned Pet Journal pet (`C_PetJournal.GetSummonedPetGUID`), by species, with your custom name if you gave one. Works on WoW: Forever too |
| Combat pets | Hunter, warlock and other class pets (`UnitExists("pet")`, `UnitName`, `UnitCreatureFamily`), by name |
| Lifetime habits | Statistics panel (deaths, falling deaths, emotes, critters, abandoned quests) |

Everything is stored per character in `PersonaDB`. No combat data is read, so it is unaffected by Midnight's secret-value restrictions.

## Matching your UI

With EllesmereUI installed, Persona's window, buttons and fonts take on EllesmereUI's look through its skinning API. Turn it off in EllesmereUI under Blizzard Skins+ > Window Skins > Third-Party Addons.

## Commands

- `/persona`: toggle the panel
- `/persona stats`: list which lifetime statistics this client provides
- `/persona moves`: list the class and racial moves counted on this character
- `/persona share` (or `/persona share chat`): open a copy box with your profile as text for Discord or in-game chat; also the **Share** button next to the panel title
- `/persona dock`: put the panel back beside the character frame after moving it
- `/persona minimap`: hide or show the minimap button (Persona is also in the minimap's addons button)
- `/persona forget Name`: remove a character from the roster (use `Name-Realm` if two share a name, or `First Surname` on WoW: Forever)
- `/persona reset`: wipe this character's data

Drag the panel to move it. Once moved it opens where you left it. Opened from the character frame, it closes when the character frame does.

## Bundled libraries

`Libs/` holds LibStub, CallbackHandler-1.0 (from Ace3, BSD licence), LibDataBroker-1.1 and LibDBIcon-1.0, for the minimap button.
LibDBIcon comes from WowAce. To update it:

```
svn export --force https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0 Libs/LibDBIcon-1.0
```

## Releasing

Push a tag such as `v0.4.1`. The GitHub Action runs the smoke tests, then the BigWigs packager builds the zip and uploads it to CurseForge.

Requires the repository secret `CF_API_KEY` and `## X-Curse-Project-ID` in `Persona.toc`.

## Tests

```
pip install lupa
python3 tests/smoke_retail.py Traits.lua
python3 tests/smoke_forever.py Traits.lua
```

These run the trait builder against stubbed game data. They don't replace testing in the game client.
