# Mod.io listing

- **Name:** RarityScape
- **Profile URL:** rarityscape
- **Homepage:** https://rarityscape.com
- **Summary:**

  Shows how rare your titles, animations, pets and achievements are, right in the game's windows: a colour-coded tier (Common to Ultra Rare) and the % of RarityScape players who own each one.

Description below the line. Copy it from the rendered preview to keep the headings and lists.

---

RarityScape shows how rare your titles, animations, pets and achievements are among RuneScape players who use the plugin, right inside the game's own windows.

## Features

- A colour-coded tier next to every title, animation, pet and achievement in the Customisations and Achievements windows:
  UR Ultra Rare (0.1% or less), SR Super Rare (1% or less), VR Very Rare (5% or less), R Rare (15% or less), U Uncommon (40% or less), C Common.
- Hover a tier to see the exact share of players who own it.
- Community statistics for every item at https://rarityscape.com

## How to use

Enable the plugin and log in. Open the Achievements window or the Customisations window (titles, animations, pets) and the tiers appear next to each item. The plugin reads what you own from the window while you view it, so open each Customisations tab once. Rarity is shared with everyone who contributes: your own unlocks are sent automatically, and from then on you see everyone's. The server refreshes the statistics every few minutes; the plugin downloads them when you log in and every hour.

## Email

rarityscape@outlook.com - for questions, a copy of your data, or having your data deleted.

## Feedback and collaboration

Bug reports, ideas and other feedback are welcome by email or in the comments on this page. Code contributions are not accepted for now, but suggestions are always considered.

## EULA

This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User Licence Agreement (EULA) found at https://legal.jagex.com/docs/terms/eula (and all terms incorporated into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.

## Permissions

- **trackingAccess:** reads your account's tracking ID, which the plugin turns into an anonymous player ID on your PC (a one-way SHA-256 hash). The tracking ID itself never leaves your PC. The player ID links your uploads together, so you are counted once and can have your data deleted.
- **httpAccess:** connects to the RarityScape server (https://rarityscape.com) to send which items you have unlocked and to download the rarity of every item.
- **Used together:** every request to the server carries the anonymous player ID made with trackingAccess. Both permissions are required, because rarity is only shown to players who contribute their own unlocks.

## Data protection

Data is sent to a server in the EU (Germany).

**Data used:**

- an anonymous player ID: a one-way SHA-256 hash of your tracking ID
- which titles, animations, pets and achievements you have unlocked (as game item IDs)
- the plugin version
- English item names, from English clients only (game data, not personal data)

No names, account details, chat or IP addresses are stored. On your PC, the plugin keeps what it saw you own and a short log in the game's plugin storage.

**Endpoints:** https://rarityscape.com, hosted by Hetzner Online GmbH in Germany (EU).

**Security measures:**

- HTTPS only
- every request is signed (HMAC-SHA256); unsigned or altered requests are rejected
- the tracking ID is hashed on your PC and never sent
- all input is validated by the server; the database is not reachable from the internet; server logins use SSH keys only
- your data is deleted automatically 6 months after your last sync, or sooner on request: email your player ID, which the plugin prints in the game console (Alt+`) after you log in
- the public statistics only show totals per item, never individual players

**Privacy notice:** https://rarityscape.com/privacy
