-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- -------------------------------------------------------------------------
-- ENUMS
-- -------------------------------------------------------------------------
CREATE TYPE public.user_role AS ENUM (
    'Admin',
    'Driver',
    'Courier',
    'Customer'
);

CREATE TYPE public.vehicle_type AS ENUM (
    'Tricycle',
    'Bicycle',
    'Walker'
);

CREATE TYPE public.order_type AS ENUM (
    'Ride',
    'Food',
    'Parcel'
);

CREATE TYPE public.order_status AS ENUM (
    'pending',
    'accepted',
    'picking_up',
    'in_transit',
    'delivered',
    'cancelled'
);

CREATE TYPE public.payment_status AS ENUM (
    'pending',
    'paid',
    'failed',
    'refunded'
);

-- -------------------------------------------------------------------------
-- TABLES
-- -------------------------------------------------------------------------

-- 1. Profiles (Linked to auth.users)
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    clsu_id_number TEXT,
    phone_number TEXT,
    college_department TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    role public.user_role NOT NULL DEFAULT 'Customer',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Campus Zones (For Logic)
CREATE TABLE public.campus_zones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    boundary GEOMETRY(POLYGON, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Vehicles
CREATE TABLE public.vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    uts_id_number TEXT,
    vehicle_type public.vehicle_type NOT NULL,
    capacity INTEGER DEFAULT 1,
    is_online BOOLEAN DEFAULT FALSE,
    current_location GEOGRAPHY(POINT, 4326),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Orders
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.profiles(id),
    provider_id UUID REFERENCES public.profiles(id),
    order_type public.order_type NOT NULL,
    pickup_location GEOGRAPHY(POINT, 4326) NOT NULL,
    dropoff_location GEOGRAPHY(POINT, 4326) NOT NULL,
    estimated_fare DECIMAL(10, 2),
    actual_fare DECIMAL(10, 2),
    payment_method TEXT CHECK (payment_method IN ('Cash', 'LinkBiz_QR')),
    payment_status public.payment_status DEFAULT 'pending',
    status public.order_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- -------------------------------------------------------------------------
-- INDEXES
-- -------------------------------------------------------------------------
CREATE INDEX idx_campus_zones_boundary ON public.campus_zones USING GIST (boundary);
CREATE INDEX idx_vehicles_location ON public.vehicles USING GIST (current_location);
CREATE INDEX idx_orders_pickup ON public.orders USING GIST (pickup_location);
CREATE INDEX idx_orders_dropoff ON public.orders USING GIST (dropoff_location);
CREATE INDEX idx_orders_customer ON public.orders(customer_id);
CREATE INDEX idx_orders_provider ON public.orders(provider_id);
CREATE INDEX idx_orders_status ON public.orders(status);

-- -------------------------------------------------------------------------
-- ROW LEVEL SECURITY (RLS)
-- -------------------------------------------------------------------------

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campus_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Helper function to check if user is Admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'Admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- --- Profiles ---
-- Users can view their own profile. Admins can view all.
CREATE POLICY "Users can view own profile" ON public.profiles
    FOR SELECT USING (auth.uid() = id OR public.is_admin());

-- Users can update their own profile. Admins can update all.
CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE USING (auth.uid() = id OR public.is_admin());

-- Insert handled by trigger usually, but allow self-insert if needed or Admin
CREATE POLICY "Service role or Admin can insert profiles" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id OR public.is_admin());


-- --- Campus Zones ---
-- Authenticated users can view zones (needed for location logic)
CREATE POLICY "Authenticated users can view zones" ON public.campus_zones
    FOR SELECT TO authenticated USING (true);

-- Only Admins can manage zones
CREATE POLICY "Admins can manage zones" ON public.campus_zones
    FOR ALL USING (public.is_admin());


-- --- Vehicles ---
-- Admin can view all
CREATE POLICY "Admins can view all vehicles" ON public.vehicles
    FOR SELECT USING (public.is_admin());

-- Providers can view their own vehicle
CREATE POLICY "Providers can view own vehicle" ON public.vehicles
    FOR SELECT USING (auth.uid() = provider_id);

