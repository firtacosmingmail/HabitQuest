# habit-quest API (Supabase Edge Functions)

This file is the shared contract between the Supabase backend (`supabase/`) and
the Flutter API client. The app never queries tables directly: every call goes
to an Edge Function.

Base URL: `{SUPABASE_URL}/functions/v1/<name>`
(project `fwikodmrfoorbstmkedx` → `https://fwikodmrfoorbstmkedx.supabase.co`).

## General rules

- Every request sends the header `apikey: <anon key>`.
- Data endpoints (`habits`, `check-ins`, `game-state`, `quotes`, `quote-loves`,
  `admin-quotes`, `admin-stats`)
  and `auth-logout` also
  send `Authorization: Bearer <accessToken>`.
- Request and response bodies are JSON (`content-type: application/json`).
- Errors: an HTTP 4xx/5xx status with body

  ```json
  { "error": { "code": "<snake_case>", "message": "human readable" } }
  ```

  `401` with code `unauthorized` when the token is missing, invalid or
  expired. Other common codes: `invalid_input` (400), `not_found` (404),
  `method_not_allowed` (405), `internal_error` (500).
- CORS: every function answers `OPTIONS` preflight with `200` and allows any
  origin, the methods `GET, POST, PUT, DELETE, OPTIONS` and the headers
  `authorization, apikey, content-type, x-client-info`.
- Timestamps are ISO-8601 UTC strings with milliseconds, e.g.
  `2026-10-07T09:15:00.000Z`. The server always answers in this exact format;
  it accepts any ISO-8601 string with a time zone.
- Dates are `yyyy-MM-dd`.

## Session

```json
{
  "accessToken": "eyJ...",
  "refreshToken": "abc123",
  "expiresAt": 1791364500,
  "user": { "id": "uuid", "email": "a@b.c" }
}
```

`expiresAt` is an integer number of epoch seconds.

## Auth

All auth endpoints are `POST`.

### `auth-register`

Body: `{ "email": string, "password": string, "displayName"?: string }`

- `200 { "session": Session }`
- `200 { "session": null, "needsConfirmation": true }` when email
  confirmation is enabled in the project and no session is returned.
- `409 email_taken`
- `400 invalid_input` (missing/invalid email or password, displayName not a
  string or longer than 100 characters) or `400 weak_password`.
- `403 signup_disabled` when sign-ups are turned off in the project.

The confirmation email redirects to the hosted "email confirmed" page
(`emailRedirectTo` = `CONFIRM_SUCCESS_URL`). See README "Email confirmation".

### `auth-confirm` (GET, browser link)

Not called by the app. The confirmation email links here (custom template):
`GET auth-confirm?token_hash=...&type=signup|email|email_change|recovery|invite`
(type defaults to `signup`). It verifies the token with `verifyOtp` and answers:

- `303` → `CONFIRM_SUCCESS_URL` on success.
- `303` → `CONFIRM_ERROR_URL?reason=expired|invalid|missing` on failure
  (`otp_expired` → `expired`, which Supabase also returns for unknown or used
  tokens; missing `token_hash` → `missing`; anything else → `invalid`).
- Plain-text `200`/`400` if the URL secrets are unset; `405` for other methods.

### `auth-login`

Body: `{ "email": string, "password": string }`

- `200 { "session": Session }`
- `401 invalid_credentials`
- `403 email_not_confirmed` (account exists but its email is not confirmed)
- `400 invalid_input`

### `auth-oauth`

Sign in (or sign up) with Google or Apple. The app gets an ID token from the
native SDK and sends it here; the function calls
`supabase.auth.signInWithIdToken` on an anon client.

Body: `{ "provider": "google" | "apple", "idToken": string, "nonce"?: string }`

- `nonce` is the **raw** nonce (Apple: the app sends its SHA-256 to Apple and
  the raw value here; Supabase hashes it and compares with the token).
- `200 { "session": Session }`. A first sign-in creates the user; the signup
  trigger creates the `profiles` row with the provider's name
  (`full_name` / `name` metadata) as `displayName`, or `null`.
- `400 invalid_input` (unknown provider, missing/empty `idToken`, non-string
  `nonce`).
