-- Enable PostGIS
create extension if not exists postgis;

-- Create profiles table
create table public.profiles (
  id uuid not null references auth.users(id) on delete cascade primary key,
  full_name text,
  id_number text,
  role text check (role in ('Admin', 'Driver', 'Courier', 'Customer')),
  is_student boolean default false,
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users can view their own profile" on public.profiles
  for select using (auth.uid() = id);

create policy "Users can update their own profile" on public.profiles
  for update using (auth.uid() = id);

create policy "Admins can view all profiles" on public.profiles
  for select using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'Admin'
    )
  );

-- Create vehicles table
create table public.vehicles (
  id uuid not null primary key default gen_random_uuid(),
  driver_id uuid references public.profiles(id) not null,
  uts_id text,
  is_online boolean default false,
  current_location geography(Point, 4326),
  updated_at timestamptz default now()
);

create index vehicles_geo_index on public.vehicles using GIST (current_location);

alter table public.vehicles enable row level security;

create policy "Online vehicles are viewable by authenticated users" on public.vehicles
  for select to authenticated using (is_online = true);

create policy "Drivers can update their own vehicle" on public.vehicles
  for update using (auth.uid() = driver_id);

create policy "Drivers can insert their own vehicle" on public.vehicles
  for insert with check (auth.uid() = driver_id);

-- Create orders table
create table public.orders (
  id uuid not null primary key default gen_random_uuid(),
  customer_id uuid references public.profiles(id) not null,
  vehicle_id uuid references public.vehicles(id),
  pickup_coords geography(Point, 4326),
  dropoff_coords geography(Point, 4326),
  fare numeric,
  status text default 'pending',
  created_at timestamptz default now()
);

alter table public.orders enable row level security;

create policy "Users can view their own orders" on public.orders
  for select using (auth.uid() = customer_id);

create policy "Drivers can view assigned orders" on public.orders
  for select using (
    exists (
      select 1 from public.vehicles
      where id = orders.vehicle_id and driver_id = auth.uid()
    )
  );

-- RPC for finding nearby vehicles
-- This avoids client-side filtering and leverages PostGIS index
create or replace function nearby_vehicles(
  lat float,
  long float
)
returns table (
  id uuid,
  driver_id uuid,
  uts_id text,
  lat float,
  long float,
  dist_meters float
)
language plpgsql
security definer
as $$
begin
  return query
  select
    v.id,
    v.driver_id,
    v.uts_id,
    st_y(v.current_location::geometry) as lat,
    st_x(v.current_location::geometry) as long,
    st_distance(v.current_location, st_point(long, lat)::geography) as dist_meters
  from
    public.vehicles v
  where
    v.is_online = true
    and st_dwithin(v.current_location, st_point(long, lat)::geography, 2000) -- 2km radius
  order by
    v.current_location <-> st_point(long, lat)::geography
  limit 5;
end;
$$;
