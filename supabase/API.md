# habit-quest API (Supabase Edge Functions)

This file is the shared contract between the Supabase backend (`supabase/`) and
the Flutter API client. The app never queries tables directly: every call goes
to an Edge Function.

Base URL: `{SUPABASE_URL}/functions/v1/<name>`
(project `fwikodmrfoorbstmkedx` → `https://fwikodmrfoorbstmkedx.supabase.co`).

## General rules

- Every request sends the header `apikey: <anon key>`.
- Data endpoints (`habits`, `check-ins`, `game-state`) and `auth-logout` also
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

## Status code summary

| Status | Codes |
|---|---|
| 400 | `invalid_input`, `weak_password`, `same_password` |
| 401 | `unauthorized`, `invalid_credentials`, `invalid_refresh_token` |
| 403 | `email_not_confirmed`, `signup_disabled` |
| 404 | `not_found` |
| 405 | `method_not_allowed` |
| 409 | `email_taken`, `habit_not_found`, `no_password` |
| 429 | `rate_limited` (Supabase Auth rate limit) |
| 500 | `internal_error` |
