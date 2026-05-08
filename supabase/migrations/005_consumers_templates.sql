-- Migration 005: Consumer profiles + layout templates

-- Consumer profiles table
create table if not exists public.consumer_profiles (
  id          uuid references auth.users(id) on delete cascade primary key,
  name        text not null,
  email       text not null,
  tier        text not null default 'standard' check (tier in ('standard','silver','gold','platinum')),
  tier_expires_at timestamptz default null,
  created_at  timestamptz default now()
);
alter table public.consumer_profiles enable row level security;
drop policy if exists "Consumers read own" on public.consumer_profiles;
drop policy if exists "Consumers update own" on public.consumer_profiles;
drop policy if exists "Anyone insert own consumer" on public.consumer_profiles;
drop policy if exists "Admins manage consumers" on public.consumer_profiles;
create policy "Consumers read own"          on public.consumer_profiles for select using (auth.uid()=id);
create policy "Consumers update own"        on public.consumer_profiles for update using (auth.uid()=id);
create policy "Anyone insert own consumer"  on public.consumer_profiles for insert with check (auth.uid()=id);
create policy "Admins manage consumers"     on public.consumer_profiles for all using (public.is_admin());

-- Layout templates table (admin-managed venue presets)
create table if not exists public.layout_templates (
  id          text primary key,
  name        text not null,
  sections    jsonb not null default '[]',
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz default now()
);
alter table public.layout_templates enable row level security;
drop policy if exists "Authenticated read templates" on public.layout_templates;
drop policy if exists "Admins manage templates" on public.layout_templates;
create policy "Authenticated read templates" on public.layout_templates for select using (auth.uid() is not null);
create policy "Admins manage templates"      on public.layout_templates for all using (public.is_admin());
