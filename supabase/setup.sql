-- RangaSwang live stats
-- Paste this whole file into Supabase → SQL Editor → New query, then click Run.
-- It is safe to run again later: it only adds what's missing and refreshes the functions.
--
-- What it stores
--   shots   one row per question a player answers: the day, which question, how good the strike was.
--           Powers "41% of players were within 10% on this one."
--   rounds  one row per finished daily round: name, strokes per hole, total. Powers the leaderboard.
-- Players are identified only by a random device code made by their browser. No emails, no accounts.
--
-- Moderation: to pull a name off the leaderboard, open Table Editor → rounds and set "hidden" to true.
-- The score still counts toward the day's averages. Rude names are hidden automatically.

-- ---------- tables ----------
create table if not exists public.shots (
  day        date        not null,
  device     uuid        not null,
  qid        text        not null check (char_length(qid) between 3 and 40),
  tier       text        not null check (tier in ('E', 'M', 'H')),
  quality    text        not null check (quality in ('perfect', 'solid', 'ok', 'mishit', 'shank', 'whiff')),
  hole       smallint    check (hole between 1 and 3),
  shot       smallint    check (shot between 1 and 8),
  bonus      boolean     not null default false,
  created_at timestamptz not null default now(),
  primary key (device, qid)
);
create index if not exists shots_qid_idx on public.shots (qid);
create index if not exists shots_day_idx on public.shots (day);

create table if not exists public.rounds (
  day        date        not null,
  device     uuid        not null,
  name       text        not null default 'Rookie',
  scores     smallint[]  not null,
  total      smallint    not null,
  to_par     smallint    not null,
  perfects   smallint    not null default 0,
  hidden     boolean     not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (day, device)
);
create index if not exists rounds_board_idx on public.rounds (day, total, perfects desc, created_at);

-- Nobody reads or writes these tables directly. The site can only call the functions below.
alter table public.shots  enable row level security;
alter table public.rounds enable row level security;
revoke all on public.shots, public.rounds from anon, authenticated;

-- ---------- record one answered question ----------
create or replace function public.record_shot(
  p_day date, p_device uuid, p_qid text, p_tier text, p_quality text,
  p_hole int default null, p_shot int default null, p_bonus boolean default false)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_day is null or p_device is null or p_day < current_date - 2 or p_day > current_date + 1 then
    return;
  end if;
  insert into shots (day, device, qid, tier, quality, hole, shot, bonus)
  values (p_day, p_device, p_qid, p_tier, p_quality, p_hole, p_shot, coalesce(p_bonus, false))
  on conflict (device, qid) do nothing;
exception when check_violation or not_null_violation then
  return;
end
$$;

-- ---------- how everyone did on some questions ----------
create or replace function public.question_stats(p_qids text[])
returns json
language sql stable security definer set search_path = public
as $$
  select coalesce(json_object_agg(qid, s), '{}'::json)
  from (
    select qid, json_build_object(
      'n',       count(*),
      'perfect', count(*) filter (where quality = 'perfect'),
      'solid',   count(*) filter (where quality = 'solid'),
      'ok',      count(*) filter (where quality = 'ok'),
      'mishit',  count(*) filter (where quality = 'mishit'),
      'shank',   count(*) filter (where quality = 'shank'),
      'whiff',   count(*) filter (where quality = 'whiff')) as s
    from shots
    where qid = any (p_qids[1:200])
    group by qid
  ) t
$$;

