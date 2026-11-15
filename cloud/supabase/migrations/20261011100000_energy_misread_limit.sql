-- A misread power peak can also land below 65535 W (seen: 50,004 W from a
-- 60 W load). Anything over 30 kW is impossible for a home meter (and is
-- what firmware 0.4.4 rejects), so that is the misread limit now.
create or replace function public.get_energy(p_id text, p_from timestamptz, p_to timestamptz, p_bucket text)
returns table(bucket timestamptz, kwh double precision)
language sql
stable
set search_path to ''
as $function$
  with d as (select timezone from public.devices where id = p_id),
  r0 as (
    select ts, p_max,
           energy_dwh - lag(energy_dwh) over (order by ts) as delta,
           extract(epoch from ts - lag(ts) over (order by ts)) / 3600.0 as dt_h
    from public.readings
    where device_id = p_id and ts > p_from - interval '1 day' and ts <= p_to
  ),
  r as (
    select ts,
           greatest(delta, 0) as delta,
           coalesce(p_max > 30000, false) as glitch,
           -- energy_dwh is in 0.1 Wh: W * h * 10, +10 %, +5 (0.5 Wh)
           case when p_max is null or p_max > 30000 then null else p_max * dt_h * 11 + 5 end as cap
    from r0
    where delta is not null
  ),
  c as (
    select ts,
           case
             when glitch then least(delta, coalesce(avg(case when not glitch then least(delta, coalesce(cap, delta)) end)
                 over (order by ts range between interval '1 hour' preceding and interval '1 hour' following), 0))
             else least(delta, coalesce(cap, delta))
           end as delta
    from r
  )
  select (date_trunc(p_bucket, c.ts at time zone d.timezone) at time zone d.timezone) as bucket,
         sum(c.delta) / 10000.0 as kwh
  from c, d
  where c.ts > p_from and p_bucket in ('hour', 'day', 'month')
  group by 1
  order by 1
$function$;
