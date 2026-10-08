-- SEM-1 cloud: core schema
--
-- Who talks to the database:
--   * meters  -> only through device_hello() / device_push() (anon key + per-unit secret)
--   * the app -> as a logged-in user, protected by row-level security (RLS):
--                a user only ever sees meters they own or that were shared with them.
--
-- Secrets are never stored readable: the meter's 32-char secret and the 8-char
-- QR "proof of possession" are kept as SHA-256 hashes in the private schema,
-- which the API does not expose.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------- tables

create table public.devices (
  id               text primary key check (id ~ '^SEM1-[0-9A-F]{6}$'),
  name             text not null default 'My home' check (char_length(name) between 1 and 40),
  fw               text,
  hw               text,
  created_at       timestamptz not null default now(),
  claimed_at       timestamptz,
  last_seen        timestamptz,
  -- user settings (owner can change)
  timezone         text not null default 'Asia/Riyadh',
  currency         text not null default 'SAR' check (char_length(currency) = 3),
  -- tiered tariff: price per kWh for each block of monthly consumption;
  -- the last tier has no upto_kwh. Default: Saudi residential (SEC).
  tariff           jsonb not null default '{"tiers":[{"upto_kwh":6000,"price":0.18},{"price":0.30}],"monthly_fixed":0}',
  billing_day      smallint not null default 1 check (billing_day between 1 and 28),
  alert_power_w    integer check (alert_power_w is null or alert_power_w between 100 and 30000),
  alert_offline_min integer not null default 15 check (alert_offline_min between 5 and 1440),
  -- alert state (managed by the server)
  high_power_active boolean not null default false
);

create table private.device_keys (
  device_id   text primary key references public.devices(id) on delete cascade,
  secret_hash text not null,
  pop_hash    text not null
);

create table public.device_members (
  device_id text not null references public.devices(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  role      text not null check (role in ('owner', 'member')),
  added_at  timestamptz not null default now(),
  primary key (device_id, user_id)
);
create index on public.device_members (user_id);
-- exactly one owner per meter
create unique index device_one_owner on public.device_members (device_id) where role = 'owner';

create table public.invites (
  id          uuid primary key default gen_random_uuid(),
  device_id   text not null references public.devices(id) on delete cascade,
  email       text not null check (position('@' in email) > 1),
  role        text not null default 'member' check (role in ('member')),
  invited_by  uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  unique (device_id, email)
);

-- latest live values, one row per meter (the app subscribes to changes)
create table public.device_live (
  device_id  text primary key references public.devices(id) on delete cascade,
  ts         timestamptz not null,
  v          real, i real, p real, s real, pf real,
  kwh        double precision,
  rssi       smallint,
  updated_at timestamptz not null default now()
);

-- 5-minute history from the meter's flash log. energy_dwh is the meter's
-- lifetime counter (0.1 Wh); consumption = difference between records.
create table public.readings (
  device_id  text not null references public.devices(id) on delete cascade,
  ts         timestamptz not null,
  energy_dwh bigint not null check (energy_dwh >= 0),
  p_avg      integer,
  p_max      integer,
  v_avg      real,
  flags      smallint not null default 0,
  primary key (device_id, ts)
);

create table public.alerts (
  id          bigint generated always as identity primary key,
  device_id   text not null references public.devices(id) on delete cascade,
  kind        text not null check (kind in ('high_power', 'offline')),
  value       real,
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);
create index on public.alerts (device_id, created_at desc);

-- ---------------------------------------------------------------- helpers

create or replace function private.sha256(t text) returns text
language sql immutable set search_path = '' as
$$ select encode(extensions.digest(t, 'sha256'), 'hex') $$;

create or replace function public.is_member(p_device text) returns boolean
language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.device_members m
                  where m.device_id = p_device and m.user_id = (select auth.uid())) $$;

create or replace function public.is_owner(p_device text) returns boolean
language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.device_members m
                  where m.device_id = p_device and m.user_id = (select auth.uid()) and m.role = 'owner') $$;

