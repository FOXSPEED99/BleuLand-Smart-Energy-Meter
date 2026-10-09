-- device_push, now also storing the WiFi name and handing over a
-- "change WiFi" request ({"wifi_setup": true}). Otherwise unchanged.
create or replace function public.device_push(p_id text, p_secret text, p_live jsonb, p_records jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  d public.devices%rowtype;
  vd public.volt_days%rowtype;
  acked bigint := 0;
  t timestamptz := now();
  today date;
  p real; v real; vmin real; vmax real;
  st text; sev smallint; worst real;
  rel public.firmware_releases%rowtype;
  ota jsonb;
  wifi_setup boolean := false;
begin
  if not private.device_auth(p_id, p_secret) then
    return jsonb_build_object('ok', false, 'error', 'auth');
  end if;
  update public.devices set last_seen = t where id = p_id returning * into d;
  today := (t at time zone d.timezone)::date;

  -- back online: close an open offline alert
  update public.alerts set resolved_at = t
    where device_id = p_id and kind = 'offline' and resolved_at is null;

  if p_live is not null and jsonb_typeof(p_live) = 'object' then
    v := (p_live ->> 'v')::real;
    vmin := coalesce((p_live ->> 'vmin')::real, v);
    vmax := coalesce((p_live ->> 'vmax')::real, v);

    -- ---- voltage (below 100 V = no mains, e.g. a bench supply: ignored) ----
    if v >= 100 and vmin >= 100 then
      insert into public.volt_days as x (device_id, day, v_min, v_min_at, v_max, v_max_at)
      values (p_id, today, vmin, t, vmax, t)
      on conflict (device_id, day) do update set
        v_min_at = case when excluded.v_min < x.v_min then excluded.v_min_at else x.v_min_at end,
        v_min    = least(x.v_min, excluded.v_min),
        v_max_at = case when excluded.v_max > x.v_max then excluded.v_max_at else x.v_max_at end,
        v_max    = greatest(x.v_max, excluded.v_max);

      st := case when vmin < d.volt_min then 'low' when vmax > d.volt_max then 'high' else 'ok' end;
      -- leaving a low/high spell needs 2 V of margin, so it doesn't flap at the limit
      if st = 'ok' and d.volt_state <> 'ok' and (vmin < d.volt_min + 2 or vmax > d.volt_max - 2) then
        st := d.volt_state;
      end if;
      worst := case when st = 'low' then vmin else vmax end;
      sev := case when (st = 'low' and vmin < d.volt_min - 10) or (st = 'high' and vmax > d.volt_max + 10)
                  then 2 else 1 end;

      if st = 'ok' then
        if d.volt_state <> 'ok' then
          update public.alerts set resolved_at = t
            where device_id = p_id and kind in ('volt_low', 'volt_high') and resolved_at is null;
          update public.devices set volt_state = 'ok', volt_bad_since = null where id = p_id;
        end if;
      else
        if d.volt_state <> st then
          update public.alerts set resolved_at = t
            where device_id = p_id and kind in ('volt_low', 'volt_high') and resolved_at is null;
          update public.devices set volt_state = st, volt_bad_since = t where id = p_id;
          d.volt_bad_since := t;
        end if;
        if exists (select 1 from public.alerts
                   where device_id = p_id and kind = 'volt_' || st and resolved_at is null) then
          update public.alerts set
              value = case when st = 'low' then least(value, worst) else greatest(value, worst) end,
              severity = greatest(severity, sev)
            where device_id = p_id and kind = 'volt_' || st and resolved_at is null;
        elsif d.volt_bad_since <= t - interval '60 seconds' or (st = 'high' and sev = 2) then
          insert into public.alerts (device_id, kind, value, severity) values (p_id, 'volt_' || st, worst, sev);
        end if;
      end if;
    end if;
    select * into vd from public.volt_days where device_id = p_id and day = today;

    insert into public.device_live as l
      (device_id, ts, v, i, p, s, pf, kwh, rssi, ssid, vmin, vmax,
       day, day_vmin, day_vmin_at, day_vmax, day_vmax_at, updated_at)
    values (p_id,
            to_timestamp(least((p_live ->> 'ts')::double precision, extract(epoch from t) + 60)),
            v, (p_live ->> 'i')::real, (p_live ->> 'p')::real,
            (p_live ->> 's')::real, (p_live ->> 'pf')::real, (p_live ->> 'kwh')::double precision,
            (p_live ->> 'rssi')::smallint, left(nullif(p_live ->> 'ssid', ''), 32), vmin, vmax,
            vd.day, vd.v_min, vd.v_min_at, vd.v_max, vd.v_max_at, t)
    on conflict (device_id) do update set
      ts = excluded.ts, v = excluded.v, i = excluded.i, p = excluded.p, s = excluded.s,
      pf = excluded.pf, kwh = excluded.kwh, rssi = excluded.rssi,
      ssid = coalesce(excluded.ssid, l.ssid),
      vmin = excluded.vmin, vmax = excluded.vmax,
      day = excluded.day, day_vmin = excluded.day_vmin, day_vmin_at = excluded.day_vmin_at,
      day_vmax = excluded.day_vmax, day_vmax_at = excluded.day_vmax_at, updated_at = t;

    -- high-power alert with 10 % hysteresis
    p := (p_live ->> 'p')::real;
    if d.alert_power_w is not null and p is not null then
      if not d.high_power_active and p > d.alert_power_w then
        insert into public.alerts (device_id, kind, value) values (p_id, 'high_power', p);
        update public.devices set high_power_active = true where id = p_id;
      elsif d.high_power_active and p < d.alert_power_w * 0.9 then
        update public.alerts set resolved_at = t
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
    where (r ->> 'ts')::bigint between 1704067200 and extract(epoch from t)::bigint + 3600
    on conflict (device_id, ts) do nothing;
    select coalesce(max((r ->> 'seq')::bigint), 0) into acked from jsonb_array_elements(p_records) r;
  end if;

  if d.ota_status = 'requested' and d.ota_version is distinct from d.fw then
    select * into rel from public.firmware_releases where hw = d.hw and version = d.ota_version;
    if found then
      ota := jsonb_build_object('version', rel.version, 'url', rel.url, 'size', rel.size, 'md5', rel.md5);
    end if;
  end if;

  -- the owner asked to change the WiFi (only fresh requests; handed over once)
  if d.wifi_setup_at is not null then
    wifi_setup := d.wifi_setup_at > t - interval '2 minutes';
    update public.devices set wifi_setup_at = null where id = p_id;
  end if;

  return jsonb_build_object('ok', true, 'acked', acked,
                            'fast', coalesce(d.watch_until > t, false), 'ota', ota,
                            'wifi_setup', wifi_setup);
end $$;