- `401 invalid_token`: Supabase rejected the token (bad signature, wrong
  audience / client ID not authorized, expired, nonce mismatch).
- `400 provider_disabled`: the provider is not enabled in Supabase Auth.
- `403 signup_disabled`, `429 rate_limited`, `500 internal_error`.

### `auth-refresh`

Body: `{ "refreshToken": string }`

- `200 { "session": Session }`
- `401 invalid_refresh_token`
- `400 invalid_input`

### `auth-logout`

Header `Authorization: Bearer <accessToken>`, no body.

- `204` (no body). Revokes the refresh tokens of the session.
- `401 unauthorized`

## Resources

### Habit

```json
{
  "id": "client-generated string",
  "name": "Drink water",
  "emoji": "💧",
  "color": 4283215696,
  "schedule": { "type": "daily" },
  "reminderTime": "08:30",
  "createdAt": "2026-10-01T08:00:00.000Z",
  "archived": false,
  "updatedAt": "2026-10-07T09:15:00.000Z",
  "deletedAt": null
}
```

- `id`: non-empty string, max 200 characters.
- `name`: non-empty string, max 200 characters. `emoji`: string (may be
  empty), max 32 characters.
- `color`: integer ARGB, `0 ≤ color ≤ 4294967295`.
- `schedule`: any JSON object, stored as `jsonb` and returned unchanged (the
  server does not interpret it).
- `reminderTime`: `"HH:mm"` (24 h) or `null`.
- `archived`: boolean.
- `updatedAt`: timestamp, required on writes; drives last-write-wins.
- `deletedAt`: `null` or timestamp (tombstone).

### CheckIn

```json
{
  "id": "<habitId>_<yyyy-MM-dd>",
  "habitId": "habit-1",
  "date": "2026-10-07",
  "completed": true,
  "updatedAt": "2026-10-07T09:15:00.000Z",
  "deletedAt": null
}
```

`id` must equal `habitId + "_" + date` (otherwise `400 invalid_input`). The
habit must already exist on the server for this user (push habits before their
check-ins); otherwise `409 habit_not_found`.

### GameState

```json
{ "state": { "...": "opaque JSON object" }, "updatedAt": "2026-10-07T09:15:00.000Z" }
```

One per user. `state` is any JSON object, stored and returned unchanged.

## Last-write-wins (LWW)

A write (upsert or soft delete) is **applied** only if there is no stored row
or the incoming `updatedAt` is strictly greater than the stored `updatedAt`.
Otherwise nothing changes and the response has `"applied": false` with the
stored row in `item`, so the client can adopt the server version. Equal
timestamps are not applied (the write is idempotent).

Every table also has a server-only column `server_updated_at`, set by a trigger
to the database time on every insert/update. It is not part of the JSON.

## Delta pull and cursors

`GET /habits?since=<iso>` (and `GET /check-ins?since=<iso>`) returns every row
whose `server_updated_at > since`, tombstones included, ordered by
`server_updated_at`. Without `since` it returns all rows of the user.

The response contains `serverTime`; the client stores it and sends it as
`since` on its next pull. `serverTime` is the database time of the query minus
a small safety overlap (5 seconds), so writes that were committing while the
pull ran are never skipped. As a consequence a pull can return rows the client
has already seen: apply them idempotently with LWW (equal `updatedAt` = no-op).

## Function `habits`

| Method & path | Body | Response |
|---|---|---|
| `GET /habits?since=<iso>` | – | `200 { "items": [Habit...], "serverTime": iso }` |
| `GET /habits/<id>` | – | `200 Habit` (tombstones included) or `404 not_found` |
| `PUT /habits/<id>` | Habit | `200 { "item": Habit, "applied": bool }` |
| `POST /habits` | Habit (with `id`) | same as PUT, id taken from the body |
| `DELETE /habits/<id>?updatedAt=<iso>` | – | `200 { "item": Habit, "applied": bool }` or `404 not_found` |
| `POST /habits/batch` | `{ "items": [Habit...] }` | `200 { "results": [{ "id", "applied", "item" }] }` |

- PUT: if the body contains an `id` it must equal the path id
  (`400 invalid_input`); if it is missing the path id is used.
