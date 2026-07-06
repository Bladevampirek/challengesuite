-- ============================================================
-- Record Challenge Suite - Supabase Global Leaderboard Setup
-- Run in Supabase SQL Editor.
-- Public browser users can read Top 20 and submit through RPC.
-- Do not expose service_role/secret keys in the GitHub Pages game.
-- ============================================================

create table if not exists public.leaderboard_scores (
  id bigint generated always as identity primary key,

  challenge_id text not null,
  player_name text not null check (char_length(player_name) between 1 and 24),
  player_name_key text generated always as (lower(btrim(player_name))) stored,

  time_ms integer not null check (time_ms > 0 and time_ms < 120000),
  status text not null check (status in ('PASS', 'FAILED')),

  splits_ms integer[] not null default '{}',
  movement_m numeric(10, 3) not null default 0,
  best_split_ms integer,
  accuracy numeric(6, 2) not null default 0,
  shots integer not null default 0,
  misses integer not null default 0,
  reloads integer not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (challenge_id, player_name_key)
);

alter table public.leaderboard_scores enable row level security;

grant usage on schema public to anon;
grant select on public.leaderboard_scores to anon;
revoke insert, update, delete on public.leaderboard_scores from anon;
revoke insert, update, delete on public.leaderboard_scores from authenticated;

drop policy if exists "public can read leaderboard" on public.leaderboard_scores;
create policy "public can read leaderboard"
on public.leaderboard_scores
for select
to anon
using (true);

-- Browser users do not get insert/update/delete table policies.
-- Submissions go through the controlled SECURITY DEFINER function below.

create or replace function public.submit_leaderboard_score(
  p_challenge_id text,
  p_player_name text,
  p_time_ms integer,
  p_status text,
  p_splits_ms integer[] default '{}',
  p_movement_m numeric default 0,
  p_best_split_ms integer default null,
  p_accuracy numeric default 0,
  p_shots integer default 0,
  p_misses integer default 0,
  p_reloads integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text;
  existing_id bigint;
  existing_time integer;
  row_count integer;
  worst_top20_time integer;
  final_id bigint;
  final_rank integer;
begin
  clean_name := left(regexp_replace(btrim(p_player_name), '\s+', ' ', 'g'), 24);

  if clean_name = '' then
    return jsonb_build_object('accepted', false, 'reason', 'Name required');
  end if;

  if p_challenge_id is null or btrim(p_challenge_id) = '' then
    return jsonb_build_object('accepted', false, 'reason', 'Challenge required');
  end if;

  if p_time_ms <= 0 or p_time_ms >= 120000 then
    return jsonb_build_object('accepted', false, 'reason', 'Invalid time');
  end if;

  if p_status not in ('PASS', 'FAILED') then
    return jsonb_build_object('accepted', false, 'reason', 'Invalid status');
  end if;

  select id, time_ms
  into existing_id, existing_time
  from public.leaderboard_scores
  where challenge_id = p_challenge_id
    and player_name_key = lower(clean_name)
  limit 1;

  -- Same name already exists on this challenge.
  -- Only replace if the new milliseconds are lower.
  if existing_id is not null then
    if p_time_ms < existing_time then
      update public.leaderboard_scores
      set
        player_name = clean_name,
        time_ms = p_time_ms,
        status = p_status,
        splits_ms = coalesce(p_splits_ms, '{}'),
        movement_m = coalesce(p_movement_m, 0),
        best_split_ms = p_best_split_ms,
        accuracy = coalesce(p_accuracy, 0),
        shots = coalesce(p_shots, 0),
        misses = coalesce(p_misses, 0),
        reloads = coalesce(p_reloads, 0),
        updated_at = now()
      where id = existing_id
      returning id into final_id;
    else
      final_id := existing_id;

      select rank_num
      into final_rank
      from (
        select id, row_number() over (order by time_ms asc, updated_at asc, id asc) as rank_num
        from public.leaderboard_scores
        where challenge_id = p_challenge_id
      ) ranked
      where id = final_id;

      return jsonb_build_object(
        'accepted', false,
        'kept_existing', true,
        'reason', 'Existing score is faster or equal',
        'rank', final_rank,
        'existing_time_ms', existing_time
      );
    end if;
  else
    -- New name. Only accept if leaderboard has room,
    -- or if this score beats the current 20th place.
    select count(*)
    into row_count
    from public.leaderboard_scores
    where challenge_id = p_challenge_id;

    select max(time_ms)
    into worst_top20_time
    from (
      select time_ms
      from public.leaderboard_scores
      where challenge_id = p_challenge_id
      order by time_ms asc, updated_at asc, id asc
      limit 20
    ) top20;

    if row_count >= 20 and p_time_ms >= worst_top20_time then
      return jsonb_build_object(
        'accepted', false,
        'reason', 'Score did not beat the Top 20',
        'needed_below_ms', worst_top20_time
      );
    end if;

    insert into public.leaderboard_scores (
      challenge_id, player_name, time_ms, status, splits_ms,
      movement_m, best_split_ms, accuracy, shots, misses, reloads
    )
    values (
      p_challenge_id, clean_name, p_time_ms, p_status, coalesce(p_splits_ms, '{}'),
      coalesce(p_movement_m, 0), p_best_split_ms, coalesce(p_accuracy, 0),
      coalesce(p_shots, 0), coalesce(p_misses, 0), coalesce(p_reloads, 0)
    )
    returning id into final_id;
  end if;

  -- Keep only Top 20 per challenge.
  with ranked as (
    select id,
      row_number() over (
        partition by challenge_id
        order by time_ms asc, updated_at asc, id asc
      ) as rn
    from public.leaderboard_scores
  )
  delete from public.leaderboard_scores
  where id in (select id from ranked where rn > 20);

  select rank_num
  into final_rank
  from (
    select id,
      row_number() over (order by time_ms asc, updated_at asc, id asc) as rank_num
    from public.leaderboard_scores
    where challenge_id = p_challenge_id
  ) ranked_current
  where id = final_id;

  return jsonb_build_object(
    'accepted', final_rank is not null and final_rank <= 20,
    'rank', final_rank,
    'id', final_id,
    'time_ms', p_time_ms,
    'status', p_status
  );
end;
$$;

revoke all on function public.submit_leaderboard_score(
  text, text, integer, text, integer[], numeric, integer, numeric, integer, integer, integer
) from public;

grant execute on function public.submit_leaderboard_score(
  text, text, integer, text, integer[], numeric, integer, numeric, integer, integer, integer
) to anon;

-- Optional read RPC used by the game. The game also has a direct SELECT fallback,
-- but this RPC keeps leaderboard reads clean and stable.
create or replace function public.get_leaderboard_scores(
  p_challenge_id text
)
returns table (
  rank integer,
  id bigint,
  player_name text,
  time_ms integer,
  status text,
  best_split_ms integer,
  accuracy numeric,
  movement_m numeric,
  shots integer,
  misses integer,
  reloads integer,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    row_number() over (order by time_ms asc, updated_at asc, id asc)::integer as rank,
    id,
    player_name,
    time_ms,
    status,
    best_split_ms,
    accuracy,
    movement_m,
    shots,
    misses,
    reloads,
    updated_at
  from public.leaderboard_scores
  where challenge_id = p_challenge_id
  order by time_ms asc, updated_at asc, id asc
  limit 20;
$$;

revoke all on function public.get_leaderboard_scores(text) from public;
grant execute on function public.get_leaderboard_scores(text) to anon;
