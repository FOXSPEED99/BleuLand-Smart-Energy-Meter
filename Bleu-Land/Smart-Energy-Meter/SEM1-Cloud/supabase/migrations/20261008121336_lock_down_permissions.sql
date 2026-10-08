revoke update on public.devices from authenticated, anon;
grant update (name, timezone, currency, tariff, billing_day, alert_power_w, alert_offline_min)
  on public.devices to authenticated;
revoke execute on function public.claim_device, public.accept_invites, public.get_energy,
  public.is_member, public.is_owner from public, anon;
revoke all on schema private from public, anon, authenticated;