-- check a meter's secret; returns true when it matches
create or replace function private.device_auth(p_id text, p_secret text) returns boolean
language sql stable set search_path = '' as
$$ select exists (select 1 from private.device_keys k
                  where k.device_id = p_id and k.secret_hash = private.sha256(p_secret)) $$;

-- ---------------------------------------------------------------- RLS

alter table public.devices        enable row level security;
alter table public.device_members enable row level security;
alter table public.invites        enable row level security;
alter table public.device_live    enable row level security;
alter table public.readings       enable row level security;
alter table public.alerts         enable row level security;
alter table private.device_keys   enable row level security;

create policy "members read their meters" on public.devices
  for select to authenticated using ((select public.is_member(id)));
create policy "owner edits settings" on public.devices
  for update to authenticated using ((select public.is_owner(id))) with check ((select public.is_owner(id)));
-- only these columns may be changed from the app
revoke update on public.devices from authenticated, anon;
grant update (name, timezone, currency, tariff, billing_day, alert_power_w, alert_offline_min)
  on public.devices to authenticated;

create policy "members see who shares" on public.device_members
  for select to authenticated using ((select public.is_member(device_id)));
create policy "owner removes members, members can leave" on public.device_members
  for delete to authenticated
  using (role = 'member' and ((select public.is_owner(device_id)) or user_id = (select auth.uid())));

create policy "owner and invitee see invites" on public.invites
  for select to authenticated
  using ((select public.is_owner(device_id)) or lower(email) = lower((select auth.jwt()) ->> 'email'));
create policy "owner invites" on public.invites
  for insert to authenticated
  with check ((select public.is_owner(device_id)) and invited_by = (select auth.uid()));
create policy "owner cancels invites" on public.invites
  for delete to authenticated using ((select public.is_owner(device_id)));

create policy "members read live" on public.device_live
  for select to authenticated using ((select public.is_member(device_id)));
create policy "members read history" on public.readings
  for select to authenticated using ((select public.is_member(device_id)));
create policy "members read alerts" on public.alerts
  for select to authenticated using ((select public.is_member(device_id)));

-- ---------------------------------------------------------------- meter API (anon key)