-- ---------- today's field and leaderboard ----------
create or replace function public.day_board(p_day date, p_device uuid default null, p_limit int default 10)
returns json
language sql stable security definer set search_path = public
as $$
  with r as (
    select * from rounds where day = p_day
  ), ranked as (
    select r.*,
           rank()       over (order by total, perfects desc)             as rnk,
           row_number() over (order by total, perfects desc, created_at) as pos
    from r
  ), me as (
    select * from ranked where device = p_device
  )
  select json_build_object(
    'players',   (select count(*) from r),
    'avg_total', (select round(avg(total), 2) from r),
    'avg',       json_build_array(
                   (select round(avg(scores[1]), 2) from r),
                   (select round(avg(scores[2]), 2) from r),
                   (select round(avg(scores[3]), 2) from r)),
    'under',     json_build_array(
                   (select count(*) filter (where scores[1] < 5) from r),
                   (select count(*) filter (where scores[2] < 4) from r),
                   (select count(*) filter (where scores[3] < 3) from r)),
    'top', coalesce((
      select json_agg(json_build_object(
               'rank', rnk, 'name', name, 'total', total, 'to_par', to_par,
               'perfects', perfects, 'me', device = p_device) order by pos)
      from (
        select * from ranked
        where not hidden or device = p_device
        order by pos
        limit greatest(1, least(coalesce(p_limit, 10), 50))
      ) t), '[]'::json),
    'me', (
      select json_build_object(
               'rank', rnk, 'name', name, 'total', total, 'to_par', to_par,
               'beat', (select count(*) from r where r.total > me.total))
      from me)
  )
$$;

-- ---------- submit a finished daily round (the first score counts; the name can change) ----------
create or replace function public.submit_round(
  p_day date, p_device uuid, p_name text, p_scores int[], p_perfects int default 0)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  pars    constant int[] := array[5, 4, 3];
  v_name  text;
  v_total int := 0;
  v_hide  boolean;
begin
  if p_day is null or p_device is null or p_day < current_date - 2 or p_day > current_date + 1 then
    return null;
  end if;
  if p_scores is null or coalesce(array_length(p_scores, 1), 0) <> 3 then
    return null;
  end if;
  for i in 1..3 loop
    if p_scores[i] is null or p_scores[i] < 1 or p_scores[i] > pars[i] + 3 then
      return null;
    end if;
    v_total := v_total + p_scores[i];
  end loop;

  v_name := regexp_replace(coalesce(p_name, ''), '[^A-Za-z0-9 ._''-]', '', 'g');
  v_name := left(btrim(regexp_replace(v_name, '\s+', ' ', 'g')), 18);
  if v_name = '' then v_name := 'Rookie'; end if;
  v_hide := lower(regexp_replace(v_name, '[^A-Za-z]', '', 'g'))
            ~ '(fuck|shit|cunt|nigg|fag|bitch|dick|cock|pussy|slut|whore|rape|nazi|hitler)';

  insert into rounds (day, device, name, scores, total, to_par, perfects, hidden)
  values (p_day, p_device, v_name, p_scores::smallint[], v_total, v_total - 12,
          greatest(0, least(coalesce(p_perfects, 0), 21)), v_hide)
  on conflict (day, device) do update
    set name = excluded.name,
        hidden = excluded.hidden or rounds.hidden,
        updated_at = now();

  return public.day_board(p_day, p_device, 10);
end
$$;

-- ---------- who may call what ----------
revoke all on function public.record_shot(date, uuid, text, text, text, int, int, boolean) from public;
revoke all on function public.question_stats(text[])                                       from public;
revoke all on function public.day_board(date, uuid, int)                                   from public;
revoke all on function public.submit_round(date, uuid, text, int[], int)                   from public;
grant execute on function public.record_shot(date, uuid, text, text, text, int, int, boolean) to anon, authenticated;
grant execute on function public.question_stats(text[])                                       to anon, authenticated;
grant execute on function public.day_board(date, uuid, int)                                   to anon, authenticated;
grant execute on function public.submit_round(date, uuid, text, int[], int)                   to anon, authenticated;

-- ---------- for you: growth at a glance (Table Editor or SQL: select * from daily_activity) ----------
create or replace view public.daily_activity with (security_invoker = on) as
  select coalesce(s.day, r.day)  as day,
         coalesce(s.started, 0)  as players_started,
         coalesce(r.finished, 0) as rounds_finished,
         r.avg_strokes,
         r.best_round
  from (select day, count(distinct device) as started from public.shots where not bonus group by day) s
  full join (select day, count(*) as finished, round(avg(total), 2) as avg_strokes, min(total) as best_round
             from public.rounds group by day) r on r.day = s.day
  order by 1 desc;
revoke all on public.daily_activity from anon, authenticated;
