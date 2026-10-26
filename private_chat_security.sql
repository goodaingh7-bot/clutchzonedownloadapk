-- CLUTCH ZONE V59 — PRIVATE SUPPORT SECURITY + PUBLIC GROUP SEPARATION
-- Run this once in Supabase SQL Editor after the previous 7 setup chunks.
-- This keeps 24/7 support private to the verified Name + UID pair.
-- Public group messages are explicitly marked is_group = true.

alter table public.support_messages
  add column if not exists is_group boolean not null default false;

update public.support_messages
set is_group = true
where support_user_id is null
  and is_group = false;

-- Remove the old UID-only RPC signatures so a player cannot read/send
-- another player's private support chat by knowing only the UID.
drop function if exists public.get_support_messages(text);
drop function if exists public.send_support_message(text,text);
drop function if exists public.get_group_chat_messages(text);
drop function if exists public.send_group_chat_message(text,text);

create or replace function public.get_support_messages(p_display_name text, p_uid text)
returns table(
  id uuid,
  display_name text,
  message text,
  is_admin boolean,
  created_at timestamptz,
  support_user_id uuid
)
language plpgsql
security definer
set search_path=public
as $fn$
declare
  v_name text := btrim(coalesce(p_display_name,''));
  v_uid text := upper(btrim(coalesce(p_uid,'')));
  v_user_id uuid;
begin
  select su.id into v_user_id
  from public.support_users su
  where lower(btrim(su.display_name)) = lower(v_name)
    and upper(btrim(su.uid)) = v_uid
  limit 1;

  if v_user_id is null then
    raise exception 'Name + UID verification required';
  end if;

  return query
  select sm.id,
         coalesce(sm.display_name, case when sm.is_admin then 'Admin' else 'Player' end),
         sm.message,
         sm.is_admin,
         sm.created_at,
         sm.support_user_id
  from public.support_messages sm
  where sm.support_user_id = v_user_id
    and coalesce(sm.is_group,false) = false
  order by sm.created_at asc
  limit 500;
end;
$fn$;

create or replace function public.send_support_message(p_display_name text, p_uid text, p_message text)
returns public.support_messages
language plpgsql
security definer
set search_path=public
as $fn$
declare
  v_name text := btrim(coalesce(p_display_name,''));
  v_uid text := upper(btrim(coalesce(p_uid,'')));
  v_user_id uuid;
  v_real_name text;
  v_row public.support_messages;
  v_message text := btrim(coalesce(p_message,''));
begin
  if v_message = '' then raise exception 'Message cannot be empty'; end if;
  if char_length(v_message) > 1500 then raise exception 'Message too long'; end if;

  select su.id, su.display_name into v_user_id, v_real_name
  from public.support_users su
  where lower(btrim(su.display_name)) = lower(v_name)
    and upper(btrim(su.uid)) = v_uid
  limit 1;

  if v_user_id is null then raise exception 'Name + UID verification required'; end if;

  insert into public.support_messages(
    support_user_id, display_name, message, is_admin, is_read, is_group, created_at
  ) values (
    v_user_id, v_real_name, v_message, false, false, false, now()
  )
  returning * into v_row;

  return v_row;
end;
$fn$;

create or replace function public.send_group_chat_message(p_display_name text, p_uid text, p_message text)
returns public.support_messages
language plpgsql
security definer
set search_path=public
as $fn$
declare
  v_name text := btrim(coalesce(p_display_name,''));
  v_uid text := upper(btrim(coalesce(p_uid,'')));
  v_user_id uuid;
  v_real_name text;
  v_row public.support_messages;
  v_message text := btrim(coalesce(p_message,''));
begin
  if v_message = '' then raise exception 'Message cannot be empty'; end if;
  if char_length(v_message) > 1500 then raise exception 'Message too long'; end if;

  select su.id, su.display_name into v_user_id, v_real_name
  from public.support_users su
  where lower(btrim(su.display_name)) = lower(v_name)
    and upper(btrim(su.uid)) = v_uid
  limit 1;

  if v_user_id is null then raise exception 'Name + UID verification required'; end if;

  insert into public.support_messages(
    support_user_id, display_name, message, is_admin, is_read, is_group, created_at
  ) values (
    v_user_id, v_real_name, v_message, false, true, true, now()
  )
  returning * into v_row;

  return v_row;
end;
$fn$;

create or replace function public.get_group_chat_messages(p_display_name text, p_uid text)
returns table(
  id uuid,
  display_name text,
  message text,
  is_admin boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $fn$
declare
  v_name text := btrim(coalesce(p_display_name,''));
  v_uid text := upper(btrim(coalesce(p_uid,'')));
begin
  if not exists(
    select 1 from public.support_users su
    where lower(btrim(su.display_name)) = lower(v_name)
      and upper(btrim(su.uid)) = v_uid
  ) then
    raise exception 'Name + UID verification required';
  end if;

  return query
  select sm.id,
         coalesce(sm.display_name, case when sm.is_admin then 'Admin' else 'Player' end),
         sm.message,
         sm.is_admin,
         sm.created_at
  from public.support_messages sm
  where coalesce(sm.is_group,false) = true
  order by sm.created_at asc
  limit 500;
end;
$fn$;

-- Explicit permissions: public visitors may use the verified Name + UID RPCs.
grant execute on function public.get_support_messages(text,text) to anon, authenticated;
grant execute on function public.send_support_message(text,text,text) to anon, authenticated;
grant execute on function public.get_group_chat_messages(text,text) to anon, authenticated;
grant execute on function public.send_group_chat_message(text,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
