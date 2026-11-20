-- Our Sky — current database schema snapshot
-- Captured from Supabase project LoveBase on 2026-11-21.
--
-- IMPORTANT:
--   * This is a BASELINE SNAPSHOT, not an incremental migration.
--   * Do NOT run this against the existing production database.
--   * It contains schema only: no users, stars, comments, Telegram records,
--     uploaded files, tokens, passwords, or API keys.
--   * Supabase-managed auth/storage schemas and platform roles are not recreated.
--   * Historical migrations 20261111000815..20261112185742 are not present
--     as SQL files in this repository; this snapshot captures their resulting
--     application schema state instead.
--
-- For a fresh Supabase project, create the Supabase Auth schema first
-- (provided automatically by Supabase), then run this file as postgres.

create extension if not exists pgcrypto;

create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.people (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null
);

create table public.stars (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references auth.users(id),
  author_name text,
  title text not null,
  body text not null default ''::text,
  happened_on date not null default current_date,
  photo_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_private boolean not null default false,
  star_type text not null default 'silver'::text,
  unlock_at date,
  constraint stars_title_check
    check (char_length(title) >= 1 and char_length(title) <= 80),
  constraint stars_body_check
    check (char_length(body) <= 4000),
  constraint stars_star_type_check
    check (star_type = any (array['silver'::text, 'gold'::text]))
);

create table public.telegram (
  user_id uuid primary key references auth.users(id) on delete cascade,
  chat_id bigint not null
);

create table public.delete_codes (
  user_id uuid not null references auth.users(id) on delete cascade,
  star_id uuid not null references public.stars(id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, star_id)
);

create table public.star_comments (
  id uuid primary key default gen_random_uuid(),
  star_id uuid references public.stars(id) on delete cascade,
  is_first boolean not null default false,
  telegram_user_id bigint not null,
  author_name text not null,
  body text not null,
  created_at timestamptz not null default now(),
  constraint star_comments_author_name_check
    check (char_length(author_name) >= 1 and char_length(author_name) <= 120),
  constraint star_comments_body_check
    check (char_length(body) >= 1 and char_length(body) <= 1200),
  constraint star_comments_target_check
    check ((is_first = true and star_id is null) or (is_first = false and star_id is not null))
);

create table public.comment_bans (
  telegram_user_id bigint primary key,
  author_name text not null default 'Гость Telegram'::text,
  banned_by uuid not null references public.people(user_id),
  created_at timestamptz not null default now()
);

create table public.telegram_users (
  telegram_user_id bigint primary key,
  display_name text not null default 'Пользователь Telegram'::text,
  username text,
  first_name text,
  last_name text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table public.telegram_message_targets (
  admin_telegram_user_id bigint primary key,
  target_telegram_user_id bigint not null,
  selected_at timestamptz not null default now()
);

create table public.star_notification_dispatch (
  star_id uuid primary key references public.stars(id) on delete cascade,
  created_by uuid not null references public.people(user_id),
  is_private boolean not null,
  guest_total integer not null default 0,
  guest_delivered integer not null default 0,
  spouse_delivered boolean not null default false,
  status text not null default 'sending'::text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index star_comments_first_created_idx
  on public.star_comments using btree (created_at)
  where (is_first = true);

create index star_comments_star_created_idx
  on public.star_comments using btree (star_id, created_at);

-- ---------------------------------------------------------------------------
-- Functions and triggers
-- ---------------------------------------------------------------------------

create or replace function private.is_member()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.people
    where user_id = (select auth.uid())
  );
$function$;

revoke all on function private.is_member() from public, anon;
grant execute on function private.is_member() to authenticated;

create or replace function public.reject_future_star_dates()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if new.happened_on > (now() at time zone 'Europe/Moscow')::date then
    raise exception using
      errcode = '23514',
      message = 'future_star_date_not_allowed';
  end if;
  return new;
end;
$function$;

create or replace function public.stars_touch()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  new.author_id := old.author_id;
  new.created_at := old.created_at;
  new.updated_at := pg_catalog.now();
  return new;
end
$function$;

create trigger reject_future_star_dates
before insert or update of happened_on on public.stars
for each row execute function public.reject_future_star_dates();

create trigger stars_touch
before update on public.stars
for each row execute function public.stars_touch();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.people enable row level security;
alter table public.stars enable row level security;
alter table public.telegram enable row level security;
alter table public.delete_codes enable row level security;
alter table public.star_comments enable row level security;
alter table public.comment_bans enable row level security;
alter table public.telegram_users enable row level security;
alter table public.telegram_message_targets enable row level security;
alter table public.star_notification_dispatch enable row level security;

create policy "members read people"
on public.people for select to authenticated
using (private.is_member());

create policy "guests read public stars"
on public.stars for select to anon
using (is_private = false);

create policy "members read all stars"
on public.stars for select to authenticated
using (private.is_member());

create policy "members add stars"
on public.stars for insert to authenticated
with check (private.is_member() and author_id = (select auth.uid()));

create policy "members edit stars"
on public.stars for update to authenticated
using (private.is_member())
with check (private.is_member());

create policy "members read all comments"
on public.star_comments for select to authenticated
using (
  private.is_member()
  or is_first = true
  or exists (
    select 1 from public.stars s
    where s.id = star_comments.star_id and s.is_private = false
  )
);

create policy "public comments read open memories"
on public.star_comments for select to anon
using (
  is_first = true
  or exists (
    select 1 from public.stars s
    where s.id = star_comments.star_id and s.is_private = false
  )
);

-- Preserve the current table grants used by the app.
grant select on public.people to authenticated;
grant select on public.stars to anon, authenticated;
grant insert, update on public.stars to authenticated;

-- ---------------------------------------------------------------------------
-- Private photo bucket and Storage policies
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

create policy "members read photos"
on storage.objects for select to authenticated
using (bucket_id = 'photos' and private.is_member());

create policy "members upload photos"
on storage.objects for insert to authenticated
with check (bucket_id = 'photos' and private.is_member());

-- The live project currently has these two indexes, nine application tables,
-- the policies above, and the private 'photos' bucket. No production rows
-- are included in this snapshot.
