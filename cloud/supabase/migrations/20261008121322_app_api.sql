-- Add a meter to my account. The PoP comes from the QR code on the label,
-- so only someone holding the meter can claim it.
create or replace function public.claim_device(p_id text, p_pop text, p_name text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if not exists (select 1 from private.device_keys k
                 where k.device_id = p_id and k.pop_hash = private.sha256(p_pop)) then
    return jsonb_build_object('ok', false, 'error',
      case when exists (select 1 from public.devices where id = p_id) then 'wrong_code' else 'not_online_yet' end);
  end if;
  if exists (select 1 from public.device_members where device_id = p_id and role = 'owner' and user_id <> uid) then
    return jsonb_build_object('ok', false, 'error', 'already_claimed');
  end if;
  insert into public.device_members (device_id, user_id, role) values (p_id, uid, 'owner')
    on conflict (device_id, user_id) do update set role = 'owner';
  update public.devices set claimed_at = coalesce(claimed_at, now()),
                            name = coalesce(nullif(trim(p_name), ''), name)
    where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Turn pending invitations for my e-mail address into memberships.
create or replace function public.accept_invites()
returns integer language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); mail text := lower(auth.jwt() ->> 'email'); n integer;
begin
  if uid is null or mail is null then return 0; end if;
  with acc as (
    update public.invites set accepted_at = now()
    where lower(email) = mail and accepted_at is null
    returning device_id, role)
  insert into public.device_members (device_id, user_id, role)
  select device_id, uid, role from acc
  on conflict (device_id, user_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Energy per hour / day / month in the meter's local time.
create or replace function public.get_energy(p_id text, p_from timestamptz, p_to timestamptz, p_bucket text)
returns table (bucket timestamptz, kwh double precision)
language sql stable security invoker set search_path = '' as $$
  with d as (select timezone from public.devices where id = p_id),
  r as (
    select ts, energy_dwh - lag(energy_dwh) over (order by ts) as delta
    from public.readings
    where device_id = p_id and ts > p_from - interval '1 day' and ts <= p_to
  )
  select (date_trunc(p_bucket, r.ts at time zone d.timezone) at time zone d.timezone) as bucket,
         sum(greatest(r.delta, 0)) / 10000.0 as kwh
  from r, d
  where r.ts > p_from and r.delta is not null and p_bucket in ('hour', 'day', 'month')
  group by 1
  order by 1
$$;

grant update (name, timezone, currency, tariff, billing_day, alert_power_w, alert_offline_min)
  on public.devices to authenticated;
grant execute on function public.device_hello, public.device_push to anon, authenticated;
grant execute on function public.claim_device, public.accept_invites, public.get_energy to authenticated;

alter publication supabase_realtime add table public.device_live, public.alerts;
