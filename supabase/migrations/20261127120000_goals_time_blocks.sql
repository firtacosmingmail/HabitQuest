-- Projects rework, part 1 (the data layer): Target → Goal, recurring blocks
-- move to the project as time blocks, and "consistent actions" become plain
-- text items of a goal. Runs on the live data (existing rows are kept and
-- back-filled); apply it once, after 20261114120000_projects.sql and
-- 20261114130000_admin_stats_projects.sql. The Supabase CLI applies a
-- migration file in one transaction, so it either applies fully or not at all.
--
-- What changes (ids never change: goal id = old target id, time block id =
-- old consistent action id):
--
-- 1. public.targets is renamed public.goals (constraints, indexes, trigger and
--    policies renamed goals_*). plan_tasks.target_id → plan_tasks.goal_id
--    (FK plan_tasks_goal_fk, index plan_tasks_user_goal_idx).
-- 2. public.consistent_actions (the recurring time blocks of a target) is
--    renamed public.time_blocks (constraints, indexes, trigger, policies
--    renamed time_blocks_*; is_valid_action_recurrence → is_valid_block_recurrence,
--    the check keeps working because it references the function by oid).
--    A time block now belongs to the PROJECT: new columns project_id (back-filled
--    from the goal's project), label (back-filled from the goal's title, i.e.
--    the old target title) and end_date (null = open-ended; the old goal
--    deadline no longer cuts a block off). If the goal is soft-deleted and the
--    block is not, the block gets the goal's deleted_at so blocks of deleted
--    targets do not come back to life; updated_at is NOT touched so the client
--    (whose local migration does the same) and the server stay identical.
--    The target FK and target_id column are dropped; a (user_id, project_id)
--    FK to projects (on delete cascade), an index and the label / end_date
--    checks are added.
-- 3. session_marks.action_id → session_marks.time_block_id (FK
--    session_marks_time_block_fk; the primary key stays
--    (user_id, time_block_id, date)).
-- 4. A NEW public.consistent_actions table: text items of a goal
--    (id, goal_id, text, sort_order + the LWW/tombstone columns), with RLS
--    and grants like the other Projects tables.
-- 5. LWW functions: the target / old consistent-action / session-mark /
--    plan-task functions are dropped and recreated for goals, time blocks,
--    plan tasks (goal_id), the new consistent actions and session marks
--    (time_block_id; ids "<time_block_id>|<date>").
-- 6. The back-fill bumps server_updated_at of every time block (trigger); the
--    app resets its sync cursors with this release, so that is harmless.
-- 7. admin_stats (same signature, `create or replace`): targets → goals
--    (raw keys goals, goals_done) plus time_blocks and consistent_actions
--    counts; sessions count under a live time block of a live project.
--
-- BREAKING: old app builds calling /targets (and the old shapes of
-- /consistent-actions, /plan-tasks, /session-marks) will fail once this
-- migration and the new Edge Functions are deployed. Deploy the database and
-- the functions together, then release the app.

-- ---------------------------------------------------------------------------
-- 1. targets → goals; plan_tasks.target_id → goal_id
-- ---------------------------------------------------------------------------

alter table public.targets rename to goals;

alter table public.goals rename constraint targets_project_fk to goals_project_fk;
alter index public.targets_user_server_updated_at_idx rename to goals_user_server_updated_at_idx;
alter index public.targets_user_project_idx rename to goals_user_project_idx;
alter trigger targets_set_server_updated_at on public.goals
  rename to goals_set_server_updated_at;
alter policy "targets_select_own" on public.goals rename to "goals_select_own";
alter policy "targets_insert_own" on public.goals rename to "goals_insert_own";
alter policy "targets_update_own" on public.goals rename to "goals_update_own";
alter policy "targets_delete_own" on public.goals rename to "goals_delete_own";

alter table public.plan_tasks rename column target_id to goal_id;
alter table public.plan_tasks rename constraint plan_tasks_target_fk to plan_tasks_goal_fk;
alter index public.plan_tasks_user_target_idx rename to plan_tasks_user_goal_idx;

