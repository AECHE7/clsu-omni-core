
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getMockQrResponse } from "./mock_data.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const {
      merchant_payment_code,
      amount_total,
      currency_code,
      payment_type_code,
      customer_details,
      description
    } = await req.json();

    // Environment variables
    const isMock = Deno.env.get("IS_MOCK") !== "false"; // Default to true if not set or set to anything other than "false"
    const merchantId = Deno.env.get("MERCHANT_ID");
    const secretKey = Deno.env.get("SECRET_KEY");

    // Input validation (basic)
    if (!merchant_payment_code || !amount_total) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: merchant_payment_code or amount_total" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
      );
    }

    // 1. Mock Mode
    if (isMock) {
      console.log("Processing in MOCK MODE");
      const mockResponse = getMockQrResponse();
      return new Response(
        JSON.stringify(mockResponse),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    // 2. Real API Mode
    if (!merchantId || !secretKey) {
      console.error("Missing Merchant Credentials in Secrets");
      return new Response(
        JSON.stringify({ error: "Server Configuration Error" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    // Construct Basic Auth Header
    const authString = btoa(`${merchantId}:${secretKey}`);
    const headers = {
      "Authorization": `Basic ${authString}`,
      "Content-Type": "application/json",
      "Accept": "application/json"
    };

    // Construct Payload
    // DPA/Security Note: Do not log customer_details
    const payload = {
      merchant_payment_code,
      amount_total,
      currency_code: currency_code || "php",
      payment_type_code: payment_type_code || "qrph",
      customer_details, // includes name, email, phone_number
      description
    };

    console.log(`Sending request to Landbank for Order: ${merchant_payment_code}, Amount: ${amount_total}`);

    const response = await fetch("https://www.lbp-eservices.com/egps/portal/api/v1/generate-qr", {
      method: "POST",
      headers: headers,
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Landbank API Error:", response.status, errorText);
      return new Response(
        JSON.stringify({ error: "Failed to generate QR from provider", details: errorText }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: response.status }
      );
    }

    const data = await response.json();

    // Map external response to our internal format if necessary
    // Assuming the API returns the format we want directly, or we map it here.
    // Based on requirements, we return qr_image_base64, redirect_url, transaction_id.
    // If the API differs, this mapping would need adjustment based on actual API response docs.
    // For now, passing through data assuming alignment or standard fields.

    return new Response(
      JSON.stringify(data),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );

  } catch (error) {
    console.error("Edge Function Error:", error.message);
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
    );
  }
});
