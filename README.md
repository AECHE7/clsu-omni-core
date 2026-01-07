CLSU-Omni: Integrated Campus Management & Logistics SaaS
🚀 Project Overview
CLSU-Omni is a centralized digital layer designed specifically for the Central Luzon State University (CLSU) ecosystem in the Science City of Muñoz, Nueva Ecija. The project aims to solve "last-mile" logistical inefficiencies across the 654-hectare campus, serving a population of over 14,000 students and 500+ faculty members.

The platform transforms manual, street-hailing transport and fragmented food delivery into a unified, "Cash-Lite" digital experience.

🛠 Tech Stack
Frontend: FlutterFlow (Cross-platform mobile & web)

Backend/Database: Supabase (PostgreSQL + PostGIS extension)

Logic Layer: Supabase Edge Functions (TypeScript/Deno)

Mapping & GIS: Geoapify Route Matrix API & OpenStreetMap

Payments: Landbank LinkBizPortal API (QR Ph Integration)

AI Agent: Jules (Autonomous coding and backend orchestration)

📦 Core Modules
Transport Hub (Tricycle e-Hailing): Real-time booking for the ~100 registered University Transport System (UTS) tricycles with automated fare calculation based on official university matrices.

Campus Express (Logistics): A student-to-student courier network for food delivery from the University Canteen and Alumni Food Court to distant colleges and dormitories.

AR Navigator: Augmented Reality wayfinding to assist visitors and freshmen in locating specific RIC (Records-in-Charge) offices and research laboratories.

🏛 Institutional Context & Compliance
Cash-Lite Campus: All financial transactions must align with the university’s initiative to reduce cash dependency, utilizing Landbank Piso Plus accounts.

UTS Regulations: Operations must follow Resolution No. 7-2023 regarding tricycle operating hours (6 AM - 8 PM) and fare matrices.

Data Privacy: The system is designed to comply with the Philippine Data Privacy Act (RA 10173), employing strict Row Level Security (RLS) and data minimization for student location tracking.

🤖 Instructions for Jules (AI Agent)
Database: Use migrations in supabase/migrations/. Always ensure the postgis extension is enabled for geospatial queries.

Security: Implement Row Level Security (RLS) on every table. Users should only see data relevant to their role (Student, Driver, Courier, or Admin).

Architecture: Prefer Supabase Edge Functions for external API integrations (Landbank, Geoapify).

Conventions: Follow standard TypeScript/Deno patterns for functions and clean SQL for migrations. Use the auth.uid() function to verify user identity in all policies.

📂 Project Structure
/supabase/migrations: SQL scripts for schema updates.

/supabase/functions: Backend logic for payments and routing.

/docs: Capstone manuscript and technical documentation.
