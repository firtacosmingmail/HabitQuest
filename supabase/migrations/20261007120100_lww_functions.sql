-- Last-write-wins (LWW) upserts, soft deletes and delta pulls used by the
-- Edge Functions. All are SECURITY INVOKER: they run as the calling user
-- (the Edge Function forwards the user's JWT), so RLS applies to every
-- statement and auth.uid() is the caller.
--
-- LWW rule: a write is applied only if there is no stored row or the incoming
-- updated_at is strictly greater than the stored updated_at. Every function
-- returns the row as stored after the operation plus whether it was applied.
--
-- Inputs are snake_case JSON objects already validated by the Edge Function
-- (supabase/functions/_shared/validation.ts); the table CHECK constraints are
-- the last line of defence.

-- Overlap subtracted from the pull cursor so that writes still committing
-- while a pull runs are picked up by the next pull (duplicates are harmless:
-- clients apply them with LWW).
create or replace function public.sync_cursor_now()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select now() - interval '5 seconds';
$$;

-- ---------------------------------------------------------------------------
-- habits
-- ---------------------------------------------------------------------------

create or replace function public.upsert_habit(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.habits;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.habits as h (
    user_id, id, name, emoji, color, schedule, reminder_time,
    created_at, archived, updated_at, deleted_at
  ) values (
    auth.uid(),
    p_item ->> 'id',
    p_item ->> 'name',
    coalesce(p_item ->> 'emoji', ''),
    (p_item ->> 'color')::bigint,
    p_item -> 'schedule',
    p_item ->> 'reminder_time',
    (p_item ->> 'created_at')::timestamptz,
    coalesce((p_item ->> 'archived')::boolean, false),
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    name = excluded.name,
    emoji = excluded.emoji,
    color = excluded.color,
    schedule = excluded.schedule,
    reminder_time = excluded.reminder_time,
    created_at = excluded.created_at,
    archived = excluded.archived,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where h.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.habits
    where user_id = auth.uid() and id = p_item ->> 'id';
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

-- Applies the items in order, in one transaction. Returns
-- [{"id","applied","item"}...] in the same order.
create or replace function public.upsert_habits(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_result := public.upsert_habit(v_item);
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('id', v_item ->> 'id') || v_result
    );
  end loop;
  return v_results;
end;
$$;

-- Soft delete (tombstone) with LWW. Returns null when the habit does not exist.
create or replace function public.soft_delete_habit(p_id text, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.habits;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.habits h
     set deleted_at = v_at, updated_at = v_at
   where h.user_id = auth.uid() and h.id = p_id and h.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.habits where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_habits(p_since timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.server_updated_at, h.id)
      from public.habits h
      where h.user_id = auth.uid()
        and (p_since is null or h.server_updated_at > p_since)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- ---------------------------------------------------------------------------
-- check_ins
-- ---------------------------------------------------------------------------

create or replace function public.upsert_check_in(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.check_ins;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.check_ins as c (
    user_id, id, habit_id, date, completed, updated_at, deleted_at
  ) values (
    auth.uid(),
    p_item ->> 'id',
    p_item ->> 'habit_id',
    (p_item ->> 'date')::date,
    (p_item ->> 'completed')::boolean,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    habit_id = excluded.habit_id,
    date = excluded.date,
    completed = excluded.completed,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where c.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.check_ins
    where user_id = auth.uid() and id = p_item ->> 'id';
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.upsert_check_ins(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_result := public.upsert_check_in(v_item);
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('id', v_item ->> 'id') || v_result
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_check_in(p_id text, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.check_ins;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.check_ins c
     set deleted_at = v_at, updated_at = v_at
   where c.user_id = auth.uid() and c.id = p_id and c.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.check_ins where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_check_ins(p_since timestamptz default null, p_habit_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.server_updated_at, c.id)
      from public.check_ins c
      where c.user_id = auth.uid()
        and (p_since is null or c.server_updated_at > p_since)
        and (p_habit_id is null or c.habit_id = p_habit_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- ---------------------------------------------------------------------------
-- game_state
-- ---------------------------------------------------------------------------

create or replace function public.upsert_game_state(p_state jsonb, p_updated_at timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.game_state;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.game_state as g (user_id, state, updated_at)
  values (auth.uid(), p_state, p_updated_at)
  on conflict (user_id) do update set
    state = excluded.state,
    updated_at = excluded.updated_at
  where g.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.game_state where user_id = auth.uid();
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions: only signed-in users may call these.
-- ---------------------------------------------------------------------------

revoke all on function public.sync_cursor_now() from public, anon;
revoke all on function public.upsert_habit(jsonb) from public, anon;
revoke all on function public.upsert_habits(jsonb) from public, anon;
revoke all on function public.soft_delete_habit(text, timestamptz) from public, anon;
revoke all on function public.pull_habits(timestamptz) from public, anon;
revoke all on function public.upsert_check_in(jsonb) from public, anon;
revoke all on function public.upsert_check_ins(jsonb) from public, anon;
revoke all on function public.soft_delete_check_in(text, timestamptz) from public, anon;
revoke all on function public.pull_check_ins(timestamptz, text) from public, anon;
revoke all on function public.upsert_game_state(jsonb, timestamptz) from public, anon;

grant execute on function public.sync_cursor_now() to authenticated;
grant execute on function public.upsert_habit(jsonb) to authenticated;
grant execute on function public.upsert_habits(jsonb) to authenticated;
grant execute on function public.soft_delete_habit(text, timestamptz) to authenticated;
grant execute on function public.pull_habits(timestamptz) to authenticated;
grant execute on function public.upsert_check_in(jsonb) to authenticated;
grant execute on function public.upsert_check_ins(jsonb) to authenticated;
grant execute on function public.soft_delete_check_in(text, timestamptz) to authenticated;
grant execute on function public.pull_check_ins(timestamptz, text) to authenticated;
grant execute on function public.upsert_game_state(jsonb, timestamptz) to authenticated;
