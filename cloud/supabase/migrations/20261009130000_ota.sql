-- Firmware updates over WiFi (OTA).
--
-- 1. GitHub Actions builds the firmware and uploads it to the public
--    "firmware" bucket, then adds a row to firmware_releases (service key).
-- 2. The owner taps "Update" in the app -> request_update().
-- 3. device_push answers with {"ota": {version, url, size, md5}}; the meter
--    reports progress with device_ota(), downloads into its spare slot,
--    checks the MD5 and restarts.
-- 4. device_hello after the restart: same version as requested -> "done";
--    an older one (the meter rolled back by itself) -> "failed".

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('firmware', 'firmware', true, 4194304, array['application/octet-stream'])
on conflict (id) do nothing;

create table public.firmware_releases (
  id         bigint generated always as identity primary key,
  version    text not null check (version ~ '^\d+\.\d+\.\d+$'),
  hw         text not null,  -- what the meter reports: SEM1-proto-devkit, SEM1-C3
  channel    text not null default 'beta' check (channel in ('beta', 'stable')),
  url        text not null check (url like 'https://%'),
  size       integer not null check (size between 100000 and 2031616),
  md5        text not null check (md5 ~ '^[0-9a-f]{32}$'),
  notes      text,
  git_sha    text,
  created_at timestamptz not null default now(),
  unique (hw, version)
);
-- No policies: only the service key (CI) and the functions below touch it.
alter table public.firmware_releases enable row level security;

alter table public.devices
  add column fw_channel  text not null default 'stable' check (fw_channel in ('stable', 'beta')),
  add column ota_version text,      -- the version the owner asked for
  add column ota_status  text check (ota_status in ('requested', 'downloading', 'installing', 'done', 'failed')),
  add column ota_error   text,
  add column ota_tries   smallint not null default 0,
  add column ota_at      timestamptz;

create or replace function private.semver(v text) returns int[]
language sql immutable set search_path = '' as $$
  select case when v ~ '^\d+\.\d+\.\d+$' then string_to_array(v, '.')::int[] else array[0, 0, 0] end
$$;

-- Newest release this meter may install (beta meters also see beta builds).
create or replace function private.latest_release(p_hw text, p_channel text)
returns public.firmware_releases language sql stable set search_path = '' as $$
  select r.* from public.firmware_releases r
  where r.hw = p_hw and (r.channel = 'stable' or p_channel = 'beta')
  order by private.semver(r.version) desc, r.created_at desc
  limit 1
$$;

-- For the app's firmware screen.
create or replace function public.firmware_status(p_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare d public.devices%rowtype; r public.firmware_releases%rowtype;
begin
  if not public.is_member(p_id) then return null; end if;
  select * into d from public.devices where id = p_id;
  r := private.latest_release(d.hw, d.fw_channel);
  return jsonb_build_object(
    'current', d.fw, 'hw', d.hw, 'channel', d.fw_channel,
    'latest', case when r.version is not null and private.semver(r.version) > private.semver(d.fw)
                   then jsonb_build_object('version', r.version, 'notes', r.notes, 'size', r.size,
                                           'channel', r.channel, 'created_at', r.created_at)
              end,
    'status', d.ota_status, 'target', d.ota_version, 'error', d.ota_error, 'at', d.ota_at);
end $$;

-- Owner taps "Update".
create or replace function public.request_update(p_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.devices%rowtype; r public.firmware_releases%rowtype;
begin
  if not public.is_owner(p_id) then return jsonb_build_object('ok', false, 'error', 'not_owner'); end if;
  select * into d from public.devices where id = p_id;
  r := private.latest_release(d.hw, d.fw_channel);
  if r.version is null or private.semver(r.version) <= private.semver(d.fw) then
    return jsonb_build_object('ok', false, 'error', 'up_to_date');
  end if;
  if d.ota_status in ('downloading', 'installing') then
    return jsonb_build_object('ok', false, 'error', 'busy');
  end if;
  update public.devices
    set ota_version = r.version, ota_status = 'requested', ota_error = null, ota_tries = 0, ota_at = now()
    where id = p_id;
  return jsonb_build_object('ok', true, 'version', r.version);
end $$;

-- Owner cancels a request the meter hasn't picked up yet (e.g. it's offline).
create or replace function public.cancel_update(p_id text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner(p_id) then return false; end if;
  update public.devices set ota_status = null, ota_version = null, ota_error = null, ota_at = now()
    where id = p_id and ota_status = 'requested';
  return found;
end $$;

-- The meter reports progress: downloading / installing / failed.
create or replace function public.device_ota(p_id text, p_secret text, p_status text, p_error text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not private.device_auth(p_id, p_secret) then
    return jsonb_build_object('ok', false, 'error', 'auth');
  end if;
  if p_status not in ('downloading', 'installing', 'failed') then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  update public.devices set
      ota_status = p_status,
      ota_error  = case when p_status = 'failed' then left(coalesce(p_error, 'unknown error'), 200) end,
      ota_tries  = ota_tries + case when p_status = 'downloading' then 1 else 0 end,
      ota_at     = now()
    where id = p_id and ota_status in ('requested', 'downloading', 'installing');
  return jsonb_build_object('ok', true);
end $$;

-- device_hello, now also closing an update after the restart.
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
    -- running the requested version: done
    update public.devices set ota_status = 'done', ota_error = null, ota_at = now()
      where id = p_id and ota_status in ('requested', 'downloading', 'installing') and ota_version = fw;
    -- restarted into the old version after installing: the new one failed its
    -- checks and the chip went back by itself
    update public.devices set ota_status = 'failed', ota_at = now(),
        ota_error = 'The new version did not start properly, so the meter went back to ' || fw || '.'
      where id = p_id and ota_status = 'installing';
    -- restarted in the middle of a download (power cut): try again, 3 times at most
    update public.devices set ota_at = now(),
        ota_status = case when ota_tries >= 3 then 'failed' else 'requested' end,
        ota_error  = case when ota_tries >= 3 then 'The download kept getting interrupted.' end
      where id = p_id and ota_status = 'downloading';
  end if;
  return jsonb_build_object(
    'ok', true,
    'claimed', exists (select 1 from public.device_members where device_id = p_id),
    'live_s', 10);
end $$;

revoke execute on function public.firmware_status, public.request_update, public.cancel_update
  from public, anon;
grant execute on function public.firmware_status, public.request_update, public.cancel_update
  to authenticated;
revoke execute on function public.device_ota from public, authenticated;
grant execute on function public.device_ota to anon;
revoke all on function private.semver, private.latest_release from public, anon, authenticated;
