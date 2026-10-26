-- Clutch Zone V60: private support unread-count fix
-- Run once in Supabase SQL Editor.

alter table public.support_messages
  add column if not exists admin_read_at timestamptz;

create or replace function public.mark_support_messages_read(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path=public
as $fn$
declare
  v_count integer := 0;
begin
  if p_user_id is null then
    return 0;
  end if;

  -- Only admin can mark a player's private messages as read.
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  update public.support_messages
  set admin_read_at = coalesce(admin_read_at, now()),
      is_read = true
  where support_user_id = p_user_id
    and coalesce(is_group,false) = false
    and is_admin = false
    and admin_read_at is null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$fn$;

grant execute on function public.mark_support_messages_read(uuid) to authenticated;

notify pgrst, 'reload schema';
