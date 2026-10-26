# RangaSwang questions

Every day of the game is one file in `days/`, named for its date: `days/2026-10-27.json`.
`reserve.json` holds backup questions the game uses only if a day runs short.

The easiest way to edit is the **Question Studio** (`/studio/` on the site). You can also edit these files on github.com, or ask Claude.

## How a day is played

A daily round is three holes: a par 5, a par 4 and a par 3. Every shot asks one question from that day's file:

| List | When players see it | Target per day |
|---|---|---|
| `news` | The tee shots on holes 1 and 2 | 2 |
| `medium` | Off the tee and from the fairway | 5 |
| `hard` | After a mishit, shank or whiff, or from the rough, a bunker or the trees | 4 |
| `easy` | Within 40 yards of the pin, or on the green | 5 |

Within a list, questions are used **from the top down**, so everyone in the same situation gets the same question. A player never sees any question twice. Questions a day doesn't use are simply never played.

## Format

```json
{
 "date": "2026-10-27",
 "news":   [ QUESTION, QUESTION ],
 "easy":   [ QUESTION, ... ],
 "medium": [ QUESTION, ... ],
 "hard":   [ QUESTION, ... ]
}
```

Each QUESTION:

```json
{
 "id": "a7k2m9qx",
 "cat": "history",
 "q": "In what year did the Golden Gate Bridge open?",
 "a": 1937,
 "type": "year",
 "unit": "year",
 "fact": "Its towers rise 746 feet above the water.",
 "src": "https://…",
 "by": "owner"
}
```

| Field | Meaning |
|---|---|
| `id` | Unique, never reused. Letters and numbers. |
| `cat` | `history`, `pop`, `geo`, `sports` or `news` |
| `q` | The question. Ends with `?`. |
| `a` | The exact answer: a whole number, no quotes, no commas. |
| `type` | `year` for years. `number` for everything else. Years get wider strike bands. |
| `unit` | Shown next to the answer box: `year`, `feet`, `points`, `million $`… |
| `fact` | One short, true "Did you know?" line, shown after the shot. |
| `src` | Optional. A source link, mainly for news. |
| `by` | `"owner"` marks a question you wrote or edited. **The morning update never changes or removes these.** The Studio adds it for you. |

## Writing rules

- **Answers are exact whole numbers.** If the real figure has decimals, say "to the nearest whole number" (or mile, million…) in the question, and round.
- **U.S. units only:** feet, inches, yards, miles, pounds, ounces, °F, gallons. No metric.
- **One clear number.** Avoid answers that depend on how you count or that change often, unless the question pins them to a date ("as of Oct. 25").
- **Difficulty:**
  - *Easy* is common knowledge that most adults can get within 10%.
  - *Medium* is what a trivia fan knows or can reason to.
  - *Hard* is specific, but still fair to estimate.
- **News** questions come from the last few days' real headlines, with a source in `src`. Keep them neutral. Skip deaths, tragedies and partisan framing.
- **Mix the categories** within each list: history, pop culture, geography and sports.
- **No repeats.** Search the whole `content/` folder for the key name or number before adding a question.

## Checking your work

From the repository root, run:

```
node tools/validate.mjs
```

It lists anything that would break the game (bad JSON, missing fields, metric units, duplicates) and how many days are ready.
