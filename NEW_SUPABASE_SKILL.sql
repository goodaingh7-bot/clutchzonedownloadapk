-- =========================================================
-- CLUTCH ZONE V49 — ARENA EDITION
-- NEW DATABASE SKILL / MIGRATION
-- Run AFTER the 7 successful setup chunks already applied.
-- Old room ID/password system is intentionally NOT included.
-- =========================================================

create extension if not exists pgcrypto;

create table if not exists public.match_categories(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  image_url text,
  sort_order integer not null default 0,
  is_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.match_categories enable row level security;

drop policy if exists "Public can view match categories" on public.match_categories;
create policy "Public can view match categories"
on public.match_categories for select
to anon, authenticated
using(is_visible = true or public.is_admin());

drop policy if exists "Admins can insert match categories" on public.match_categories;
create policy "Admins can insert match categories"
on public.match_categories for insert
to authenticated
with check(public.is_admin());

drop policy if exists "Admins can update match categories" on public.match_categories;
create policy "Admins can update match categories"
on public.match_categories for update
to authenticated
using(public.is_admin())
with check(public.is_admin());

drop policy if exists "Admins can delete match categories" on public.match_categories;
create policy "Admins can delete match categories"
on public.match_categories for delete
to authenticated
using(public.is_admin());

grant select on public.match_categories to anon, authenticated;
grant insert, update, delete on public.match_categories to authenticated;

insert into public.match_categories(name,slug,sort_order,is_visible)
values
 ('Battle Royale','battle-royale',10,true),
 ('Clash Squad','clash-squad',20,true),
 ('Lone Wolf','lone-wolf',30,true),
 ('FF Survival','ff-survival',40,true)
on conflict(slug) do nothing;

alter table public.match_schedule
  add column if not exists category_id uuid;

alter table public.match_schedule
  drop constraint if exists match_schedule_category_id_fkey;

alter table public.match_schedule
  add constraint match_schedule_category_id_fkey
  foreign key(category_id)
  references public.match_categories(id)
  on delete set null;

create index if not exists match_schedule_category_idx
on public.match_schedule(category_id,match_date);

-- Rebuild the safe public view with category support.
drop view if exists public.public_match_schedule;
create view public.public_match_schedule
with (security_invoker = true)
as
select
  id,
  title,
  description,
  category_id,
  game_mode,
  entry_fee,
  prize_pool,
  total_players,
  per_kill_reward,
  match_image_url,
  match_date,
  status,
  is_visible,
  created_at,
  updated_at
from public.match_schedule
where is_visible = true;

grant select on public.public_match_schedule to anon, authenticated;

notify pgrst, 'reload schema';
