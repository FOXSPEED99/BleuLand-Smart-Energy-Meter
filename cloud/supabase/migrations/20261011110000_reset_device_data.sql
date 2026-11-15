-- "Start fresh": the owner can wipe a meter's usage data (energy history,
-- so the bill, charts and History start from zero, and its alerts). The
-- meter itself, its settings, tariff, WiFi and sharing stay.
--
-- The meter keeps a log on its flash and may still upload records from
-- before the reset (e.g. after being offline): those are dropped on insert,
-- so the reset sticks.

alter table public.devices add column data_reset_at timestamptz;  -- last "start fresh"

create or replace function public.reset_device_data(p_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n_readings int; n_alerts int;
begin
  if not public.is_owner(p_id) then return jsonb_build_object('ok', false, 'error', 'not_owner'); end if;
  update public.devices set data_reset_at = now() where id = p_id;
  delete from public.readings where device_id = p_id;
  get diagnostics n_readings = row_count;
  delete from public.alerts where device_id = p_id;
  get diagnostics n_alerts = row_count;
  return jsonb_build_object('ok', true, 'readings', n_readings, 'alerts', n_alerts);
end $$;

revoke execute on function public.reset_device_data from public, anon;
grant execute on function public.reset_device_data to authenticated;

-- Records stamped before the last reset are not stored again.
create or replace function private.readings_after_reset()
returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from public.devices d
             where d.id = new.device_id and d.data_reset_at is not null and new.ts <= d.data_reset_at) then
    return null;
  end if;
  return new;
end $$;

create trigger readings_after_reset before insert on public.readings
  for each row execute function private.readings_after_reset();