- DELETE is a soft delete: sets `deletedAt` and `updatedAt` to the `updatedAt`
  query parameter (defaults to the server's current time when omitted), with
  LWW. The row stays, as a tombstone, so other devices learn about it.
  Deleting an unknown id returns `404 not_found`.
- To undelete, PUT the habit with `deletedAt: null` and a newer `updatedAt`.
- `item` is always the row as stored after the operation.
- Batch: max 500 items per request. The whole batch is validated first; any
  invalid item → `400 invalid_input` and nothing is written (the message names
  the index). Items are applied in order, each with LWW; `results` has the same
  order as `items`.

## Function `check-ins`

Same semantics as `habits`, with CheckIn bodies:

- `GET /check-ins?since=<iso>&habitId=<habitId>` (both optional).
- `GET /check-ins/<id>`, `PUT /check-ins/<id>`, `POST /check-ins`,
  `DELETE /check-ins/<id>?updatedAt=<iso>`, `POST /check-ins/batch`.
- A batch whose check-in refers to a habit that does not exist on the server
  → `409 habit_not_found` (the batch is applied in one transaction, so nothing
  is written).

## Function `game-state`

| Method | Body | Response |
|---|---|---|
| `GET /game-state` | – | `200 { "item": GameState or null, "serverTime": iso }` |
| `PUT /game-state` | GameState | `200 { "item": GameState, "applied": bool }` |
| `DELETE /game-state` | – | `204` (row removed: reset) |

PUT uses LWW on `updatedAt` like the other resources.

## Account

All three functions need `Authorization: Bearer <accessToken>` (checked in
code with `auth.getUser`; `401 unauthorized` otherwise). The user is always
the token's user: nothing in the body can name another account.

### `profile`

`GET /profile` →

```json
{
  "id": "uuid",
  "email": "a@b.c",
  "displayName": "Quest Hero",
  "createdAt": "2026-10-01T08:00:00.000Z",
  "providers": ["email"],
  "hasPassword": true
}
```

- `displayName` is `null` when unset. `createdAt` is the auth user's creation
  time ("member since").
- `providers` lists the sign-in methods from the user's identities
  (`email`, `google`, `apple`, ...). `hasPassword` is `true` when they include
  `email`.

`PUT /profile` with `{ "displayName": string }` → `200` with the same body.
The name is trimmed and must be 1–50 characters (`400 invalid_input`
otherwise). Written to `profiles` with the caller's JWT (RLS).

### `auth-change-password` (POST)

Body: `{ "currentPassword": string, "newPassword": string }`

- `204` (no body). The current password is checked with
  `signInWithPassword` on a separate anon client, then the new one is set with
  `auth.updateUser` on that session (which is then signed out).
- `400 invalid_input` (a field missing), `400 weak_password` (fewer than 6
  or more than 72 characters, or refused by Supabase), `400 same_password`.
- `401 invalid_credentials`: the current password is wrong.
- `409 no_password`: the account has no email identity (Google/Apple).

Supabase Auth revokes the user's other sessions when the password changes
(verified live: the old access and refresh tokens stop working), so the app
signs in again with the new password right after the `204`.

### `account-delete` (POST)

Body: `{ "confirm": "DELETE" }` (exactly; anything else → `400 invalid_input`).

- `204`: the caller's `check_ins`, `habits`, `game_state` and `profiles` rows
  are deleted (with their JWT, RLS), then the auth user with
  `auth.admin.deleteUser`. That admin call uses a service-role client built
  from `SUPABASE_SERVICE_ROLE_KEY`, which Supabase provides to deployed
  functions; it never leaves the server.
- `401 unauthorized`, `500 internal_error`.

## Quotes

A quote of the day, the history of past days, and each user's saved
("loved") quotes. Tables: `quotes` and `quote_loves`
(`migrations/20261016120000_quotes.sql`); 90 quotes are seeded, one per day
from 2026-10-16 to 2027-01-13. Both functions need
`Authorization: Bearer <accessToken>` (checked in code with `auth.getUser`;
`401 unauthorized` otherwise).

### Quote

```json
{
  "id": "6f1c1c1e-1b7a-4f0e-9a43-3d2b9c0f5e11",
  "text": "Well done is better than well said.",
  "author": "Benjamin Franklin",
  "day": "2026-11-14",
  "createdAt": "2026-10-16T12:00:00.000Z",
  "updatedAt": "2026-10-16T12:00:00.000Z",
  "loved": false
}
```

- `id`: uuid (lower case).
- `text`: 1–500 characters, trimmed.
- `author`: 1–200 characters, or `null` for anonymous quotes and proverbs.
- `day`: the UTC calendar day the quote is scheduled for, or `null` when it is
  not scheduled. At most one quote per day.
- `loved`: whether the caller has loved (saved) this quote. Always `false`
  for the service role.

### Function `quotes`

#### `GET /quotes?date=yyyy-MM-dd` — quote of the day

`date` is optional; it defaults to today in UTC. The app should send its own
local calendar day. Any date is accepted, past or future.

`200`:

```json
{ "date": "2026-11-14", "fallback": false, "quote": { /* Quote */ } }
```

- When a quote is scheduled on `date`, it is returned with `fallback: false`.
- Otherwise `fallback: true` and the quote is picked deterministically, so
  every user gets the same quote for the same date: take the quotes with
  `day < date` (or all quotes, unscheduled ones included, if none are older),
  order them by `(day, id)` with `null` days last, and pick the one at index
  `daysSince1970(date) mod count`, where `daysSince1970("1970-01-01") = 0`.
  The pick for a date changes only when quotes are added or rescheduled.
- `400 invalid_input`: `date` is not a real `yyyy-MM-dd` date, or is combined
  with `from`/`to`/`past`.
- `404 not_found`: there are no quotes at all.

#### `GET /quotes?from=yyyy-MM-dd&to=yyyy-MM-dd` or `GET /quotes?past=N` — history

Returns the quotes scheduled on the days of the range, **never future
ones**.

- `from`/`to`: both required, inclusive, `from <= to`, at most 366 days.
  `to` is capped at today (UTC); if `from` is after today the list is empty.
- `past=N` (integer 1–366): the `N` days before today (UTC), today excluded:
  `from = today − N`, `to = today − 1`. Fetch today with `?date=`.

`200`:

```json
{ "from": "2026-10-17", "to": "2026-10-19", "items": [ /* Quote, newest day first */ ] }
```

Only scheduled quotes are listed: a day without a scheduled quote has no
entry (no fallback is computed for history). `400 invalid_input` for a
missing, malformed or out-of-range parameter, or for mixing `past` with
`from`/`to`.

#### `POST /quotes` — create (admin only)

Body: `{ "text": string, "author"?: string | null, "day"?: "yyyy-MM-dd" | null }`
(`author` blank → `null`; strings are trimmed).

`201` with `{ "quote": { /* Quote */ } }`.

#### `PUT /quotes?id=<uuid>` — update (admin only)

Body: any non-empty subset of `{ "text", "author", "day" }` (same rules as
POST; send `null` to clear `author` or `day`). `200` with
`{ "quote": { /* Quote */ } }`.

Admins are the service role (`Authorization: Bearer <service role key>`) or
signed-in users whose email is listed in the `QUOTE_ADMINS` function secret
(comma-separated, case-insensitive). Writes use a service-role client on the
server, after this check. The same check (`_shared/admin.ts`) guards every
admin endpoint; see [Admin](#admin).

To **unschedule** a quote (keep it, free its day), send
`PUT /quotes?id=<uuid>` with `{ "day": null }`. To reschedule, send the new
`day`.

Errors for POST/PUT: `401 unauthorized`; `403 forbidden` (not an admin);
`400 invalid_input` (bad body, bad or missing `id`, empty PUT body);
`404 not_found` (PUT: unknown id); `409 day_taken` (another quote is already
scheduled on `day`). Other methods → `405 method_not_allowed`.

### Function `quote-loves`

The caller's saved quotes. A signed-in user only (the service role gets
`403 forbidden`); a user only ever sees and changes their own loves (RLS).

#### `GET /quote-loves`

`200`:

```json
{ "items": [ { /* Quote, "loved": true */ "lovedAt": "2026-10-20T07:30:00.000Z" } ] }
```

Each item is a Quote (with `loved: true`) plus `lovedAt`, newest love first.

#### `POST /quote-loves`

Body: `{ "quoteId": "<uuid>" }`. Idempotent: loving an already loved quote
changes nothing and returns the original `lovedAt`.

`200` with the item (`Quote` + `loved: true` + `lovedAt`).
`400 invalid_input` (missing or malformed `quoteId`, body not JSON),
`404 not_found` (no such quote).

#### `DELETE /quote-loves?quoteId=<uuid>`

`204` (no body). Idempotent: also `204` when the quote was not loved or does
not exist. `400 invalid_input` for a missing or malformed `quoteId`.

## Admin

Endpoints for the admin web console (`admin/`). All of them need
`Authorization: Bearer <accessToken>` of an **admin**: the service role, or a
signed-in user whose email is in the `QUOTE_ADMINS` function secret
(comma/semicolon/whitespace separated, case-insensitive; one check in
`_shared/admin.ts`, shared with `POST`/`PUT /quotes`). Anyone else gets
`403 forbidden`; a missing or invalid token gets `401 unauthorized`.

On the server they read with a service-role client, created only after the
admin check, through SQL functions that only the service role may execute
(`migrations/20261017120000_admin_functions.sql`: `admin_list_quotes`,
`admin_stats`, both `SECURITY DEFINER`). The service-role key never leaves
the server.

### Function `admin-quotes`

#### `GET /admin-quotes` — every quote, with love counts

Unlike `GET /quotes`, this lists **all** quotes: past, today, scheduled for
the future and unscheduled.

Query (all optional):

| Param | Meaning |
|---|---|
| `q` | case-insensitive substring of `text` or `author` (trimmed, ≤ 200 chars; `%` and `_` are literal) |
| `from`, `to` | inclusive `yyyy-MM-dd` day range; either one set → scheduled quotes only |
| `scheduled` | `all` (default), `scheduled` or `unscheduled` (not combinable with `from`/`to`) |
| `limit` | 1–500, default 100 |
| `offset` | ≥ 0, default 0 |

Order: unscheduled quotes first, then `day` descending (furthest future
first), then `createdAt` descending.

`200`:

```json
{
  "total": 91,
  "limit": 100,
  "offset": 0,
  "items": [
    {
      "id": "uuid", "text": "…", "author": "…" , "day": "2027-01-13",
      "createdAt": "2026-10-16T12:00:00.000Z", "updatedAt": "2026-10-16T12:00:00.000Z",
      "loves": 3
    }
  ]
}
```

`total` counts every match (before paging). `loves` = how many users have the
quote saved. There is no `loved` field (the listing is not per-user).
`400 invalid_input` for a malformed date, `from > to`, an unknown
`scheduled`, an out-of-range `limit`/`offset` or a too long `q`.

#### `DELETE /admin-quotes?id=<uuid>` — delete

`204`. The quote is removed and its loves with it (`on delete cascade`).
`404 not_found` for an unknown id, `400 invalid_input` for a malformed one.
To keep a quote but free its day, unschedule it with
`PUT /quotes?id=` `{ "day": null }` instead.

Create, edit and reschedule stay on `POST /quotes` and `PUT /quotes?id=`.
Days without a scheduled quote fall back to the deterministic cycling
described under `GET /quotes?date=`. Other methods → `405`, sub-paths → `404`.

### Function `admin-stats` (read-only)

#### `GET /admin-stats/me` — admin check

`200 { "admin": true, "email": "a@b.c", "serviceRole": false }` for an admin,
`403 forbidden` otherwise. The console calls it right after sign-in.

#### `GET /admin-stats?from=yyyy-MM-dd&to=yyyy-MM-dd` — usage aggregates

`from`/`to` are optional, inclusive UTC days: `to` defaults to today (UTC),
`from` to `to − 29` (30 days). At most 366 days; `from <= to`; otherwise
`400 invalid_input`.

Aggregates only: counts, per-day/per-week series, histograms and the
most-loved quotes. No user id, email, display name or habit name is ever
returned.

`200`:

```json
{
  "from": "2026-09-21", "to": "2026-10-20", "days": 30,
  "generatedAt": "2026-10-20T10:00:00.000Z",
  "totals": {
    "users": 120, "usersWithGameState": 95,
    "habits": 410, "activeHabits": 350, "completions": 9800,
    "quotes": 90, "scheduledQuotes": 90, "quoteLoves": 230
  },
  "range": {
    "signups": 14, "activeUsers": 61, "habitsCreated": 52,
    "completions": 1900, "quoteLoves": 75, "averageDailyActiveUsers": 33.4
  },
  "daily": [
    { "date": "2026-09-21", "signups": 0, "activeUsers": 31, "habitsCreated": 2,
      "completions": 64, "quoteLoves": 3 }
  ],
  "weekly": [
    { "weekStart": "2026-09-21", "days": 7, "signups": 4, "completions": 450, "activeUsers": 48 }
  ],
  "xpBuckets": [ { "label": "100–499", "min": 100, "max": 499, "users": 40 } ],
  "bestStreakBuckets": [ { "label": "7–13", "min": 7, "max": 13, "users": 12 } ],
  "levels": [ { "level": 3, "users": 20 } ],
  "topQuotes": [ { "id": "uuid", "text": "…", "author": null, "day": "2026-10-20", "loves": 9 } ],
  "widgets": { "recorded": false, "note": "Widget usage is not recorded: …" }
}
```

What each figure means (and its limits):

| Field | Source | Exactness |
|---|---|---|
| `totals.users`, `daily[].signups`, `weekly[].signups` | `auth.users.created_at` (UTC day) | exact |
| `daily[].activeUsers` (DAU), `weekly[].activeUsers` (WAU), `range.activeUsers` | distinct users with ≥ 1 completed, non-deleted check-in **dated** that day/ISO week/range | approximation: users who open the app without checking anything off are not counted; a back-filled check-in counts on its habit day; only synced (signed-in) data exists on the server |
| `range.averageDailyActiveUsers` | mean of `daily[].activeUsers` | derived |
| `totals.habits`, `activeHabits` | non-deleted habits (`activeHabits`: also not archived) | exact (synced habits only) |
| `daily[].habitsCreated` | `habits.created_at` (the client's creation time, also counts habits deleted later) | exact for synced habits |
| `daily[].completions`, `weekly[].completions` | completed, non-deleted `check_ins` by `date` | exact (synced) |
| `xpBuckets` | per user: sum of the numeric values of `game_state.state.checkIns` + `perfectDays` (the app's XP ledgers) | exact for users with a synced game state (`usersWithGameState`) |
| `bestStreakBuckets` | `game_state.state.bestStreakEver` | **best** streak ever; current streaks are computed on the device and not stored |
| `levels` | `game_state.state.maxLevelReached` | highest level reached |
| `daily[].quoteLoves`, `totals.quoteLoves` | `quote_loves.created_at` | loves still present (an unlove deletes the row, so it is not counted) |
| `topQuotes` | the 10 quotes with the most loves, all time | exact |
| `widgets` | – | not recorded: nothing stores widget views or taps |

Buckets — XP: `0`, `1–99`, `100–499`, `500–999`, `1000–2499`, `2500–4999`,
`5000–9999`, `10000+`; best streak: `0`, `1–2`, `3–6`, `7–13`, `14–29`,
`30–59`, `60–99`, `100+`. `weekly` has one entry per ISO week (Monday)
overlapping the range; `days < 7` marks a partial edge week (its counts cover
only the days inside the range). Other methods → `405`, other sub-paths →
`404`.

## Status code summary

| Status | Codes |
|---|---|
| 400 | `invalid_input`, `weak_password`, `same_password`, `provider_disabled` |
| 401 | `unauthorized`, `invalid_credentials`, `invalid_refresh_token`, `invalid_token` |
| 403 | `email_not_confirmed`, `signup_disabled`, `forbidden` |
| 404 | `not_found` |
| 405 | `method_not_allowed` |
| 409 | `email_taken`, `habit_not_found`, `no_password`, `day_taken` |
| 429 | `rate_limited` (Supabase Auth rate limit) |
| 500 | `internal_error` |
