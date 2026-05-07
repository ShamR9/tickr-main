-- ============================================================
-- TICKR — Supabase Schema
-- Run this in Supabase SQL Editor or via supabase db push
-- ============================================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ─────────────────────────────────────────────────────────────
-- PROFILES (extends Supabase Auth users)
-- ─────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text unique not null,
  name        text not null default '',
  role        text not null default 'organiser' check (role in ('admin','organiser')),
  bank_name   text default '',
  bank_account text default '',
  bank_holder text default '',
  phone       text default '',
  created_at  timestamptz default now()
);

-- Auto-create profile row when a user signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username, name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'role', 'organiser')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- EVENTS
-- ─────────────────────────────────────────────────────────────
create table if not exists public.events (
  id                    text primary key default 'EVT' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  org_id                uuid references public.profiles(id) on delete cascade not null,
  name                  text not null,
  category              text default 'Concert',
  date                  timestamptz,
  venue                 text default '',
  description           text default '',
  seating_mode          text default 'free' check (seating_mode in ('free','allocated')),
  capacity              integer default 0,
  max_seats_per_res     integer default 4,
  scanner_code          text default upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),
  approval_status       text default 'draft' check (approval_status in ('draft','pending','approved','rejected')),
  approval_fee          numeric(10,2) default 0,
  fee_paid              boolean default false,
  fee_paid_at           timestamptz,
  approved_at           timestamptz,
  submitted_at          timestamptz,
  rejected_at           timestamptz,
  rejection_reason      text default '',
  design                jsonb default '{}',
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

-- ─────────────────────────────────────────────────────────────
-- SEATING LAYOUTS
-- ─────────────────────────────────────────────────────────────
create table if not exists public.seating_layouts (
  id          text primary key default 'LAY' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  event_id    text references public.events(id) on delete cascade not null,
  name        text not null,
  sections    jsonb default '[]',  -- array of section config objects
  created_at  timestamptz default now()
);

-- ─────────────────────────────────────────────────────────────
-- SEATS
-- ─────────────────────────────────────────────────────────────
create table if not exists public.seats (
  id          text primary key default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
  layout_id   text references public.seating_layouts(id) on delete cascade not null,
  event_id    text references public.events(id) on delete cascade not null,
  section     text not null,
  row_label   text not null,
  seat_number text not null,
  seat_type   text default 'standard' check (seat_type in ('standard','vip','accessible','blocked')),
  status      text default 'available' check (status in ('available','sold','reserved','held','blocked')),
  price       numeric(10,2) default 0,
  created_at  timestamptz default now()
);

create index if not exists seats_event_id_idx    on public.seats(event_id);
create index if not exists seats_layout_id_idx   on public.seats(layout_id);
create index if not exists seats_status_idx      on public.seats(status);

-- ─────────────────────────────────────────────────────────────
-- TICKETS
-- ─────────────────────────────────────────────────────────────
create table if not exists public.tickets (
  id              text primary key default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
  event_id        text references public.events(id) on delete cascade not null,
  seat_id         text references public.seats(id) on delete set null,
  reservation_id  text,  -- FK added after reservations table created
  code            text unique not null,
  qr_data         text not null,
  holder          text default 'General Admission',
  phone           text default '',
  checked_in      boolean default false,
  checked_in_at   timestamptz,
  issued_at       timestamptz default now(),
  created_at      timestamptz default now()
);

create index if not exists tickets_event_id_idx  on public.tickets(event_id);
create index if not exists tickets_code_idx      on public.tickets(code);
create index if not exists tickets_qr_data_idx   on public.tickets(qr_data);

-- ─────────────────────────────────────────────────────────────
-- RESERVATIONS
-- ─────────────────────────────────────────────────────────────
create table if not exists public.reservations (
  id                text primary key default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
  ref               text unique not null,
  event_id          text references public.events(id) on delete cascade not null,
  name              text not null,
  phone             text not null,
  email             text not null,
  seat_ids          text[] default '{}',
  ticket_ids        text[] default '{}',
  status            text default 'pending' check (status in ('pending','approved','rejected')),
  total_amount      numeric(10,2) default 0,
  rejection_reason  text default '',
  requested_at      timestamptz default now(),
  created_at        timestamptz default now()
);

create index if not exists reservations_event_id_idx on public.reservations(event_id);
create index if not exists reservations_ref_idx      on public.reservations(ref);

-- Add FK from tickets back to reservations
alter table public.tickets
  add column if not exists reservation_id text references public.reservations(id) on delete set null;

-- ─────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────
alter table public.profiles       enable row level security;
alter table public.events         enable row level security;
alter table public.seating_layouts enable row level security;
alter table public.seats          enable row level security;
alter table public.tickets        enable row level security;
alter table public.reservations   enable row level security;

-- Helper: get caller's role
create or replace function public.my_role()
returns text language sql security definer stable as $$
  select role from public.profiles where id = auth.uid();
$$;

-- Helper: is caller admin?
create or replace function public.is_admin()
returns boolean language sql security definer stable as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

-- PROFILES policies
create policy "Users can read own profile"
  on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "Users can update own profile"
  on public.profiles for update using (id = auth.uid());
create policy "Admin can manage all profiles"
  on public.profiles for all using (public.is_admin());

-- EVENTS policies
create policy "Organisers see own events; admins see all"
  on public.events for select
  using (org_id = auth.uid() or public.is_admin());
create policy "Organisers can insert own events"
  on public.events for insert
  with check (org_id = auth.uid());
create policy "Organisers can update own events; admins can update any"
  on public.events for update
  using (org_id = auth.uid() or public.is_admin());
