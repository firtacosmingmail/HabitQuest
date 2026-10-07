-- habit-quest schema: profiles, habits, check_ins, game_state.
-- Every table belongs to its user (user_id / id = auth.uid()) and has RLS.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Sets server_updated_at to the database time on every insert/update. Delta
-- pulls (`?since=`) filter on this column, never on the client's updated_at.
create or replace function public.set_server_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Creates the profile when a user signs up (display_name from the sign-up
-- metadata). Security definer: it runs as the table owner from auth.users.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(left(trim(coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'displayName',
      ''
    )), 100), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- habits
-- ---------------------------------------------------------------------------

create table public.habits (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null check (char_length(id) between 1 and 200),
  name text not null check (char_length(name) between 1 and 200),
  emoji text not null default '' check (char_length(emoji) <= 32),
  color bigint not null check (color between 0 and 4294967295),
  schedule jsonb not null check (jsonb_typeof(schedule) = 'object'),
  reminder_time text check (reminder_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  created_at timestamptz not null,
  archived boolean not null default false,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index habits_user_server_updated_at_idx
  on public.habits (user_id, server_updated_at);

create trigger habits_set_server_updated_at
  before insert or update on public.habits
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- check_ins
-- ---------------------------------------------------------------------------

create table public.check_ins (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  habit_id text not null,
  date date not null,
  completed boolean not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id),
  -- The id is derived from the habit and the day: "<habitId>_<yyyy-MM-dd>".
  constraint check_ins_id_matches check (id = habit_id || '_' || to_char(date, 'YYYY-MM-DD')),
  constraint check_ins_habit_fk foreign key (user_id, habit_id)
    references public.habits (user_id, id) on delete cascade
);

create index check_ins_user_server_updated_at_idx
  on public.check_ins (user_id, server_updated_at);

create index check_ins_user_habit_idx
  on public.check_ins (user_id, habit_id);

create trigger check_ins_set_server_updated_at
  before insert or update on public.check_ins
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- game_state (one row per user)
-- ---------------------------------------------------------------------------

create table public.game_state (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  state jsonb not null check (jsonb_typeof(state) = 'object'),
  updated_at timestamptz not null,
  server_updated_at timestamptz not null default now()
);

create trigger game_state_set_server_updated_at
  before insert or update on public.game_state
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.habits enable row level security;
alter table public.check_ins enable row level security;
alter table public.game_state enable row level security;

-- profiles (rows are created by the trigger; users may also insert their own)
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "profiles_delete_own" on public.profiles
  for delete to authenticated using (id = (select auth.uid()));

-- habits
create policy "habits_select_own" on public.habits
  for select to authenticated using (user_id = (select auth.uid()));
create policy "habits_insert_own" on public.habits
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "habits_update_own" on public.habits
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "habits_delete_own" on public.habits
  for delete to authenticated using (user_id = (select auth.uid()));

-- check_ins
create policy "check_ins_select_own" on public.check_ins
  for select to authenticated using (user_id = (select auth.uid()));
create policy "check_ins_insert_own" on public.check_ins
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "check_ins_update_own" on public.check_ins
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "check_ins_delete_own" on public.check_ins
  for delete to authenticated using (user_id = (select auth.uid()));

-- game_state
create policy "game_state_select_own" on public.game_state
  for select to authenticated using (user_id = (select auth.uid()));
create policy "game_state_insert_own" on public.game_state
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "game_state_update_own" on public.game_state
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "game_state_delete_own" on public.game_state
  for delete to authenticated using (user_id = (select auth.uid()));

-- Anonymous callers get nothing; signed-in users get table access (still
-- filtered by the policies above).
revoke all on public.profiles, public.habits, public.check_ins, public.game_state from anon;
grant select, insert, update, delete
  on public.profiles, public.habits, public.check_ins, public.game_state
  to authenticated;
