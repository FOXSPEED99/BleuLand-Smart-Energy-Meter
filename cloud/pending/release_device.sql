-- NOT APPLIED YET. The migration tool cancels anything containing DELETE,
-- so paste this into Supabase dashboard -> SQL Editor -> Run when needed.
-- Owner gives the meter away (e.g. sells the house): removes everyone.
create or replace function public.release_device(p_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner(p_id) then return jsonb_build_object('ok', false, 'error', 'not_owner'); end if;
  delete from public.device_members where device_id = p_id;
  delete from public.invites where device_id = p_id;
  update public.devices set claimed_at = null where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.release_device from public, anon;
grant execute on function public.release_device to authenticated;
