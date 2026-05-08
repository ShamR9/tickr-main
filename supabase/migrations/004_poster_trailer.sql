-- Migration 004: Add poster image and trailer URL to events
alter table public.events
  add column if not exists poster      text default null,
  add column if not exists trailer_url text default null;
