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

create or replace function private.device_auth(p_id text, p_secret text) returns boolean
language sql stable set search_path = '' as
$$ select exists (select 1 from private.device_keys k
                  where k.device_id = p_id and k.secret_hash = private.sha256(p_secret)) $$;

create policy "members read their meters" on public.devices
  for select to authenticated using ((select public.is_member(id)));
create policy "owner edits settings" on public.devices
  for update to authenticated using ((select public.is_owner(id))) with check ((select public.is_owner(id)));

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
