-- Run this once in Supabase SQL Editor for the "Our Sky" project.
alter table public.stars
  add column if not exists unlock_at date;

comment on column public.stars.unlock_at is
  'Optional date when a sealed memory becomes readable. NULL means immediately available.';
