-- admin_stats v2: adds the Projects XP ledger and cheap Projects usage counts.
--
-- DEPENDS ON 20261114120000_projects.sql (it reads public.projects,
-- public.targets, public.plan_tasks, public.consistent_actions and
-- public.session_marks), so it must be applied after it. It replaces the
-- admin_stats of 20261017120000_admin_functions.sql (already applied; that
-- file is not edited) with `create or replace`: same signature, same
-- SECURITY DEFINER + service-role-only grants.
--
-- Changes against v1 (see supabase/API.md, "Function admin-stats"):
--   * xp (histogram) and totals.xp now add the project XP ledger
--     state.projects ({"task:<id>": 10, "session:<action>|<date>": 15,
--     "target:<id>": 50}) to state.checkIns + state.perfectDays, so they
--     match GameState.xp in the app (lib/features/game/game_state.dart).
--   * project_xp: histogram of state.projects alone; totals.project_xp.
--   * totals: projects, active_projects, users_with_projects, targets,
--     targets_done, plan_tasks_done, sessions_attended.
--   * in_range: projects_created, sessions_attended.
--   * sessions_attended: sparse daily series by session date.
-- Every other key is unchanged. Still aggregates only: no user id, email,
-- project name or target title ever leaves the database.

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
  live_targets as (
    select t.user_id, t.id, t.status
    from public.targets t
    join live_projects p on p.user_id = t.user_id and p.id = t.project_id
    where t.deleted_at is null
  ),
  attended as (
    select m.user_id, m.date
    from public.session_marks m
    join public.consistent_actions a
      on a.user_id = m.user_id and a.id = m.action_id and a.deleted_at is null
    join live_targets t on t.user_id = a.user_id and t.id = a.target_id
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
      'targets', (select count(*) from live_targets),
      'targets_done', (select count(*) from live_targets where status = 'done'),
      'plan_tasks_done', (select count(*) from public.plan_tasks k
        join live_targets t on t.user_id = k.user_id and t.id = k.target_id
        where k.done and k.deleted_at is null),
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
