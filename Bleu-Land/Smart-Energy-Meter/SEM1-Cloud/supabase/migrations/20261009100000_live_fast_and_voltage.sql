-- Faster live values while someone has the app open, and mains-voltage
-- monitoring (normal range per meter, daily lowest/highest, low/high alerts).

alter table public.devices
  add column watch_until    timestamptz,  -- an app is showing live values until then
  add column volt_min       real not null default 200 check (volt_min between 150 and 250),
  add column volt_max       real not null default 230 check (volt_max between 180 and 280),
  add column volt_state     text not null default 'ok' check (volt_state in ('ok', 'low', 'high')),
  add column volt_bad_since timestamptz,
  add constraint volt_range_ok check (volt_max - volt_min >= 10);

-- Today's lowest/highest voltage, copied into the live row so the app gets it
-- with every live update.
alter table public.device_live
  add column vmin real,  -- lowest / highest 1-s voltage since the previous upload
  add column vmax real,
  add column day date,
  add column day_vmin real, add column day_vmin_at timestamptz,
  add column day_vmax real, add column day_vmax_at timestamptz;

create table public.volt_days (
  device_id text not null references public.devices(id) on delete cascade,
  day       date not null,  -- in the meter's time zone
  v_min     real, v_min_at timestamptz,
  v_max     real, v_max_at timestamptz,
  primary key (device_id, day)
);
alter table public.volt_days enable row level security;
create policy "members read voltage days" on public.volt_days
  for select to authenticated using ((select public.is_member(device_id)));

alter table public.alerts drop constraint alerts_kind_check;
alter table public.alerts add constraint alerts_kind_check
  check (kind in ('high_power', 'offline', 'volt_low', 'volt_high'));
-- 1 = a little outside the normal range, 2 = far outside (more than 10 V)
alter table public.alerts add column severity smallint not null default 1 check (severity in (1, 2));

grant update (volt_min, volt_max) on public.devices to authenticated;

-- The app calls this about every 30 s while it shows live values; the meter
-- then uploads every 2 s instead of every 10 s.
create or replace function public.watch_device(p_id text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_member(p_id) then return false; end if;
  update public.devices set watch_until = now() + interval '45 seconds' where id = p_id;
  return true;
end $$;
revoke execute on function public.watch_device from public, anon;
grant execute on function public.watch_device to authenticated;