-- ---------------------------------------------------------------------------
-- 2. consistent_actions → time_blocks (owned by the project)
-- ---------------------------------------------------------------------------

alter table public.consistent_actions rename to time_blocks;
alter function public.is_valid_action_recurrence(jsonb) rename to is_valid_block_recurrence;

alter table public.time_blocks
  add column project_id uuid,
  add column label text,
  add column end_date date;

-- Back-fill from the goal (old target). Every block has its goal (FK).
update public.time_blocks b
   set project_id = g.project_id,
       label = g.title,
       deleted_at = case
         when b.deleted_at is null and g.deleted_at is not null then g.deleted_at
         else b.deleted_at
       end
  from public.goals g
 where g.user_id = b.user_id and g.id = b.target_id;

alter table public.time_blocks alter column project_id set not null;

alter table public.time_blocks drop constraint consistent_actions_target_fk;
drop index if exists public.consistent_actions_user_target_idx;
alter table public.time_blocks drop column target_id;

alter table public.time_blocks
  add constraint time_blocks_project_fk foreign key (user_id, project_id)
    references public.projects (user_id, id) on delete cascade,
  add constraint time_blocks_label_check
    check (label is null or (char_length(label) between 1 and 200 and btrim(label) <> '')),
  add constraint time_blocks_end_date_check
    check (end_date is null or start_date is null or end_date >= start_date);

create index time_blocks_user_project_idx on public.time_blocks (user_id, project_id);

alter trigger consistent_actions_set_server_updated_at on public.time_blocks
  rename to time_blocks_set_server_updated_at;
alter policy "consistent_actions_select_own" on public.time_blocks
  rename to "time_blocks_select_own";
alter policy "consistent_actions_insert_own" on public.time_blocks
  rename to "time_blocks_insert_own";
alter policy "consistent_actions_update_own" on public.time_blocks
  rename to "time_blocks_update_own";
alter policy "consistent_actions_delete_own" on public.time_blocks
  rename to "time_blocks_delete_own";
alter index public.consistent_actions_user_server_updated_at_idx
  rename to time_blocks_user_server_updated_at_idx;

-- ---------------------------------------------------------------------------
-- Generated constraint names (pkey, column checks, user_id fkey): rename every
-- remaining targets_* / consistent_actions_* constraint and index. Renaming a
-- primary key constraint also renames its index. This frees the
-- consistent_actions_* names for the new table below.
-- ---------------------------------------------------------------------------

do $$
declare
  m record;
  r record;
begin
  for m in
    select * from (values
      ('public.goals'::regclass, 'targets_', 'goals_'),
      ('public.time_blocks'::regclass, 'consistent_actions_', 'time_blocks_')
    ) v(tbl, old_prefix, new_prefix)
  loop
    for r in
      select conname from pg_constraint
      where conrelid = m.tbl and starts_with(conname, m.old_prefix)
    loop
      execute format('alter table %s rename constraint %I to %I', m.tbl, r.conname,
        m.new_prefix || substr(r.conname, length(m.old_prefix) + 1));
    end loop;
    for r in
      select c.relname from pg_index i join pg_class c on c.oid = i.indexrelid
      where i.indrelid = m.tbl and starts_with(c.relname, m.old_prefix)
    loop
      execute format('alter index public.%I rename to %I', r.relname,
        m.new_prefix || substr(r.relname, length(m.old_prefix) + 1));
    end loop;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. session_marks.action_id → time_block_id
-- ---------------------------------------------------------------------------

alter table public.session_marks rename column action_id to time_block_id;
alter table public.session_marks
  rename constraint session_marks_action_fk to session_marks_time_block_fk;

-- ---------------------------------------------------------------------------
-- 4. NEW consistent_actions: text items of a goal
-- ---------------------------------------------------------------------------

create table public.consistent_actions (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,
  goal_id uuid not null,
  "text" text not null check (char_length("text") between 1 and 500 and btrim("text") <> ''),
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint consistent_actions_goal_fk foreign key (user_id, goal_id)
    references public.goals (user_id, id) on delete cascade
);

