-- Changing the meter's WiFi from the app.
--
-- Online meter: the owner taps "Change WiFi" -> request_wifi_setup(); the next
-- device_push answers {"wifi_setup": true} and the meter restarts into phone
-- setup over Bluetooth, keeping its current WiFi until a new one works.
-- Offline meter (e.g. the router password changed): the meter opens phone
-- setup by itself after 2 minutes without WiFi; the app connects over
-- Bluetooth directly.
--
-- Bluetooth setup needs the 8-character code from the label. claim_device now
-- keeps it (owner-only, via get_setup_code) so the owner doesn't have to find
-- the label again, e.g. on a new phone.

alter table public.device_live add column ssid text;  -- WiFi the meter is on
alter table public.devices add column wifi_setup_at timestamptz;  -- owner asked to change WiFi

create table private.device_setup_codes (
  device_id text primary key references public.devices(id) on delete cascade,
  pop       text not null check (char_length(pop) = 8)
);

-- Owner only: the label code, for Bluetooth setup.
create or replace function public.get_setup_code(p_id text)
returns text language sql stable security definer set search_path = '' as $$
  select c.pop from private.device_setup_codes c where c.device_id = p_id and public.is_owner(p_id)
$$;

-- Owner taps "Change WiFi" while the meter is online.
create or replace function public.request_wifi_setup(p_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare seen timestamptz;
begin
  if not public.is_owner(p_id) then return jsonb_build_object('ok', false, 'error', 'not_owner'); end if;
  update public.devices set wifi_setup_at = now() where id = p_id returning last_seen into seen;
  return jsonb_build_object('ok', true, 'online', coalesce(seen > now() - interval '1 minute', false));
end $$;

-- claim_device, now also keeping the label code for later WiFi changes.
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
  insert into private.device_setup_codes (device_id, pop) values (p_id, p_pop)
    on conflict (device_id) do update set pop = excluded.pop;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.get_setup_code, public.request_wifi_setup from public, anon;
grant execute on function public.get_setup_code, public.request_wifi_setup to authenticated;