-- Customers generally DO NOT select from vehicles table directly (privacy).
-- They use the get_nearby_vehicles RPC.
-- However, if they have an active order, they might need to track the assigned vehicle.
CREATE POLICY "Customers can track assigned vehicle" ON public.vehicles
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.provider_id = vehicles.provider_id
            AND orders.customer_id = auth.uid()
            AND orders.status IN ('accepted', 'picking_up', 'in_transit')
        )
    );

-- Providers can update their own vehicle (location/status)
CREATE POLICY "Providers can update own vehicle" ON public.vehicles
    FOR UPDATE USING (auth.uid() = provider_id);

-- Admin manage
CREATE POLICY "Admins can manage vehicles" ON public.vehicles
    FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY "Admins can delete vehicles" ON public.vehicles
    FOR DELETE USING (public.is_admin());


-- --- Orders ---
-- Admin view all
CREATE POLICY "Admins can view all orders" ON public.orders
    FOR SELECT USING (public.is_admin());

-- Customers view their own orders
CREATE POLICY "Customers can view own orders" ON public.orders
    FOR SELECT USING (auth.uid() = customer_id);

-- Providers view orders assigned to them
CREATE POLICY "Providers can view assigned orders" ON public.orders
    FOR SELECT USING (auth.uid() = provider_id);

-- Drivers/Couriers view PENDING orders in their current ZONE
-- Logic: The order is pending AND The order's pickup location is in a zone
-- AND the driver's vehicle is in the SAME zone.
CREATE POLICY "Drivers see pending orders in their zone" ON public.orders
    FOR SELECT
    TO authenticated
    USING (
        status = 'pending' AND
        EXISTS (
            SELECT 1
            FROM public.profiles p
            JOIN public.vehicles v ON v.provider_id = p.id
            JOIN public.campus_zones z ON ST_Intersects(v.current_location::geometry, z.boundary)
            WHERE p.id = auth.uid()
            AND (p.role = 'Driver' OR p.role = 'Courier')
            AND ST_Intersects(orders.pickup_location::geometry, z.boundary)
        )
    );

-- Customers can insert orders
CREATE POLICY "Customers can create orders" ON public.orders
    FOR INSERT WITH CHECK (auth.uid() = customer_id);

-- Providers can update orders assigned to them (e.g. status)
CREATE POLICY "Providers can update assigned orders" ON public.orders
    FOR UPDATE USING (auth.uid() = provider_id);

-- Customers can cancel (update) their own orders if pending
CREATE POLICY "Customers can cancel own pending orders" ON public.orders
    FOR UPDATE USING (auth.uid() = customer_id AND status = 'pending');


-- -------------------------------------------------------------------------
-- FUNCTIONS
-- -------------------------------------------------------------------------

-- 1. Get Nearby Vehicles (RPC)
-- Security Definer to bypass RLS on vehicles table for the search
CREATE OR REPLACE FUNCTION public.get_nearby_vehicles(
    lat DOUBLE PRECISION,
    long DOUBLE PRECISION,
    radius_meters DOUBLE PRECISION DEFAULT 1000
)
RETURNS TABLE (
    vehicle_id UUID,
    provider_id UUID,
    vehicle_type public.vehicle_type,
    lat DOUBLE PRECISION,
    long DOUBLE PRECISION,
    dist_meters DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.id as vehicle_id,
        v.provider_id,
        v.vehicle_type,
        ST_Y(v.current_location::geometry) as lat,
        ST_X(v.current_location::geometry) as long,
        ST_Distance(
            v.current_location,
            ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography
        ) as dist_meters
    FROM
        public.vehicles v
    WHERE
        v.is_online = TRUE
        AND ST_DWithin(
            v.current_location,
            ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography,
            radius_meters
        );
END;
$$;

-- 2. Handle New User (Trigger)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
        COALESCE((NEW.raw_user_meta_data->>'role')::public.user_role, 'Customer')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call handle_new_user on auth.users insert
-- Note: In a real migration, we might check if the trigger exists first or drop it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
