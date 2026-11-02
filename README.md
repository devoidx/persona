# Persona

A World of Warcraft addon that watches how your character behaves and writes a personality profile from it. Works on Midnight and WoW: Forever.

Open it with `/persona` or the **Persona** button under the character frame.

## What it tracks

| Habit | How |
|---|---|
| Jumps while travelling | Hook on `JumpOrAscendStart`, filtered by `GetUnitSpeed` and swimming/flying |
| Favourite mount by time ridden | `C_MountJournal` active mount, sampled every 0.25s |
| Places | Real zone and subzone time |
| Idling in town | Stationary while `IsResting()` |
| Falls | `IsFalling()` duration, distance estimated from free-fall time |
| When you play | Local hour and weekday |
| Lifetime habits | Statistics panel (deaths, falling deaths, emotes, critters, abandoned quests) |

Everything is stored per character in `PersonaDB`. No combat data is read, so it is unaffected by Midnight's secret-value restrictions.

## Commands

- `/persona`: toggle the panel
- `/persona stats`: list which lifetime statistics this client provides
- `/persona reset`: wipe this character's data

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
