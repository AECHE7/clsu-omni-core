import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    );

    const {
      pickup_lat,
      pickup_lng,
      dropoff_lat,
      dropoff_lng,
    } = await req.json();

    if (!pickup_lat || !pickup_lng || !dropoff_lat || !dropoff_lng) {
      throw new Error('Missing coordinates');
    }

    // 1. Get User Profile for Discount Logic
    const {
      data: { user },
    } = await supabaseClient.auth.getUser();

    if (!user) throw new Error('Unauthorized');

    const { data: profile } = await supabaseClient
      .from('profiles')
      .select('is_student')
      .eq('id', user.id)
      .single();

    const isStudent = profile?.is_student ?? false;

    // 2. Find Nearby Vehicles (PostGIS 2km radius, limit 5)
    const { data: nearbyDrivers, error: nearbyError } = await supabaseClient
      .rpc('nearby_vehicles', {
        lat: pickup_lat,
        long: pickup_lng,
      });

    if (nearbyError) throw nearbyError;
    if (!nearbyDrivers || nearbyDrivers.length === 0) {
      return new Response(
        JSON.stringify({ drivers: [] }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const geoapifyKey = Deno.env.get('GEOAPIFY_API_KEY');
    if (!geoapifyKey) throw new Error('Missing GEOAPIFY_API_KEY');

    // 3. Geoapify Route Matrix (Drivers -> Pickup)
    const driverLocations = nearbyDrivers.map((d: any) => ({
      location: [d.long, d.lat], // Geoapify expects [lon, lat]
    }));
    const pickupLocation = [{ location: [pickup_lng, pickup_lat] }];

    const matrixBody = {
      mode: 'motorcycle',
      sources: driverLocations,
      targets: pickupLocation,
    };

    const matrixRes = await fetch(`https://api.geoapify.com/v1/routematrix?apiKey=${geoapifyKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(matrixBody),
    });

    if (!matrixRes.ok) {
      const errText = await matrixRes.text();
      console.error('Geoapify Matrix Error:', errText);
      throw new Error('Failed to fetch route matrix');
    }

    const matrixData = await matrixRes.json();
    // matrixData.sources_to_targets[source_index][target_index]
    // We only have 1 target (pickup), so we iterate sources.

    // 4. Geoapify Routing (Pickup -> Dropoff) for Trip Distance
    const routingRes = await fetch(
      `https://api.geoapify.com/v1/routing?waypoints=${pickup_lat},${pickup_lng}|${dropoff_lat},${dropoff_lng}&mode=motorcycle&apiKey=${geoapifyKey}`
    );

    if (!routingRes.ok) {
        const errText = await routingRes.text();
        console.error('Geoapify Routing Error:', errText);
        throw new Error('Failed to fetch trip route');
    }

    const routingData = await routingRes.json();
    const tripFeature = routingData.features?.[0];
    const tripDistanceMeters = tripFeature?.properties?.distance; // meters

    if (tripDistanceMeters === undefined) {
        throw new Error('Could not calculate trip distance');
    }

    const tripDistanceKm = tripDistanceMeters / 1000;

    // 5. Calculate Fare
    // Base: 35.00 for 1st km. Succeeding: 15.00 per km.
    const baseFare = 35.00;
    const additionalKm = Math.max(0, tripDistanceKm - 1);
    const distanceFare = additionalKm * 15.00;
    let totalFare = baseFare + distanceFare;

    if (isStudent) {
      totalFare = totalFare * 0.8; // 20% discount
    }

    // 6. Assemble Result
    // Combine nearbyDrivers with Matrix ETA
    const results = nearbyDrivers.map((driver: any, index: number) => {
      const matrixInfo = matrixData.sources_to_targets?.[index]?.[0];
      return {
        vehicle_id: driver.id,
        uts_id: driver.uts_id,
        eta_to_pickup_seconds: matrixInfo?.time ?? null,
        distance_to_pickup_meters: matrixInfo?.distance ?? null, // Driving distance to pickup
        trip_fare: parseFloat(totalFare.toFixed(2)),
        trip_distance_meters: tripDistanceMeters
      };
    });

    // Sort by ETA (asc) and take top 3
    results.sort((a: any, b: any) => (a.eta_to_pickup_seconds || 999999) - (b.eta_to_pickup_seconds || 999999));
    const top3 = results.slice(0, 3);

    return new Response(
      JSON.stringify({ drivers: top3 }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
