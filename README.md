# Record Challenge Suite

A static, browser-based HTML5 Canvas shooting challenge prototype with a Supabase global leaderboard.

## What is included

- `index.html` — the complete game in one file. The silhouette target and gunshot sound are embedded as base64 assets.
- `supabase_leaderboard_setup.sql` — Supabase table, RLS, submit RPC, and leaderboard-read RPC.
- Global Top 20 leaderboard per challenge using Supabase.
- Leaderboards rank by **lowest completed milliseconds**. The fastest completed run gets the highest spot.
- Each leaderboard allows **one score per name per challenge**. If the same name posts a faster score, the older score is replaced. If the same name posts a slower/equal score, the previous best is kept.
- Name prompt appears after any completed run, pass or failed, that qualifies for the Top 20.
- Bindable reload, restart/start-countdown, and fullscreen keys.
- Beep-start ruleset with 3.000 to 0.000 countdown.
- Gunshot audio on clicks.
- Telemetry-style stats and copyable report.
- Small result share button after each completed run.
- Small Contact button linking to the Discord invite.

## Supabase setup

1. Open Supabase → SQL Editor.
2. Run `supabase_leaderboard_setup.sql`.
3. Confirm it succeeds.
4. In `index.html`, the project URL and publishable key are set near the top of the script:

```js
const SUPABASE_URL = 'https://rwekwfjkwylpzyzakfgx.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_qDQRk6Dig3KmInxZIbLJ6w_JbYqDA3I';
```

Only use the publishable/anon browser key. Never put a `service_role`, secret key, database password, or connection string in this public GitHub Pages file.

## GitHub Pages upload

1. Create a GitHub repository.
2. Upload `index.html` to the root of the repository.
3. Upload `README.md` and `supabase_leaderboard_setup.sql` if you want to keep setup notes in the repo.
4. Go to **Settings → Pages**.
5. Set the source to your main branch and root folder.
6. Open the Pages URL GitHub gives you.

## Global leaderboard behavior

The game reads and submits scores to Supabase:

- PASS and FAILED completed runs can qualify.
- Lowest milliseconds ranks highest.
- One name per challenge.
- A faster score replaces the same name's older score.
- Top 20 is enforced in the database function.

Public users can read the Top 20 and submit through the safe RPC function. They do not receive direct table insert/update/delete permission.

For cheat moderation, use your Supabase dashboard Table Editor or SQL Editor to delete/edit bad rows. Do not expose admin delete buttons with a service-role key inside the public browser game.

## Share and contact buttons

After each completed challenge, a small **Share Result** button appears. It captures the current canvas as a PNG. If the browser supports Web Share with files, it opens the native share sheet; otherwise it downloads the screenshot, copies the result text when possible, and opens a Facebook share page pointing at the Discord invite.

The **Contact** button opens:

```text
https://discordapp.com/invite/qUymDuc
```

## Controls

The game asks for bindable keys on startup:

- Reload
- Restart / start countdown
- Fullscreen

Default controls are R, Space, and F.

## Challenge rules

The timer starts at the beep when countdown reaches 0.000. Firing before the beep disqualifies the attempt and automatically restarts the countdown. Failed runs can still be completed for telemetry, and completed failed runs can qualify for the Top 20 if their milliseconds beat existing scores. Failed leaderboard entries are marked FAILED.


## Latest layout updates

- Six-Plate Rack uses a clean active attempt view so the rack is not compressed by side HUD panels.
- 8 on 4 Targets now also uses a clean active attempt view with the supplied silhouette targets arranged tight side-by-side like the reference footage.
- Menu/results HUD returns after the attempt finishes.
- The top-right fixed controls were adjusted to avoid overlapping canvas text.
- Global Supabase leaderboard remains enabled; fastest completed milliseconds rank highest and each name appears once per challenge.
