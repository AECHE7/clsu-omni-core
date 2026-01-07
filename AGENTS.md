CLSU-Omni (Campus Logistics SaaS) Tech Stack: FlutterFlow (Frontend), Supabase (Backend/PostgreSQL/PostGIS), Geoapify (Mapping). Logic Patterns: Use A* algorithm for campus pathfinding. All payments must route through the Landbank LinkBiz API. Security: Strictly follow the Philippine Data Privacy Act (DPA).

## Function: generate-payment-qr
Wrapper for the Landbank LinkBizPortal API to generate dynamic QR codes for payments.

### Environment Variables (Secrets)
- `MERCHANT_ID`: Your Landbank Merchant ID.
- `SECRET_KEY`: Your Landbank Secret Key.
- `IS_MOCK`: Set to `true` (default) to return mock data, or `false` to hit the live API.

### API Usage
**Endpoint:** POST `/generate-payment-qr`

**Payload:**
```json
{
  "merchant_payment_code": "ORDER-123",
  "amount_total": 100.00,
  "currency_code": "php",
  "payment_type_code": "qrph",
  "customer_details": {
    "name": "Juan Dela Cruz",
    "email": "juan@example.com",
    "phone_number": "09123456789"
  },
  "description": "CLSU-Omni Ride Fare"
}
```

**Response:**
```json
{
  "qr_image_base64": "...",
  "redirect_url": "...",
  "transaction_id": "..."
}
```
