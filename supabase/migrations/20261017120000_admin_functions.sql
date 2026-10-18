-- Admin console backend: read-only SQL used by the `admin-quotes` and
-- `admin-stats` Edge Functions (see supabase/API.md).
--
-- Both functions are SECURITY DEFINER (they read across users and auth.users)
-- and are executable by the service role ONLY: the Edge Functions call them
-- with a service-role client, after the admin check (service role or an email
-- in QUOTE_ADMINS). anon and authenticated cannot call them, so a signed-in
-- user cannot bypass that check through PostgREST.
--
-- They return aggregates only: counts per day/week, histograms of values and
-- the most-loved quotes. No user id, email, habit name or other per-user
-- detail ever leaves the database.

-- ---------------------------------------------------------------------------
-- admin_list_quotes: every quote (past, today, scheduled, unscheduled) with
-- its love count, searched and filtered.
--
--   p_query      case-insensitive substring of text or author (null = any)
--   p_from/p_to  inclusive day range; either given → scheduled quotes only
--   p_scheduled  'all' | 'scheduled' | 'unscheduled'
--   p_limit      1..500, p_offset >= 0
--
-- Order: unscheduled first, then day descending (newest/furthest first),
-- then created_at descending, then id.
-- Returns {"total": n, "items": [{id, text, author, day, created_at,
-- updated_at, loves}]}.
-- ---------------------------------------------------------------------------

create or replace function public.admin_list_quotes(
  p_query text,
  p_from date,
  p_to date,
  p_scheduled text,
  p_limit integer,
  p_offset integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pattern text;
  v_result jsonb;
begin
  if p_query is not null and btrim(p_query) <> '' then
    -- Escape LIKE wildcards so the query is a plain substring.
    v_pattern := '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_')
      || '%';
  end if;

  with filtered as (
    select q.*
    from public.quotes q
    where (v_pattern is null or q.text ilike v_pattern or coalesce(q.author, '') ilike v_pattern)
      and (p_from is null or q.day >= p_from)
      and (p_to is null or q.day <= p_to)
      and (coalesce(p_scheduled, 'all') <> 'scheduled' or q.day is not null)
      and (coalesce(p_scheduled, 'all') <> 'unscheduled' or q.day is null)
  ),
  page as (
    select f.*,
      (select count(*) from public.quote_loves l where l.quote_id = f.id) as loves
    from filtered f
    order by f.day desc nulls first, f.created_at desc, f.id
    limit greatest(1, least(coalesce(p_limit, 100), 500))
    offset greatest(0, coalesce(p_offset, 0))
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'text', p.text,
        'author', p.author,
        'day', p.day,
        'created_at', p.created_at,
        'updated_at', p.updated_at,
        'loves', p.loves
      ) order by p.day desc nulls first, p.created_at desc, p.id)
      from page p
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_stats: aggregates for [p_from, p_to] (inclusive, UTC days).
--
-- Sparse series ({"d": day, "n": count}, days without data omitted; the Edge
-- Function fills the gaps with zeros and derives the weekly sums):
--   signups         auth.users.created_at
--   active          distinct users with >= 1 completed check-in dated that day
--   habits_created  habits.created_at (the client's creation time)
--   completions     completed, non-deleted check-ins by their date
--   loves           quote_loves.created_at (loves still present)
-- weekly_active: {"w": monday, "n": distinct users}, ISO weeks overlapping
-- the range (only check-ins inside the range count).
-- Histograms ({"v": value, "n": users}) over users with a synced game state:
--   xp           sum of the numeric values of state.checkIns + state.perfectDays
--   best_streak  state.bestStreakEver
--   level        state.maxLevelReached
-- top_quotes: the 10 most-loved quotes of all time.
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
  game as (
    select
      floor(
        coalesce((
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
        ), 0)
      )::bigint as xp,
      case when jsonb_typeof(g.state -> 'bestStreakEver') = 'number'
        then floor((g.state ->> 'bestStreakEver')::numeric)::bigint end as best_streak,
      case when jsonb_typeof(g.state -> 'maxLevelReached') = 'number'
        then floor((g.state ->> 'maxLevelReached')::numeric)::bigint end as level
    from public.game_state g
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
      'quote_loves', (select count(*) from public.quote_loves)
    ),
    'in_range', jsonb_build_object(
      'signups', (select count(*) from auth.users u
        where (u.created_at at time zone 'utc')::date between p_from and p_to),
      'active_users', (select count(distinct user_id) from completed_in_range),
      'habits_created', (select count(*) from public.habits h
        where (h.created_at at time zone 'utc')::date between p_from and p_to),
      'completions', (select count(*) from completed_in_range),
      'quote_loves', (select count(*) from public.quote_loves l
        where (l.created_at at time zone 'utc')::date between p_from and p_to)
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
    'xp', coalesce((
      select jsonb_agg(jsonb_build_object('v', v, 'n', n) order by v)
      from (select xp as v, count(*) as n from game group by 1) s
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

-- Service role only (the Edge Functions, after the admin check).
revoke all on function public.admin_list_quotes(text, date, date, text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.admin_stats(date, date) from public, anon, authenticated;
grant execute on function public.admin_list_quotes(text, date, date, text, integer, integer)
  to service_role;
grant execute on function public.admin_stats(date, date) to service_role;
