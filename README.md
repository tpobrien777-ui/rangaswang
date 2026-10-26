# RANGA-SWANG

Daily trivia golf. Every shot is a question with a number for an answer, and Rusty the orangutan swings as well as you guess. Three holes, par 12, a new course every day at midnight.

## What's where

| Path | What it is |
|---|---|
| `index.html` | The game |
| `config.js` | Site settings: web address, launch date, Supabase keys, GitHub repo |
| `content/days/` | One question file per day. See `content/README.md` |
| `content/reserve.json` | Backup questions for days that run short |
| `studio/` | The Question Studio, a private editor for the question files |
| `supabase/setup.sql` | Creates the live stats database. Run it once in Supabase's SQL Editor |
| `assets/` | Link preview image and app icons |
| `tools/validate.mjs` | Checks every question file: `node tools/validate.mjs` |

## Editing questions

Any of these works. Edits go live about a minute after saving.

1. **Question Studio:** open `/studio/` on the site. The first time, it walks you through making a GitHub access key.
2. **GitHub:** open a file in `content/days/` on github.com, click the pencil, edit, then commit.
3. **Ask Claude.**

Each morning a scheduled Claude task writes tomorrow's two news questions, keeps about ten days of questions ready, checks them, and saves them here. It never changes or removes a question you wrote or edited (those carry `"by": "owner"`).

## Live stats

When `supabaseUrl` and `supabaseKey` are set in `config.js`, the game:

- records how each question was answered, and shows players "41% of players were within 10% on this one"
- posts finished daily rounds to a public leaderboard, using the name each player picks (default "Rookie")
- shows a "Field" row of average scores on the scorecard

Players are identified only by a random code made by their browser. To see growth, open Supabase → SQL Editor and run `select * from daily_activity;`. To pull a name off the leaderboard, open Table Editor → `rounds` and set `hidden` to true. Rude names are hidden automatically.

If Supabase is down or not set up, the game still works; it just skips the stats.

## Hosting

The site is static files served by GitHub Pages. Players' scores, streaks and question history are saved in their own browsers.

Before running ads, move hosting to Cloudflare Pages or Netlify (both free, and both allow commercial sites). Connect the same repository and point the domain at the new host. Nothing in the game needs to change.
