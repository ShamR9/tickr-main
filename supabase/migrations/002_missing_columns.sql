-- ============================================================
-- TICKR — Migration 002: Missing columns and tables
-- Run in Supabase SQL Editor
-- ============================================================

-- ── events: missing columns ──────────────────────────────────
alter table public.events
  add column if not exists booking_message  text default '',
  add column if not exists payment_override jsonb default null;

-- ── tickets: missing column ──────────────────────────────────
alter table public.tickets
  add column if not exists cancelled boolean default false;

-- ── reservations: missing column ─────────────────────────────
alter table public.reservations
  add column if not exists notes text default null;

-- ── discount_codes ───────────────────────────────────────────
create table if not exists public.discount_codes (
  id          text primary key,
  event_id    text references public.events(id) on delete cascade not null,
  code        text not null,
  type        text not null check (type in ('percent','fixed')),
  value       numeric(10,2) not null default 0,
  max_uses    integer default 0,
  uses        integer default 0,
  expires_at  timestamptz default null,
  active      boolean default true,
  created_at  timestamptz default now()
);
create index if not exists discount_codes_event_id_idx on public.discount_codes(event_id);
create index if not exists discount_codes_code_idx     on public.discount_codes(event_id, code);

alter table public.discount_codes enable row level security;
create policy "Org/admin can manage discount codes"
  on public.discount_codes for all
  using (
    public.is_admin() or
    exists (select 1 from public.events e where e.id=event_id and e.org_id=auth.uid())
  );
create policy "Public can read active discount codes"
  on public.discount_codes for select
  using (active = true);

-- ── activity_log ─────────────────────────────────────────────
create table if not exists public.activity_log (
  id          text primary key,
  event_id    text references public.events(id) on delete cascade,
  user_id     uuid references public.profiles(id) on delete set null,
  action      text not null,
  detail      text default '',
  created_at  timestamptz default now()
);
create index if not exists activity_log_event_id_idx on public.activity_log(event_id);
create index if not exists activity_log_created_idx  on public.activity_log(created_at desc);

alter table public.activity_log enable row level security;
create policy "Org/admin can read activity log"
  on public.activity_log for select
  using (
    public.is_admin() or
    exists (select 1 from public.events e where e.id=event_id and e.org_id=auth.uid())
  );
create policy "Authenticated can insert activity log"
  on public.activity_log for insert
  with check (auth.uid() is not null);

-- ── waitlist ─────────────────────────────────────────────────
create table if not exists public.waitlist (
  id          text primary key,
  event_id    text references public.events(id) on delete cascade not null,
  name        text not null,
  phone       text default '',
  email       text default '',
  notified    boolean default false,
  notified_at timestamptz default null,
  created_at  timestamptz default now()
);
create index if not exists waitlist_event_id_idx on public.waitlist(event_id);

alter table public.waitlist enable row level security;
create policy "Org/admin can manage waitlist"
  on public.waitlist for all
  using (
    public.is_admin() or
    exists (select 1 from public.events e where e.id=event_id and e.org_id=auth.uid())
  );
create policy "Anyone can join waitlist"
  on public.waitlist for insert with check (true);
