## PaperMC Server Installed!

Your Minecraft server is starting up. It may take a minute to generate the world on first boot.

### Connecting

Players connect to: `$CLOUDRON-APP-DOMAIN` on the Minecraft TCP port shown in the app's Location settings.

### Configuration

- **Server files** are at `/app/data/server/` — edit via the Cloudron File Manager
- **Whitelist** is enabled by default. Add players by editing `whitelist.json` or by granting yourself OP and using `/whitelist add <player>` in-game
- **Ops** can be added by editing `ops.json`
- The server runs in **creative mode** with **peaceful difficulty** and **PvP disabled**

### Auto-Updates

The server checks for new PaperMC builds every 6 hours. When an update is found, it will download the new jar, stop the server briefly, and restart automatically.

<sso>
### Web Console

Visit the app URL to access the web console. You are signed in via Cloudron SSO.
</sso>

<nosso>
### Web Console

Visit the app URL to access the web console (no authentication required).
</nosso>