create policy "Organisers can delete own draft events; admins can delete any"
  on public.events for delete
  using (org_id = auth.uid() or public.is_admin());

-- Public can read approved events (for public booking page)
create policy "Public can read approved events"
  on public.events for select
  using (approval_status = 'approved');

-- SEATING LAYOUTS — organiser/admin only
create policy "Org/admin can manage layouts"
  on public.seating_layouts for all
  using (
    public.is_admin() or
    exists (select 1 from public.events e where e.id=event_id and e.org_id=auth.uid())
  );
create policy "Public can read layouts for approved events"
  on public.seating_layouts for select
  using (
    exists (select 1 from public.events e where e.id=event_id and e.approval_status='approved')
  );

-- SEATS — organiser/admin write, public read for approved events
create policy "Org/admin can manage seats"
  on public.seats for all
  using (
    public.is_admin() or
    exists (select 1 from public.events e where e.id=event_id and e.org_id=auth.uid())
  );
create policy "Public can read seats for approved events"
  on public.seats for select
  using (
    exists (select 1 from public.events e where e.id=event_id and e.approval_status='approved')
  );

-- TICKETS — org/admin manage, no public read (tickets are sensitive)
create policy "Org/admin can manage tickets"
  on public.tickets for all
  using (
    public.is_admin() or
    exists (select 1 from public.events e where e.id=event_id and e.org_id=auth.uid())
  );
-- Scanner validation: allow reading a ticket by its code (for check-in)
-- This is handled via a security-definer RPC function (see below)

-- RESERVATIONS — org/admin manage, public can insert and read own by ref
create policy "Org/admin can manage reservations"
  on public.reservations for all
  using (
    public.is_admin() or
    exists (select 1 from public.events e where e.id=event_id and e.org_id=auth.uid())
  );
create policy "Anyone can insert a reservation"
  on public.reservations for insert with check (true);
create policy "Anyone can read reservation by ref (for status page)"
  on public.reservations for select using (true);

-- ─────────────────────────────────────────────────────────────
-- RPC FUNCTIONS (security definer — bypass RLS where needed)
-- ─────────────────────────────────────────────────────────────

-- Scan ticket by code (used by public scanner after scanner_code auth)
create or replace function public.scan_ticket(p_code text)
returns json language plpgsql security definer as $$
declare
  v_ticket public.tickets%rowtype;
  v_event  public.events%rowtype;
  v_seat   public.seats%rowtype;
begin
  select * into v_ticket from public.tickets
    where code = p_code or qr_data = p_code
    limit 1;
  if not found then return json_build_object('found', false); end if;

  select * into v_event  from public.events where id = v_ticket.event_id;
  if v_ticket.seat_id is not null then
    select * into v_seat from public.seats where id = v_ticket.seat_id;
  end if;

  return json_build_object(
    'found',          true,
    'id',             v_ticket.id,
    'code',           v_ticket.code,
    'holder',         v_ticket.holder,
    'phone',          v_ticket.phone,
    'checked_in',     v_ticket.checked_in,
    'checked_in_at',  v_ticket.checked_in_at,
    'issued_at',      v_ticket.issued_at,
    'event_name',     v_event.name,
    'seat_section',   v_seat.section,
    'seat_row',       v_seat.row_label,
    'seat_number',    v_seat.seat_number
  );
end;
$$;

-- Check in a ticket (called from scanner, validated by scanner_code in app layer)
create or replace function public.checkin_ticket(p_ticket_id text)
returns json language plpgsql security definer as $$
declare
  v_now timestamptz := now();
begin
  update public.tickets
    set checked_in = true, checked_in_at = v_now
    where id = p_ticket_id and checked_in = false;
  if not found then
    return json_build_object('ok', false, 'msg', 'Already checked in or not found');
  end if;
  return json_build_object('ok', true, 'checked_in_at', v_now);
end;
$$;

-- Approve reservation + generate tickets atomically
create or replace function public.approve_reservation(p_res_id text)
returns json language plpgsql security definer as $$
declare
  v_res     public.reservations%rowtype;
  v_event   public.events%rowtype;
  v_seat    public.seats%rowtype;
  v_tickets text[] := '{}';
  v_code    text;
  v_tid     text;
  v_prefix  text;
  v_sid     text;
begin
  -- Only admin/org can call
  if not (public.is_admin() or exists (
    select 1 from public.reservations r
    join public.events e on e.id=r.event_id
    where r.id=p_res_id and e.org_id=auth.uid()
  )) then
    return json_build_object('ok',false,'msg','Unauthorised');
  end if;

  select * into v_res   from public.reservations where id = p_res_id;
  select * into v_event from public.events       where id = v_res.event_id;
  if not found then return json_build_object('ok',false,'msg','Not found'); end if;

  v_prefix := upper(substr(v_event.name, 1, 3));

  foreach v_sid in array v_res.seat_ids loop
    v_tid  := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    v_code := v_prefix || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
    insert into public.tickets (id, event_id, seat_id, reservation_id, code, qr_data, holder, phone, issued_at)
    values (v_tid, v_res.event_id, v_sid, v_res.id, v_code, 'TKT:'||v_res.event_id||':'||v_code, v_res.name, v_res.phone, now());
    update public.seats set status='sold' where id=v_sid;
    v_tickets := v_tickets || v_tid;
  end loop;

  update public.reservations
    set status='approved', ticket_ids=v_tickets
    where id=p_res_id;

  return json_build_object('ok',true,'ticket_ids',v_tickets);
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- UPDATED_AT trigger
-- ─────────────────────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
create or replace trigger events_updated_at
  before update on public.events
  for each row execute procedure public.set_updated_at();
