revoke execute on function public.device_hello, public.device_push from public, authenticated;
grant execute on function public.device_hello, public.device_push to anon;
create index if not exists invites_invited_by_idx on public.invites (invited_by);