-- First call after boot. Registers a new meter (trust on first use: fine for
-- prototypes; for production, units are registered at the factory instead).
create or replace function public.device_hello(p_id text, p_secret text, p_pop text, p_fw text, p_hw text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_id !~ '^SEM1-[0-9A-F]{6}$' or char_length(p_secret) <> 32 or char_length(p_pop) <> 8 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  if not exists (select 1 from public.devices where id = p_id) then
    insert into public.devices (id, fw, hw, last_seen) values (p_id, left(p_fw, 32), left(p_hw, 32), now());
    insert into private.device_keys (device_id, secret_hash, pop_hash)
      values (p_id, private.sha256(p_secret), private.sha256(p_pop));
  elsif not private.device_auth(p_id, p_secret) then
    return jsonb_build_object('ok', false, 'error', 'auth');
  else
    update public.devices set fw = left(p_fw, 32), hw = left(p_hw, 32), last_seen = now() where id = p_id;
  end if;
  return jsonb_build_object(
    'ok', true,
    'claimed', exists (select 1 from public.device_members where device_id = p_id),
    'live_s', 10);
end $$;

-- Regular upload: latest live values and/or a batch of 5-minute records.
--   p_live:    {"ts":1760000000,"v":231.2,"i":4.35,"p":998.7,"s":1005.9,"pf":0.993,"kwh":12.34,"rssi":-60}
--   p_records: [{"seq":12,"ts":1760000100,"e":123456,"pa":998,"pm":1500,"v":231.2,"f":0}, ...]
-- Returns the highest seq stored, so the meter can move its upload cursor.
create or replace function public.device_push(p_id text, p_secret text, p_live jsonb, p_records jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  d public.devices%rowtype;
  acked bigint := 0;
  p real;
begin
  if not private.device_auth(p_id, p_secret) then
    return jsonb_build_object('ok', false, 'error', 'auth');
  end if;
  update public.devices set last_seen = now() where id = p_id returning * into d;

  -- back online: close an open offline alert
  update public.alerts set resolved_at = now()
    where device_id = p_id and kind = 'offline' and resolved_at is null;

  if p_live is not null and jsonb_typeof(p_live) = 'object' then
    insert into public.device_live as l (device_id, ts, v, i, p, s, pf, kwh, rssi, updated_at)
    values (p_id,
            to_timestamp(least((p_live ->> 'ts')::double precision, extract(epoch from now()) + 60)),
            (p_live ->> 'v')::real, (p_live ->> 'i')::real, (p_live ->> 'p')::real,
            (p_live ->> 's')::real, (p_live ->> 'pf')::real, (p_live ->> 'kwh')::double precision,
            (p_live ->> 'rssi')::smallint, now())
    on conflict (device_id) do update set
      ts = excluded.ts, v = excluded.v, i = excluded.i, p = excluded.p, s = excluded.s,
      pf = excluded.pf, kwh = excluded.kwh, rssi = excluded.rssi, updated_at = now();

    -- high-power alert with 10 % hysteresis
    p := (p_live ->> 'p')::real;
    if d.alert_power_w is not null and p is not null then
      if not d.high_power_active and p > d.alert_power_w then
        insert into public.alerts (device_id, kind, value) values (p_id, 'high_power', p);
        update public.devices set high_power_active = true where id = p_id;
      elsif d.high_power_active and p < d.alert_power_w * 0.9 then
        update public.alerts set resolved_at = now()
          where device_id = p_id and kind = 'high_power' and resolved_at is null;
        update public.devices set high_power_active = false where id = p_id;
      end if;
    end if;
  end if;

  if p_records is not null and jsonb_typeof(p_records) = 'array' then
    if jsonb_array_length(p_records) > 300 then
      return jsonb_build_object('ok', false, 'error', 'too_many');
    end if;
    insert into public.readings (device_id, ts, energy_dwh, p_avg, p_max, v_avg, flags)
    select p_id, to_timestamp((r ->> 'ts')::bigint), (r ->> 'e')::bigint,
           (r ->> 'pa')::integer, (r ->> 'pm')::integer, (r ->> 'v')::real,
           coalesce((r ->> 'f')::smallint, 0)
    from jsonb_array_elements(p_records) r
    where (r ->> 'ts')::bigint between 1704067200 and extract(epoch from now())::bigint + 3600
    on conflict (device_id, ts) do nothing;
    select coalesce(max((r ->> 'seq')::bigint), 0) into acked from jsonb_array_elements(p_records) r;
  end if;

  return jsonb_build_object('ok', true, 'acked', acked);
end $$;

-- ---------------------------------------------------------------- app API (logged-in users)

-- Add a meter to my account. The PoP comes from the QR code on the label,
-- so only someone holding the meter can claim it.
create or replace function public.claim_device(p_id text, p_pop text, p_name text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'login'); end if;
  if not exists (select 1 from private.device_keys k
                 where k.device_id = p_id and k.pop_hash = private.sha256(p_pop)) then
    -- either a wrong code, or the meter has not reached the internet yet
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

-- Owner gives the meter away (e.g. sells the house): removes everyone.
create or replace function public.release_device(p_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner(p_id) then return jsonb_build_object('ok', false, 'error', 'not_owner'); end if;
  delete from public.device_members where device_id = p_id;
  delete from public.invites where device_id = p_id;
  update public.devices set claimed_at = null where id = p_id;
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
-- Consumption = growth of the lifetime counter between consecutive records
-- (a counter that goes backwards, e.g. after a factory reset, counts as 0).
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

-- ---------------------------------------------------------------- permissions

revoke execute on function public.device_hello, public.device_push from public;
grant  execute on function public.device_hello, public.device_push to anon, authenticated;
revoke execute on function public.claim_device, public.release_device, public.accept_invites, public.get_energy from public, anon;
grant  execute on function public.claim_device, public.release_device, public.accept_invites, public.get_energy to authenticated;
revoke execute on function public.is_member, public.is_owner from public, anon;
grant  execute on function public.is_member, public.is_owner to authenticated;

-- live updates for the app
alter publication supabase_realtime add table public.device_live, public.alerts;
