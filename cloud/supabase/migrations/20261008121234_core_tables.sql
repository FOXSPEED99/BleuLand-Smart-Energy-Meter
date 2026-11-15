create schema if not exists private;

create table public.devices (
  id               text primary key check (id ~ '^SEM1-[0-9A-F]{6}$'),
  name             text not null default 'My home' check (char_length(name) between 1 and 40),
  fw               text,
  hw               text,
  created_at       timestamptz not null default now(),
  claimed_at       timestamptz,
  last_seen        timestamptz,
  timezone         text not null default 'Asia/Damascus',
  currency         text not null default 'SYP' check (char_length(currency) = 3),
  tariff           jsonb not null default '{"tiers":[{"upto_kwh":300,"price":6},{"price":14}],"fixed_per_period":0,"period_months":2}',
  billing_day      smallint not null default 1 check (billing_day between 1 and 28),
  alert_power_w    integer check (alert_power_w is null or alert_power_w between 100 and 30000),
  alert_offline_min integer not null default 15 check (alert_offline_min between 5 and 1440),
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

create table public.device_live (
  device_id  text primary key references public.devices(id) on delete cascade,
  ts         timestamptz not null,
  v          real, i real, p real, s real, pf real,
  kwh        double precision,
  rssi       smallint,
  updated_at timestamptz not null default now()
);

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

alter table public.devices        enable row level security;
alter table public.device_members enable row level security;
alter table public.invites        enable row level security;
alter table public.device_live    enable row level security;
alter table public.readings       enable row level security;
alter table public.alerts         enable row level security;
alter table private.device_keys   enable row level security;
