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
