-- Daily quotes: public.quotes (shared, read-only for users) and
-- public.quote_loves (each user's saved quotes). See supabase/API.md.
--
-- Access model (same as the rest of the schema): the Edge Functions read with
-- the caller's JWT, so RLS applies. Signed-in users may read every quote and
-- read/insert/delete only their own loves. Nobody but the service role (which
-- bypasses RLS) may write quotes: the `quotes` function uses a service-role
-- client for POST/PUT, only after checking that the caller is an admin.

-- ---------------------------------------------------------------------------
-- quotes
-- ---------------------------------------------------------------------------

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  -- Stored trimmed, 1..500 characters.
  text text not null
    check (text = btrim(text) and char_length(text) between 1 and 500),
  -- null = anonymous. Stored trimmed, 1..200 characters.
  author text
    check (author is null or (author = btrim(author) and char_length(author) between 1 and 200)),
  -- The day the quote is scheduled for (UTC calendar day); null = unscheduled.
  day date unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger quotes_set_updated_at
  before update on public.quotes
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- quote_loves
-- ---------------------------------------------------------------------------

create table public.quote_loves (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  quote_id uuid not null references public.quotes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, quote_id)
);

-- "Newest love first" listing, and the cascade from quotes.
create index quote_loves_user_created_at_idx
  on public.quote_loves (user_id, created_at desc);
create index quote_loves_quote_id_idx
  on public.quote_loves (quote_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.quotes enable row level security;
alter table public.quote_loves enable row level security;

-- quotes: every signed-in user reads all quotes; no write policies, so only
-- the service role can insert/update/delete.
create policy "quotes_select_authenticated" on public.quotes
  for select to authenticated using (true);

-- quote_loves: own rows only. Loves are never updated (insert or delete).
create policy "quote_loves_select_own" on public.quote_loves
  for select to authenticated using (user_id = (select auth.uid()));
create policy "quote_loves_insert_own" on public.quote_loves
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "quote_loves_delete_own" on public.quote_loves
  for delete to authenticated using (user_id = (select auth.uid()));

-- Anonymous callers get nothing; signed-in users get read access to quotes
-- and read/insert/delete on their loves (still filtered by the policies).
revoke all on public.quotes, public.quote_loves from anon;
revoke all on public.quotes, public.quote_loves from authenticated;
grant select on public.quotes to authenticated;
grant select, insert, delete on public.quote_loves to authenticated;
grant all on public.quotes, public.quote_loves to service_role;
