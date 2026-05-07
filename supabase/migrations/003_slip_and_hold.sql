-- ============================================================
-- TICKR — Migration 003: Payment slip + atomic seat hold
-- Run in Supabase SQL Editor
-- ============================================================

-- Add payment slip column to reservations
alter table public.reservations
  add column if not exists payment_slip text default null;

-- ── hold_seats RPC ───────────────────────────────────────────
-- Called by public booking page (security definer bypasses RLS).
-- Atomically checks all seats are still available then holds them.
create or replace function public.hold_seats(p_seat_ids text[])
returns json language plpgsql security definer as $$
declare
  v_unavailable text[];
begin
  if p_seat_ids is null or array_length(p_seat_ids, 1) is null then
    return json_build_object('ok', true);
  end if;

  select array_agg(id) into v_unavailable
    from public.seats
    where id = any(p_seat_ids) and status <> 'available';

  if v_unavailable is not null and array_length(v_unavailable, 1) > 0 then
    return json_build_object('ok', false, 'msg', 'Seats no longer available');
  end if;

  update public.seats set status = 'held' where id = any(p_seat_ids);
  return json_build_object('ok', true);
end;
$$;

-- ── release_held_seats RPC ───────────────────────────────────
-- Called when admin rejects a reservation (security definer).
create or replace function public.release_held_seats(p_seat_ids text[])
returns void language plpgsql security definer as $$
begin
  if p_seat_ids is null or array_length(p_seat_ids, 1) is null then return; end if;
  update public.seats set status = 'available'
    where id = any(p_seat_ids) and status in ('held', 'reserved');
end;
$$;