create index consistent_actions_user_server_updated_at_idx
  on public.consistent_actions (user_id, server_updated_at);

create index consistent_actions_user_goal_idx
  on public.consistent_actions (user_id, goal_id);

create trigger consistent_actions_set_server_updated_at
  before insert or update on public.consistent_actions
  for each row execute function public.set_server_updated_at();

alter table public.consistent_actions enable row level security;

create policy "consistent_actions_select_own" on public.consistent_actions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "consistent_actions_insert_own" on public.consistent_actions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "consistent_actions_update_own" on public.consistent_actions
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "consistent_actions_delete_own" on public.consistent_actions
  for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.consistent_actions from anon;
grant select, insert, update, delete on public.consistent_actions to authenticated;

-- ---------------------------------------------------------------------------
-- 5. LWW functions. Drop the ones whose table, columns or parameter names
-- change, then recreate (SECURITY INVOKER, search_path = '', signed-in only).
-- ---------------------------------------------------------------------------

drop function if exists public.upsert_target(jsonb);
drop function if exists public.upsert_targets(jsonb);
drop function if exists public.soft_delete_target(uuid, timestamptz);
drop function if exists public.pull_targets(timestamptz, uuid);
drop function if exists public.upsert_plan_task(jsonb);
drop function if exists public.upsert_plan_tasks(jsonb);
drop function if exists public.pull_plan_tasks(timestamptz, uuid);
drop function if exists public.upsert_consistent_action(jsonb);
drop function if exists public.upsert_consistent_actions(jsonb);
drop function if exists public.soft_delete_consistent_action(uuid, timestamptz);
drop function if exists public.pull_consistent_actions(timestamptz, uuid);
drop function if exists public.upsert_session_mark(jsonb);
drop function if exists public.upsert_session_marks(jsonb);
drop function if exists public.soft_delete_session_mark(uuid, date, timestamptz);
drop function if exists public.pull_session_marks(timestamptz, uuid);

-- goals ---------------------------------------------------------------------

