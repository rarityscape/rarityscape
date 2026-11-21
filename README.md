# RarityScape

RS3 plugin that shows how rare your titles, animations, pets and achievements are among
RarityScape players.

## Testing a build (Beta client)

1. Download `rarityscape-<version>.zip` from
   [Releases](https://github.com/rarityscape/rarityscape/releases) and extract it so the files
   end up like this (replace any older `rarityscape` folder):

   ```
   C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\rarityscape\main.lua
   C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\rarityscape\plugin.json
   ...
   ```

2. Start the Beta (Win+R):

   ```
   jagex:launch=runescape,args=[configURI=rs-launch://www.runescape.com/jav_config_beta.ws]
   ```

3. In the console (Alt+\`), ask for the plugin's permissions:

   ```
   prf
   ppr rarityscape
   ```

   If `plist` doesn't list `rarityscape`, first run
   `plugins_setpath C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins`.

4. In the Plugin Hub (toolbox icon, bottom right of the ribbon) → **Manage**, click the
   **padlock** next to RarityScape, allow both permissions and enable it (or `pon rarityscape`).
   If the padlock isn't clickable yet, reopen the Plugin Hub or run `pon rarityscape` and
   `ppr rarityscape` again.

The console then shows `RarityScape starting (trackingAccess=true, httpAccess=true, ...)` and the
tiers appear in Achievements and Customisations shortly after. No console line and a grey cog
means the permissions are missing. After restarting the game, repeat steps 3 and 4.

## Settings

The cog next to RarityScape in **Manage**:

- **Display:** which windows show tier codes, only what you own or completed, player counts in
  tooltips.
- **Tiers:** which tiers to show, and the share of players each one stands for.
- **Sync:** when RarityScape sends and downloads data, and a button to download the latest
  rarity now.
