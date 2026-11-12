# CurseForge listing

Paste these fields into the project form at authors.curseforge.com.

## Name
Persona

## Summary
Your character has habits. Persona notices them, then writes a personality profile about you. Works on Midnight and WoW: Forever.

## Categories
- Primary: Miscellaneous
- Also: Roleplay, Achievements

## License
MIT

## Source
https://github.com/devoidx/persona

## Description

**Every character sheet shows Strength and Haste. None of them mention that you jump fourteen times a minute.**

Persona quietly watches how your character actually behaves and turns it into a short written profile, shown in a panel beside your character frame. Your strongest habit becomes your title.

> **Thrall the Restless**
>
> **Restless.** Thrall cannot walk anywhere without bouncing: 14 jumps a minute on the road.
>
> **Old Friend.** Grimfang has fought beside Thrall for 212 hours. Some bonds don't break.
>
> **Night Owl.** 40% of Thrall's adventures happen between midnight and 5am. Sleep is for NPCs.
>
> **Menace to Wildlife.** Thrall has killed 2,511 critters. None of them were a threat.

Each trait has five phrasings that change daily, so your profile doesn't read the same every time you open it.

### What it notices
- How often you jump while travelling, and how far you fall
- Which mount you actually ride, measured in time on its back
- Where you spend your life, down to the subzone, and where you keep dying
- How long you stand still in town, and how often you go AFK
- When you play: time of day and day of the week
- Every emote you use, and whether anyone was there to see you dance
- How full you keep your bags
- Your vanity pets and your combat pets, by name
- Class and racial signature moves used for no good reason: portals, summons, Feign Death with nothing nearby, Shadowmeld in town, War Stomp at nobody
- Your lifetime record from the Statistics panel: deaths, falling deaths, abandoned quests, critters, hugs, waves, LOLs and facepalms

### Six tabs
- **Profile**: your title and personality traits
- **Habits**: the numbers behind them
- **Emotes**: every emote you've used, most loved first
- **Lifetime**: what the Statistics panel says about you
- **Places**: where you spend your time, and where you die
- **Roster**: every character on your account, who gets your time, and which one is "your dramatic one"

### About 50 traits
Restless, Grounded, City Slicker, Homebody, Wanderer, Loyal, Stable Master, Pedestrian, Gravity Enthusiast, Leap of Faith, Gravity Victim, Commitment Issues, Menace to Wildlife, The Hugger, Easily Amused, Exasperated, Friendly, Cheerleader, Sardonic, Stone-Faced, Dancer, Dances Alone, Polite, Rude, Night Owl, Early Bird, Weekend Warrior, Hoarder, Travels Light, Nemesis, Easily Distracted, Taxi Service, Summoning Circle, Never Owned a Horse, Lurker, Drama Queen, Hiding From Nobody, Runs With the Pack, Rocket Commuter, Happy Camper, Born to Soar, Stomps for Fun, Escape Artist, Never Alone, Best Friends, Menagerie, Old Friend, Stable of Beasts and Lone Wolf.

Your whole account gets traits too: Altoholic, One True Main and Split Personality.

### Share it
The **Share** button (or `/persona share`) gives you your profile as text, ready to paste into Discord or in-game chat.

### WoW: Forever
Install it before you make your character and Persona sees your whole story from level 1. Lifetime statistics start empty on Forever, so your personality is built from what Persona observes. Surnames are handled properly.

### Fits your UI
With EllesmereUI installed, Persona's panel takes on its look automatically. There's a minimap button, and Persona is also in the minimap's addons menu.

### Commands
- `/persona`: open or close the panel (or use the Persona button under your character frame)
- `/persona share`: copy your profile as text (`/persona share chat` for one line)
- `/persona moves`: list the signature moves counted on this character
- `/persona stats`: show which lifetime statistics your client provides
- `/persona dock`: put the panel back beside the character frame after dragging it
- `/persona minimap`: hide or show the minimap button
- `/persona forget Name`: remove a character from the roster (`Name-Realm` if two share a name, or `First Surname` on Forever)
- `/persona reset`: start this character's profile again

### Privacy and performance
Data is saved in your own SavedVariables and never leaves your PC. Persona reads no combat data, sends no addon messages and samples a handful of cheap values four times a second.

Opening the panel for the first time each session asks the game for your /played time, which prints the usual line in chat.

### Feedback
Found a habit Persona should notice, or a move that `/persona moves` doesn't count? Open an issue on GitHub or leave a comment here.
