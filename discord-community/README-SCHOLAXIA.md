# Scholaxia Discord Community

Discord-style chat UI for the Scholaxia **Community** tab. Lives inside the Scholaxia repo.

## Run locally

```bash
cd scholaxia/discord-community
npm install --legacy-peer-deps
npm run dev -- -p 3001
```

Or double-click `scholaxia-desktop/START-DISCORD.bat`.

Stream keys come from `scholaxia-desktop/stream.env` (copied to `.env.local` automatically when you run `python run_desktop.py`).

## In the student app

Click **Community** → opens `/discord-app/scholaxia` on the same server (port 17890, proxied to 3001).

Use **← Back to Scholaxia** inside the Discord UI to return.
