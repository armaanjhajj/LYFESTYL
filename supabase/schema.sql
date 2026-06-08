-- ============================================================================
-- LYFESTYL — Supabase schema
-- ----------------------------------------------------------------------------
-- Paste this whole file into the Supabase dashboard → SQL Editor → New query
-- → Run. It is idempotent (safe to run more than once).
--
-- Model: one `entries` row per journal entry; one `insights` row per category
-- the on-device model produced. Metrics are fixed columns so trend queries are
-- trivial. Row Level Security ensures each user only ever sees their own rows.
-- ============================================================================

-- gen_random_uuid() lives in pgcrypto (enabled by default on Supabase; harmless
-- to assert).
create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- profiles — lightweight mirror of auth.users
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    display_name text,
    created_at   timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- entries — one raw journal entry (typed or transcribed voice)
-- ----------------------------------------------------------------------------
create table if not exists public.entries (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references auth.users (id) on delete cascade,
    raw_text        text not null,
    source          text not null default 'text'  check (source in ('text','voice')),
    status          text not null default 'pending'
                        check (status in ('pending','processing','processed','failed')),
    schema_version  int  not null default 1,
    overall_summary text,
    created_at      timestamptz not null default now(),
    entry_date      date not null default (now() at time zone 'utc')::date
);

-- ----------------------------------------------------------------------------
-- insights — the structured breakdown (one row per category, per entry)
-- ----------------------------------------------------------------------------
create table if not exists public.insights (
    id             uuid primary key default gen_random_uuid(),
    entry_id       uuid not null references public.entries (id) on delete cascade,
    user_id        uuid not null references auth.users (id) on delete cascade,
    category       text not null check (category in ('NUTRITION','ACTIVITY','SLEEP','HEALTH')),
    rank           text not null check (rank in ('EXCELLENT','GOOD','OKAY','BAD','AWFUL')),
    rank_score     int  not null check (rank_score between 1 and 5),
    title          text,
    detail         text,
    -- Nutrition
    calories       int,
    protein_grams  int,
    carbs_grams    int,
    fat_grams      int,
    water_ounces   int,
    -- Activity
    active_minutes int,
    distance_miles double precision,
    -- Sleep
    sleep_hours    double precision,
    created_at     timestamptz not null default now(),
    entry_date     date not null
);

-- ----------------------------------------------------------------------------
-- Indexes for fast per-user, per-day, per-category trend queries
-- ----------------------------------------------------------------------------
create index if not exists entries_user_date_idx   on public.entries (user_id, entry_date desc);
create index if not exists entries_user_created_idx on public.entries (user_id, created_at desc);
create index if not exists insights_entry_idx       on public.insights (entry_id);
create index if not exists insights_user_cat_date_idx on public.insights (user_id, category, entry_date);

-- ----------------------------------------------------------------------------
-- Row Level Security — every row is private to its owner
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.entries  enable row level security;
alter table public.insights enable row level security;

-- profiles: a user can read/write only their own profile row
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
    for select using (auth.uid() = id);
drop policy if exists "profiles_upsert_own" on public.profiles;
create policy "profiles_upsert_own" on public.profiles
    for insert with check (auth.uid() = id);
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
    for update using (auth.uid() = id) with check (auth.uid() = id);

-- entries: full CRUD scoped to the owner
drop policy if exists "entries_select_own" on public.entries;
create policy "entries_select_own" on public.entries
    for select using (auth.uid() = user_id);
drop policy if exists "entries_insert_own" on public.entries;
create policy "entries_insert_own" on public.entries
    for insert with check (auth.uid() = user_id);
drop policy if exists "entries_update_own" on public.entries;
create policy "entries_update_own" on public.entries
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "entries_delete_own" on public.entries;
create policy "entries_delete_own" on public.entries
    for delete using (auth.uid() = user_id);

-- insights: full CRUD scoped to the owner
drop policy if exists "insights_select_own" on public.insights;
create policy "insights_select_own" on public.insights
    for select using (auth.uid() = user_id);
drop policy if exists "insights_insert_own" on public.insights;
create policy "insights_insert_own" on public.insights
    for insert with check (auth.uid() = user_id);
drop policy if exists "insights_update_own" on public.insights;
create policy "insights_update_own" on public.insights
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "insights_delete_own" on public.insights;
create policy "insights_delete_own" on public.insights
    for delete using (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- Auto-create a profile row when a new user signs up (optional convenience;
-- the app also upserts the profile on sign-in).
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (id, display_name)
    values (new.id, new.raw_user_meta_data ->> 'full_name')
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