create or replace function public.upsert_goal(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.goals;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.goals as g (
    user_id, id, project_id, title, deadline, status,
    created_at, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'id')::uuid,
    (p_item ->> 'project_id')::uuid,
    p_item ->> 'title',
    (p_item ->> 'deadline')::date,
    coalesce(p_item ->> 'status', 'notStarted'),
    (p_item ->> 'created_at')::timestamptz,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    project_id = excluded.project_id,
    title = excluded.title,
    deadline = excluded.deadline,
    status = excluded.status,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where g.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.goals
    where user_id = auth.uid() and id = (p_item ->> 'id')::uuid;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.upsert_goals(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('id', v_item ->> 'id') || public.upsert_goal(v_item)
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_goal(p_id uuid, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.goals;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.goals g
     set deleted_at = v_at, updated_at = v_at
   where g.user_id = auth.uid() and g.id = p_id and g.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.goals where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_goals(p_since timestamptz default null, p_project_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(g) order by g.server_updated_at, g.id)
      from public.goals g
      where g.user_id = auth.uid()
        and (p_since is null or g.server_updated_at > p_since)
        and (p_project_id is null or g.project_id = p_project_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- time_blocks ---------------------------------------------------------------

create or replace function public.upsert_time_block(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.time_blocks;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.time_blocks as b (
    user_id, id, project_id, label, start_time, end_time, recurrence,
    start_date, end_date, created_at, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'id')::uuid,
    (p_item ->> 'project_id')::uuid,
    p_item ->> 'label',
    p_item ->> 'start_time',
    p_item ->> 'end_time',
    p_item -> 'recurrence',
    (p_item ->> 'start_date')::date,
    (p_item ->> 'end_date')::date,
    (p_item ->> 'created_at')::timestamptz,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    project_id = excluded.project_id,
    label = excluded.label,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    recurrence = excluded.recurrence,
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where b.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.time_blocks
    where user_id = auth.uid() and id = (p_item ->> 'id')::uuid;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.upsert_time_blocks(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('id', v_item ->> 'id') || public.upsert_time_block(v_item)
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_time_block(p_id uuid, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.time_blocks;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.time_blocks b
     set deleted_at = v_at, updated_at = v_at
   where b.user_id = auth.uid() and b.id = p_id and b.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.time_blocks where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_time_blocks(p_since timestamptz default null, p_project_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(b) order by b.server_updated_at, b.id)
      from public.time_blocks b
      where b.user_id = auth.uid()
        and (p_since is null or b.server_updated_at > p_since)
        and (p_project_id is null or b.project_id = p_project_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- plan_tasks (goal_id) ------------------------------------------------------

create or replace function public.upsert_plan_task(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.plan_tasks;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.plan_tasks as k (
    user_id, id, goal_id, title, delivery_date, done, position,
    created_at, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'id')::uuid,
    (p_item ->> 'goal_id')::uuid,
    p_item ->> 'title',
    (p_item ->> 'delivery_date')::date,
    coalesce((p_item ->> 'done')::boolean, false),
    coalesce((p_item ->> 'position')::integer, 0),
    (p_item ->> 'created_at')::timestamptz,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    goal_id = excluded.goal_id,
    title = excluded.title,
    delivery_date = excluded.delivery_date,
    done = excluded.done,
    position = excluded.position,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where k.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.plan_tasks
    where user_id = auth.uid() and id = (p_item ->> 'id')::uuid;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.upsert_plan_tasks(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('id', v_item ->> 'id') || public.upsert_plan_task(v_item)
    );
  end loop;
  return v_results;
end;
$$;

-- soft_delete_plan_task(uuid, timestamptz) is unchanged (it does not read
-- target_id) and keeps its grants.

create or replace function public.pull_plan_tasks(p_since timestamptz default null, p_goal_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(k) order by k.server_updated_at, k.id)
      from public.plan_tasks k
      where k.user_id = auth.uid()
        and (p_since is null or k.server_updated_at > p_since)
        and (p_goal_id is null or k.goal_id = p_goal_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- consistent_actions (NEW: text items of a goal) ----------------------------

create or replace function public.upsert_consistent_action(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.consistent_actions;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.consistent_actions as a (
    user_id, id, goal_id, "text", sort_order, created_at, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'id')::uuid,
    (p_item ->> 'goal_id')::uuid,
    p_item ->> 'text',
    coalesce((p_item ->> 'sort_order')::integer, 0),
    (p_item ->> 'created_at')::timestamptz,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    goal_id = excluded.goal_id,
    "text" = excluded."text",
    sort_order = excluded.sort_order,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where a.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.consistent_actions
    where user_id = auth.uid() and id = (p_item ->> 'id')::uuid;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.upsert_consistent_actions(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('id', v_item ->> 'id') || public.upsert_consistent_action(v_item)
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_consistent_action(p_id uuid, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.consistent_actions;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.consistent_actions a
     set deleted_at = v_at, updated_at = v_at
   where a.user_id = auth.uid() and a.id = p_id and a.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.consistent_actions where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_consistent_actions(p_since timestamptz default null, p_goal_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.server_updated_at, a.id)
      from public.consistent_actions a
      where a.user_id = auth.uid()
        and (p_since is null or a.server_updated_at > p_since)
        and (p_goal_id is null or a.goal_id = p_goal_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- session_marks (key: time_block_id + date) ---------------------------------

create or replace function public.upsert_session_mark(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.session_marks;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.session_marks as m (
    user_id, time_block_id, date, attended, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'time_block_id')::uuid,
    (p_item ->> 'date')::date,
    (p_item ->> 'attended')::boolean,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, time_block_id, date) do update set
    attended = excluded.attended,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where m.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.session_marks
    where user_id = auth.uid()
      and time_block_id = (p_item ->> 'time_block_id')::uuid
      and date = (p_item ->> 'date')::date;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

-- Results carry "id" = "<timeBlockId>|<yyyy-MM-dd>" (the sync queue key).
create or replace function public.upsert_session_marks(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('id', (v_item ->> 'time_block_id') || '|' || (v_item ->> 'date'))
        || public.upsert_session_mark(v_item)
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_session_mark(
  p_time_block_id uuid,
  p_date date,
  p_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.session_marks;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.session_marks m
     set deleted_at = v_at, updated_at = v_at
   where m.user_id = auth.uid() and m.time_block_id = p_time_block_id and m.date = p_date
     and m.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.session_marks
  where user_id = auth.uid() and time_block_id = p_time_block_id and date = p_date;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_session_marks(p_since timestamptz default null, p_time_block_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.server_updated_at, m.time_block_id, m.date)
      from public.session_marks m
      where m.user_id = auth.uid()
        and (p_since is null or m.server_updated_at > p_since)
        and (p_time_block_id is null or m.time_block_id = p_time_block_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- Permissions: only signed-in users may call these. ---------------------------

revoke all on function public.upsert_goal(jsonb) from public, anon;
revoke all on function public.upsert_goals(jsonb) from public, anon;
revoke all on function public.soft_delete_goal(uuid, timestamptz) from public, anon;
revoke all on function public.pull_goals(timestamptz, uuid) from public, anon;
revoke all on function public.upsert_time_block(jsonb) from public, anon;
revoke all on function public.upsert_time_blocks(jsonb) from public, anon;
revoke all on function public.soft_delete_time_block(uuid, timestamptz) from public, anon;
revoke all on function public.pull_time_blocks(timestamptz, uuid) from public, anon;
revoke all on function public.upsert_plan_task(jsonb) from public, anon;
revoke all on function public.upsert_plan_tasks(jsonb) from public, anon;
revoke all on function public.soft_delete_plan_task(uuid, timestamptz) from public, anon;
revoke all on function public.pull_plan_tasks(timestamptz, uuid) from public, anon;
revoke all on function public.upsert_consistent_action(jsonb) from public, anon;
revoke all on function public.upsert_consistent_actions(jsonb) from public, anon;
revoke all on function public.soft_delete_consistent_action(uuid, timestamptz) from public, anon;
revoke all on function public.pull_consistent_actions(timestamptz, uuid) from public, anon;
revoke all on function public.upsert_session_mark(jsonb) from public, anon;
revoke all on function public.upsert_session_marks(jsonb) from public, anon;
revoke all on function public.soft_delete_session_mark(uuid, date, timestamptz) from public, anon;
revoke all on function public.pull_session_marks(timestamptz, uuid) from public, anon;

grant execute on function public.upsert_goal(jsonb) to authenticated;
grant execute on function public.upsert_goals(jsonb) to authenticated;
grant execute on function public.soft_delete_goal(uuid, timestamptz) to authenticated;
grant execute on function public.pull_goals(timestamptz, uuid) to authenticated;
grant execute on function public.upsert_time_block(jsonb) to authenticated;
grant execute on function public.upsert_time_blocks(jsonb) to authenticated;
grant execute on function public.soft_delete_time_block(uuid, timestamptz) to authenticated;
grant execute on function public.pull_time_blocks(timestamptz, uuid) to authenticated;
grant execute on function public.upsert_plan_task(jsonb) to authenticated;
grant execute on function public.upsert_plan_tasks(jsonb) to authenticated;
grant execute on function public.soft_delete_plan_task(uuid, timestamptz) to authenticated;
grant execute on function public.pull_plan_tasks(timestamptz, uuid) to authenticated;
grant execute on function public.upsert_consistent_action(jsonb) to authenticated;
grant execute on function public.upsert_consistent_actions(jsonb) to authenticated;
grant execute on function public.soft_delete_consistent_action(uuid, timestamptz) to authenticated;
grant execute on function public.pull_consistent_actions(timestamptz, uuid) to authenticated;
grant execute on function public.upsert_session_mark(jsonb) to authenticated;
grant execute on function public.upsert_session_marks(jsonb) to authenticated;
grant execute on function public.soft_delete_session_mark(uuid, date, timestamptz) to authenticated;
grant execute on function public.pull_session_marks(timestamptz, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. admin_stats v3: targets → goals, time blocks and consistent actions.
-- Same signature as v2 (20261114130000_admin_stats_projects.sql); only the
-- Projects keys of `totals` change: targets → goals, targets_done →
-- goals_done, plus time_blocks and consistent_actions. Sessions count under a
-- non-deleted time block of a live project (blocks no longer hang off a goal).
-- ---------------------------------------------------------------------------

create or replace function public.admin_stats(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'admin_stats: invalid range' using errcode = '22023';
  end if;

  with
  completed as (
    select c.user_id, c.date
    from public.check_ins c
    where c.completed and c.deleted_at is null
  ),
  completed_in_range as (
    select * from completed where date between p_from and p_to
  ),
  -- Sum of the numeric values of one ledger object of game_state.state.
  ledgers as (
    select
      g.state,
      floor(coalesce((
        select sum((e.value #>> '{}')::numeric)
        from jsonb_each(case when jsonb_typeof(g.state -> 'checkIns') = 'object'
          then g.state -> 'checkIns' else '{}'::jsonb end) e
        where jsonb_typeof(e.value) = 'number'
      ), 0)
      + coalesce((
        select sum((e.value #>> '{}')::numeric)
        from jsonb_each(case when jsonb_typeof(g.state -> 'perfectDays') = 'object'
          then g.state -> 'perfectDays' else '{}'::jsonb end) e
        where jsonb_typeof(e.value) = 'number'
      ), 0))::bigint as habit_xp,
      floor(coalesce((
        select sum((e.value #>> '{}')::numeric)
        from jsonb_each(case when jsonb_typeof(g.state -> 'projects') = 'object'
          then g.state -> 'projects' else '{}'::jsonb end) e
        where jsonb_typeof(e.value) = 'number'
      ), 0))::bigint as project_xp
    from public.game_state g
  ),
  game as (
    select
      l.habit_xp + l.project_xp as xp,
      l.project_xp,
      case when jsonb_typeof(l.state -> 'bestStreakEver') = 'number'
        then floor((l.state ->> 'bestStreakEver')::numeric)::bigint end as best_streak,
      case when jsonb_typeof(l.state -> 'maxLevelReached') = 'number'
        then floor((l.state ->> 'maxLevelReached')::numeric)::bigint end as level
    from ledgers l
  ),
  live_projects as (
    select p.user_id, p.id, p.archived, p.created_at
    from public.projects p
    where p.deleted_at is null
  ),
  -- Children count only while their parent is alive (the app tombstones the
  -- children of a deleted parent; this also covers a not-yet-synced one).
  live_goals as (
    select g.user_id, g.id, g.status
    from public.goals g
    join live_projects p on p.user_id = g.user_id and p.id = g.project_id
    where g.deleted_at is null
  ),
  live_time_blocks as (
    select b.user_id, b.id
    from public.time_blocks b
    join live_projects p on p.user_id = b.user_id and p.id = b.project_id
    where b.deleted_at is null
  ),
  attended as (
    select m.user_id, m.date
    from public.session_marks m
    join live_time_blocks b on b.user_id = m.user_id and b.id = m.time_block_id
    where m.attended and m.deleted_at is null
  ),
  attended_in_range as (
    select * from attended where date between p_from and p_to
  )
  select jsonb_build_object(
    'totals', jsonb_build_object(
      'users', (select count(*) from auth.users),
      'players', (select count(*) from public.game_state),
      'habits', (select count(*) from public.habits h where h.deleted_at is null),
      'active_habits', (select count(*) from public.habits h
        where h.deleted_at is null and not h.archived),
      'completions', (select count(*) from completed),
      'quotes', (select count(*) from public.quotes),
      'scheduled_quotes', (select count(*) from public.quotes q where q.day is not null),
      'quote_loves', (select count(*) from public.quote_loves),
      'xp', (select coalesce(sum(xp), 0) from game),
      'project_xp', (select coalesce(sum(project_xp), 0) from game),
      'projects', (select count(*) from live_projects),
      'active_projects', (select count(*) from live_projects where not archived),
      'users_with_projects', (select count(distinct user_id) from live_projects),
      'goals', (select count(*) from live_goals),
      'goals_done', (select count(*) from live_goals where status = 'done'),
      'plan_tasks_done', (select count(*) from public.plan_tasks k
        join live_goals g on g.user_id = k.user_id and g.id = k.goal_id
        where k.done and k.deleted_at is null),
      'time_blocks', (select count(*) from live_time_blocks),
      'consistent_actions', (select count(*) from public.consistent_actions a
        join live_goals g on g.user_id = a.user_id and g.id = a.goal_id
        where a.deleted_at is null),
      'sessions_attended', (select count(*) from attended)
    ),
    'in_range', jsonb_build_object(
      'signups', (select count(*) from auth.users u
        where (u.created_at at time zone 'utc')::date between p_from and p_to),
      'active_users', (select count(distinct user_id) from completed_in_range),
      'habits_created', (select count(*) from public.habits h
        where (h.created_at at time zone 'utc')::date between p_from and p_to),
      'completions', (select count(*) from completed_in_range),
      'quote_loves', (select count(*) from public.quote_loves l
        where (l.created_at at time zone 'utc')::date between p_from and p_to),
      'projects_created', (select count(*) from public.projects p
        where (p.created_at at time zone 'utc')::date between p_from and p_to),
      'sessions_attended', (select count(*) from attended_in_range)
    ),
    'signups', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d)
      from (
        select (u.created_at at time zone 'utc')::date as d, count(*) as n
        from auth.users u
        where (u.created_at at time zone 'utc')::date between p_from and p_to
        group by 1
      ) s
    ), '[]'::jsonb),
    'active', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d)
      from (
        select date as d, count(distinct user_id) as n from completed_in_range group by 1
      ) s
    ), '[]'::jsonb),
    'weekly_active', coalesce((
      select jsonb_agg(jsonb_build_object('w', w, 'n', n) order by w)
      from (
        select date_trunc('week', date)::date as w, count(distinct user_id) as n
        from completed_in_range group by 1
      ) s
    ), '[]'::jsonb),
    'habits_created', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d)
      from (
        select (h.created_at at time zone 'utc')::date as d, count(*) as n
        from public.habits h
        where (h.created_at at time zone 'utc')::date between p_from and p_to
        group by 1
      ) s
    ), '[]'::jsonb),
    'completions', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d)
      from (select date as d, count(*) as n from completed_in_range group by 1) s
    ), '[]'::jsonb),
    'loves', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d)
      from (
        select (l.created_at at time zone 'utc')::date as d, count(*) as n
        from public.quote_loves l
        where (l.created_at at time zone 'utc')::date between p_from and p_to
        group by 1
      ) s
    ), '[]'::jsonb),
    'sessions_attended', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d)
      from (select date as d, count(*) as n from attended_in_range group by 1) s
    ), '[]'::jsonb),
    'xp', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'n', n) order by v)
      from (select xp as v, count(*) as n from game group by 1) s
    ), '[]'::jsonb),
    'project_xp', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'n', n) order by v)
      from (select project_xp as v, count(*) as n from game group by 1) s
    ), '[]'::jsonb),
    'best_streak', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'n', n) order by v)
      from (select best_streak as v, count(*) as n from game
        where best_streak is not null group by 1) s
    ), '[]'::jsonb),
    'level', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'n', n) order by v)
      from (select level as v, count(*) as n from game where level is not null group by 1) s
    ), '[]'::jsonb),
    'top_quotes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'text', t.text, 'author', t.author, 'day', t.day, 'loves', t.loves
      ) order by t.loves desc, t.id)
      from (
        select q.id, q.text, q.author, q.day, count(*) as loves
        from public.quote_loves l
        join public.quotes q on q.id = l.quote_id
        group by q.id
        order by count(*) desc, q.id
        limit 10
      ) t
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

-- `create or replace` keeps the existing privileges; restate them anyway.
revoke all on function public.admin_stats(date, date) from public, anon, authenticated;
grant execute on function public.admin_stats(date, date) to service_role;
