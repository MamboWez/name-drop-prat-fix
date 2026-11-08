<div align="center">

# 🏷️ Name Drop — Prat Compatibility Edition

**Shorter character names. Cleaner chat. Same people.**

A World of Warcraft: Forever addon that shortens character surnames without losing the ability to tell players apart — now with a compatibility fix for **Prat 3.0**.

**WoW Forever** · **Prat 3.0 compatible** · **Lua** · **v1.0.0-prat-fix1**

[Features](#-features) · [Installation](#-installation) · [Prat setup](#-prat-30-compatibility) · [Commands](#-slash-commands) · [Troubleshooting](#-troubleshooting)

</div>

---

## ✨ Why Name Drop?

In **WoW Forever**, players have both a first name and a surname. That's great for character identity, but lengthy names can make busy chat channels harder to read.

Name Drop changes the **displayed name**, not the player's identity:

```text
Before: [Frost Winterborn]: Looking for a healer!
After:  [Frost W.]: Looking for a healer!
```

If you meet someone with a similar surname, Name Drop can automatically show a few extra letters:

| Full character name | Smart display name |
| --- | --- |
| Frost Winterborn | **Frost Win.** |
| Frost Wildheart | **Frost Wil.** |
| Frost Blackwood | **Frost B.** |
| Asha Brightvale | **Asha B.** |

*These are illustrative examples: abbreviations depend on the other names your client has learned.*

## 🚀 Features

- **Readable chat:** shorten speaker names in say, yell, party, raid, guild, whispers and other channels.
- **Smart abbreviations:** use only as much of a surname as needed to distinguish known players.
- **Preserved player links:** click, right-click, shift-click and reply to players using their real names.
- **Full-name tooltips:** hover a chat player link to see the full name and similarly named players you've encountered.
- **More than chat:** optionally shorten names in system/loot/roll lines, unit frames and nameplates.
- **Flexible display modes:** choose smart, minimal, initial, first-name-only or full-name display.
- **No manual name list:** discover names from chat, group, guild, friends, target and `/who` information.
- **Optional Prat integration:** keep shortened chat names while using Prat's formatting and class colors.

## 📦 Installation

1. Download this repository as a ZIP (or download a release, if available).
2. Extract the addon so the files are directly inside:

   ```text
   World of Warcraft/_forever_/Interface/AddOns/NameDrop/
   ├── NameDrop.toc
   ├── Names.lua
   ├── Core.lua
   ├── Chat.lua
   ├── PratCompat.lua
   ├── Frames.lua
   └── Options.lua
   ```

3. If you're updating an existing installation, back up and replace the old `NameDrop` folder.
4. Start WoW Forever and enable **Name Drop** in the AddOns menu.
5. Enter the game and type `/namedrop test` to preview the current style.

> **Tip:** Make sure the folder is `AddOns/NameDrop/`, **not** `AddOns/NameDrop/NameDrop/`. This fork can be installed manually even if your addon manager does not list it.

## 🎨 Name styles

| Mode | Example | Behavior |
| --- | --- | --- |
| `smart` **(default)** | `Frost W.` → `Frost Win.` | Start with a surname initial; expand when needed to distinguish known names. |
| `auto` | `Frost` → `Frost Win.` | Show only the first name until another known player shares it. |
| `initial` | `Frost W.` | Always use one surname letter. |
| `first` | `Frost` | Show only the first name. |
| `full` | `Frost Winterborn` | Keep the game's full-name display. |

Change your style in the addon settings or enter:

```text
/namedrop mode smart
```

## 🤝 Prat 3.0 compatibility

**This is the key addition in this edition.**

The original Name Drop processes sender names through WoW's standard chat filtering. Prat 3.0 builds chat messages through its own formatting pipeline, which can prevent the shortening from appearing when Prat is enabled.

This fork adds `PratCompat.lua`, which registers for Prat's **`Prat_PreAddMessage`** callback and shortens its displayed `PLAYER` field before the final chat line is assembled. The underlying player hyperlink remains unchanged.

### Recommended configuration

1. Enable **Name Drop** and **Prat 3.0**.
2. Open Prat with `/prat`.
3. Under **Module Control**, enable **PlayerNames**.
4. Open **PlayerNames** and set **Player Color Mode** to **Class**.
5. Enter `/reload`.

**Result:** shorter player names **and** class-colored names in chat, with Prat's other chat features retained.

> Prat is **optional**. Without it, Name Drop continues using the standard WoW chat path. The integration is designed to do nothing when Prat is absent.

## ⚙️ Settings

Open the in-game settings using `/namedrop` (or `/nd`). The options include:

| Setting | What it controls |
| --- | --- |
| Enable Name Drop | Master switch for all changes. |
| Chat: speaker names | Shorten player names next to chat messages. |
| Chat: system, loot and roll lines | Shorten names mentioned within selected game-generated messages. |
| Unit frames | Shorten names on supported player, target, focus, party and raid frames. |
| Nameplates | Shorten names shown on supported nameplates. |
| Hover full name | Display full-name details when hovering a player link in chat. |

You can turn these parts on or off independently.

## ⌨️ Slash commands

Both `/namedrop` and `/nd` are supported.

| Command | Description |
| --- | --- |
| `/namedrop` | Open addon settings. |
| `/namedrop help` | Show command help. |
| `/namedrop mode smart` | Use smart abbreviations. |
| `/namedrop mode auto` | Use minimal abbreviations. |
| `/namedrop mode initial` | Show a single surname initial. |
| `/namedrop mode first` | Show first names only. |
| `/namedrop mode full` | Show full names. |
| `/namedrop chat on` | Enable speaker-name shortening. |
| `/namedrop system off` | Disable shortening in system/loot/roll lines. |
| `/namedrop frames off` | Disable shortening on unit frames. |
| `/namedrop plates off` | Disable shortening on nameplates. |
| `/namedrop hover on` | Enable full-name hover tooltips. |
| `/namedrop on` / `/namedrop off` | Enable or disable the addon. |
| `/namedrop who Frost` | Show known characters named Frost. |
| `/namedrop test` | Preview name styles with sample players. |
| `/namedrop stats` | Show counts of learned names. |
| `/namedrop status` | Show the current options. |
| `/namedrop debug` | Show activation and compatibility diagnostics. |
| `/namedrop forget confirm` | Clear the locally learned player-name list. |

## 🩺 Troubleshooting

<details>
<summary><strong>Prat is enabled, but names remain long</strong></summary>

- Check that you're using the edition containing `PratCompat.lua`.
- Confirm both addons are enabled, then run `/reload`.
- Try `/namedrop mode initial` and `/namedrop chat on`.
- Run `/namedrop debug` and look for `pratCompat=true`.
- If it says `pratCompat=false`, the Prat callback was not registered. Verify Prat is installed and enabled.

`pratCompat=true` confirms the integration was registered; it does not guarantee every possible chat message is processed.

</details>

<details>
<summary><strong>Names are shortened, but class colors are missing</strong></summary>

In Prat, enable **PlayerNames** and set **Player Color Mode → Class**. Reload the UI. This combination has been tested successfully with the compatibility edition.

</details>

<details>
<summary><strong>The addon isn't shown by an addon manager</strong></summary>

Install manually using the folder layout above. An addon manager's listing or flavor detection is separate from whether the addon can load in WoW Forever.

</details>

<details>
<summary><strong>How do I inspect the current state?</strong></summary>

Run:

```text
/namedrop debug
```

Example of a healthy installation with Prat:

```text
forever=true active=true separator=" " senderFilter=true pratCompat=true lastError=nil
```

- `forever=true`: the Forever naming environment was detected.
- `active=true`: Name Drop is enabled and active.
- `senderFilter=true`: the normal sender-name filter is available.
- `pratCompat=true`: the Prat integration registered successfully.
- `lastError=nil`: no error has been recorded by Name Drop.

</details>

## 🧩 What's changed in this edition?

| File | Purpose |
| --- | --- |
| `PratCompat.lua` | **Added:** handles Prat's pre-add-message callback and shortens the displayed `PLAYER` field. |
| `NameDrop.toc` | **Updated:** loads the compatibility file after `Chat.lua` and lists Prat as an optional dependency. |
| `Options.lua` | **Updated:** includes the `pratCompat` state in `/namedrop debug`. |
| Other Lua files | Original Name Drop functionality retained. |

The patch does **not** alter a player's actual name or the destination stored in clickable player links.

## 💾 Saved data

The addon remembers player-name combinations locally in the WoW `NameDropDB` saved-variable data. This allows abbreviations to remain distinctive as you encounter more players. Its current defaults retain learned names for **90 days** and cap the stored registry at **40,000 players** after pruning.

## 🙌 Credits and attribution

- **Original Name Drop:** [Name Drop on CurseForge](https://www.curseforge.com/wow/addons/name-drop), credited in the addon metadata to **Frost-Lightbringer** (published on CurseForge by **Frostaphim**).
- **Prat 3.0:** [Prat 3.0 on CurseForge](https://www.curseforge.com/wow/addons/prat-3-0), maintained by its contributors.
- **This edition:** an unofficial Prat compatibility modification of Name Drop; not an official release by the original addon author or the Prat team.

### ⚖️ License notice

The original Name Drop project is listed on CurseForge as **All Rights Reserved**. This README does not grant a license to the original source or permission to redistribute modified versions. **Obtain the original author's permission before publishing or distributing this fork**, unless you already have the necessary rights.

---

<div align="center">

**Less name clutter. More game.** ✨

</div>
