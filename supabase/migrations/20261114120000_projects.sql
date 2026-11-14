-- Projects feature (docs/PROJECTS.md): projects, targets, plan_tasks,
-- consistent_actions and session_marks, with RLS and the last-write-wins
-- (LWW) functions used by the Edge Functions. Same rules as habits and
-- check_ins (20261007120000_schema.sql, 20261007120100_lww_functions.sql).
--
-- This migration only ADDS objects. It reuses (does not change) the helpers
-- public.set_server_updated_at() and public.sync_cursor_now().
--
-- Every row belongs to its user (user_id = auth.uid(), RLS) and is deleted
-- with the auth user (on delete cascade). Children reference their parent
-- per user with a composite foreign key (on delete cascade): a child can only
-- be written once its parent exists on the server (tombstoned parents count).
--
-- The overlap rule between consistent actions is NOT enforced here: it is an
-- app save rule (docs/PROJECTS.md "Overlap rule").

-- ---------------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------------

create table public.projects (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,
  name text not null check (char_length(name) between 1 and 200 and btrim(name) <> ''),
  archived boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index projects_user_server_updated_at_idx
  on public.projects (user_id, server_updated_at);

create trigger projects_set_server_updated_at
  before insert or update on public.projects
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- targets
-- ---------------------------------------------------------------------------

create table public.targets (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,
  project_id uuid not null,
  title text not null check (char_length(title) between 1 and 200 and btrim(title) <> ''),
  deadline date not null,
  status text not null default 'notStarted'
    check (status in ('notStarted', 'inProgress', 'done')),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint targets_project_fk foreign key (user_id, project_id)
    references public.projects (user_id, id) on delete cascade
);

create index targets_user_server_updated_at_idx
  on public.targets (user_id, server_updated_at);

create index targets_user_project_idx
  on public.targets (user_id, project_id);

create trigger targets_set_server_updated_at
  before insert or update on public.targets
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- plan_tasks
-- ---------------------------------------------------------------------------

create table public.plan_tasks (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,
  target_id uuid not null,
  title text not null check (char_length(title) between 1 and 200 and btrim(title) <> ''),
  delivery_date date,
  done boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint plan_tasks_target_fk foreign key (user_id, target_id)
    references public.targets (user_id, id) on delete cascade
);

create index plan_tasks_user_server_updated_at_idx
  on public.plan_tasks (user_id, server_updated_at);

create index plan_tasks_user_target_idx
  on public.plan_tasks (user_id, target_id);

create trigger plan_tasks_set_server_updated_at
  before insert or update on public.plan_tasks
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- consistent_actions
-- ---------------------------------------------------------------------------

-- Shape check for the recurrence JSON (the Edge Function validates it fully:
-- non-empty, sorted, no duplicates, in range).
create or replace function public.is_valid_action_recurrence(p jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_typeof(p) = 'object' and (
      (p ->> 'type' = 'weekly'
        and jsonb_typeof(p -> 'weekdays') = 'array'
        and jsonb_array_length(p -> 'weekdays') between 1 and 7)
      or
      (p ->> 'type' = 'monthly'
        and jsonb_typeof(p -> 'monthDays') = 'array'
        and jsonb_array_length(p -> 'monthDays') between 1 and 31)
    ),
    false
  );
$$;

create table public.consistent_actions (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,
  target_id uuid not null,
  start_time text not null check (start_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  end_time text not null check (end_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  recurrence jsonb not null check (public.is_valid_action_recurrence(recurrence)),
  start_date date,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id),
  -- "HH:mm" strings compare in time order. No block across midnight.
  constraint consistent_actions_end_after_start check (end_time > start_time),
  constraint consistent_actions_target_fk foreign key (user_id, target_id)
    references public.targets (user_id, id) on delete cascade
);

create index consistent_actions_user_server_updated_at_idx
  on public.consistent_actions (user_id, server_updated_at);

create index consistent_actions_user_target_idx
  on public.consistent_actions (user_id, target_id);

create trigger consistent_actions_set_server_updated_at
  before insert or update on public.consistent_actions
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- session_marks (keyed by action and day, like check_ins; no uuid)
-- ---------------------------------------------------------------------------

create table public.session_marks (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  action_id uuid not null,
  date date not null,
  attended boolean not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, action_id, date),
  constraint session_marks_action_fk foreign key (user_id, action_id)
    references public.consistent_actions (user_id, id) on delete cascade
);

create index session_marks_user_server_updated_at_idx
  on public.session_marks (user_id, server_updated_at);

create trigger session_marks_set_server_updated_at
  before insert or update on public.session_marks
  for each row execute function public.set_server_updated_at();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.projects enable row level security;
alter table public.targets enable row level security;
alter table public.plan_tasks enable row level security;
alter table public.consistent_actions enable row level security;
alter table public.session_marks enable row level security;

create policy "projects_select_own" on public.projects
  for select to authenticated using (user_id = (select auth.uid()));
create policy "projects_insert_own" on public.projects
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "projects_update_own" on public.projects
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "projects_delete_own" on public.projects
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "targets_select_own" on public.targets
  for select to authenticated using (user_id = (select auth.uid()));
create policy "targets_insert_own" on public.targets
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "targets_update_own" on public.targets
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "targets_delete_own" on public.targets
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "plan_tasks_select_own" on public.plan_tasks
  for select to authenticated using (user_id = (select auth.uid()));
create policy "plan_tasks_insert_own" on public.plan_tasks
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "plan_tasks_update_own" on public.plan_tasks
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "plan_tasks_delete_own" on public.plan_tasks
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "consistent_actions_select_own" on public.consistent_actions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "consistent_actions_insert_own" on public.consistent_actions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "consistent_actions_update_own" on public.consistent_actions
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "consistent_actions_delete_own" on public.consistent_actions
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "session_marks_select_own" on public.session_marks
  for select to authenticated using (user_id = (select auth.uid()));
create policy "session_marks_insert_own" on public.session_marks
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "session_marks_update_own" on public.session_marks
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "session_marks_delete_own" on public.session_marks
  for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.projects, public.targets, public.plan_tasks,
  public.consistent_actions, public.session_marks from anon;
grant select, insert, update, delete
  on public.projects, public.targets, public.plan_tasks,
    public.consistent_actions, public.session_marks
  to authenticated;

-- ---------------------------------------------------------------------------
-- LWW functions. SECURITY INVOKER (RLS applies, auth.uid() is the caller).
-- A write is applied only if nothing is stored or the incoming updated_at is
-- strictly greater than the stored one. Inputs are snake_case JSON objects
-- already validated by the Edge Function (_shared/validation.ts).
-- ---------------------------------------------------------------------------

-- projects ------------------------------------------------------------------

create or replace function public.upsert_project(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.projects;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.projects as p (
    user_id, id, name, archived, created_at, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'id')::uuid,
    p_item ->> 'name',
    coalesce((p_item ->> 'archived')::boolean, false),
    (p_item ->> 'created_at')::timestamptz,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    name = excluded.name,
    archived = excluded.archived,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at
  where p.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.projects
    where user_id = auth.uid() and id = (p_item ->> 'id')::uuid;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.upsert_projects(p_items jsonb)
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
      jsonb_build_object('id', v_item ->> 'id') || public.upsert_project(v_item)
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_project(p_id uuid, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.projects;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.projects p
     set deleted_at = v_at, updated_at = v_at
   where p.user_id = auth.uid() and p.id = p_id and p.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.projects where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_projects(p_since timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.server_updated_at, p.id)
      from public.projects p
      where p.user_id = auth.uid()
        and (p_since is null or p.server_updated_at > p_since)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- targets -------------------------------------------------------------------

create or replace function public.upsert_target(p_item jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.targets;
  v_applied boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.targets as t (
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
  where t.updated_at < excluded.updated_at
  returning * into v_row;

  if found then
    v_applied := true;
  else
    select * into v_row from public.targets
    where user_id = auth.uid() and id = (p_item ->> 'id')::uuid;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.upsert_targets(p_items jsonb)
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
      jsonb_build_object('id', v_item ->> 'id') || public.upsert_target(v_item)
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_target(p_id uuid, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.targets;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.targets t
     set deleted_at = v_at, updated_at = v_at
   where t.user_id = auth.uid() and t.id = p_id and t.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.targets where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_targets(p_since timestamptz default null, p_project_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.server_updated_at, t.id)
      from public.targets t
      where t.user_id = auth.uid()
        and (p_since is null or t.server_updated_at > p_since)
        and (p_project_id is null or t.project_id = p_project_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- plan_tasks ----------------------------------------------------------------

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
    user_id, id, target_id, title, delivery_date, done, position,
    created_at, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'id')::uuid,
    (p_item ->> 'target_id')::uuid,
    p_item ->> 'title',
    (p_item ->> 'delivery_date')::date,
    coalesce((p_item ->> 'done')::boolean, false),
    coalesce((p_item ->> 'position')::integer, 0),
    (p_item ->> 'created_at')::timestamptz,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    target_id = excluded.target_id,
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

create or replace function public.soft_delete_plan_task(p_id uuid, p_updated_at timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.plan_tasks;
  v_at timestamptz := coalesce(p_updated_at, now());
begin
  update public.plan_tasks k
     set deleted_at = v_at, updated_at = v_at
   where k.user_id = auth.uid() and k.id = p_id and k.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.plan_tasks where user_id = auth.uid() and id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_plan_tasks(p_since timestamptz default null, p_target_id uuid default null)
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
        and (p_target_id is null or k.target_id = p_target_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- consistent_actions --------------------------------------------------------

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
    user_id, id, target_id, start_time, end_time, recurrence, start_date,
    created_at, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'id')::uuid,
    (p_item ->> 'target_id')::uuid,
    p_item ->> 'start_time',
    p_item ->> 'end_time',
    p_item -> 'recurrence',
    (p_item ->> 'start_date')::date,
    (p_item ->> 'created_at')::timestamptz,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, id) do update set
    target_id = excluded.target_id,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    recurrence = excluded.recurrence,
    start_date = excluded.start_date,
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

create or replace function public.pull_consistent_actions(p_since timestamptz default null, p_target_id uuid default null)
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
        and (p_target_id is null or a.target_id = p_target_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- session_marks (key: action_id + date) -------------------------------------

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
    user_id, action_id, date, attended, updated_at, deleted_at
  ) values (
    auth.uid(),
    (p_item ->> 'action_id')::uuid,
    (p_item ->> 'date')::date,
    (p_item ->> 'attended')::boolean,
    (p_item ->> 'updated_at')::timestamptz,
    (p_item ->> 'deleted_at')::timestamptz
  )
  on conflict (user_id, action_id, date) do update set
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
      and action_id = (p_item ->> 'action_id')::uuid
      and date = (p_item ->> 'date')::date;
  end if;

  return jsonb_build_object('applied', v_applied, 'item', to_jsonb(v_row));
end;
$$;

-- Results carry "id" = "<actionId>|<yyyy-MM-dd>" (the sync queue key).
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
      jsonb_build_object('id', (v_item ->> 'action_id') || '|' || (v_item ->> 'date'))
        || public.upsert_session_mark(v_item)
    );
  end loop;
  return v_results;
end;
$$;

create or replace function public.soft_delete_session_mark(
  p_action_id uuid,
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
   where m.user_id = auth.uid() and m.action_id = p_action_id and m.date = p_date
     and m.updated_at < v_at
  returning * into v_row;

  if found then
    return jsonb_build_object('applied', true, 'item', to_jsonb(v_row));
  end if;

  select * into v_row from public.session_marks
  where user_id = auth.uid() and action_id = p_action_id and date = p_date;
  if not found then
    return null;
  end if;
  return jsonb_build_object('applied', false, 'item', to_jsonb(v_row));
end;
$$;

create or replace function public.pull_session_marks(p_since timestamptz default null, p_action_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.server_updated_at, m.action_id, m.date)
      from public.session_marks m
      where m.user_id = auth.uid()
        and (p_since is null or m.server_updated_at > p_since)
        and (p_action_id is null or m.action_id = p_action_id)
    ), '[]'::jsonb),
    'server_time', public.sync_cursor_now()
  );
$$;

-- ---------------------------------------------------------------------------
-- Permissions: only signed-in users may call these.
-- ---------------------------------------------------------------------------

revoke all on function public.upsert_project(jsonb) from public, anon;
revoke all on function public.upsert_projects(jsonb) from public, anon;
revoke all on function public.soft_delete_project(uuid, timestamptz) from public, anon;
revoke all on function public.pull_projects(timestamptz) from public, anon;
revoke all on function public.upsert_target(jsonb) from public, anon;
revoke all on function public.upsert_targets(jsonb) from public, anon;
revoke all on function public.soft_delete_target(uuid, timestamptz) from public, anon;
revoke all on function public.pull_targets(timestamptz, uuid) from public, anon;
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

grant execute on function public.upsert_project(jsonb) to authenticated;
grant execute on function public.upsert_projects(jsonb) to authenticated;
grant execute on function public.soft_delete_project(uuid, timestamptz) to authenticated;
grant execute on function public.pull_projects(timestamptz) to authenticated;
grant execute on function public.upsert_target(jsonb) to authenticated;
grant execute on function public.upsert_targets(jsonb) to authenticated;
grant execute on function public.soft_delete_target(uuid, timestamptz) to authenticated;
grant execute on function public.pull_targets(timestamptz, uuid) to authenticated;
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
