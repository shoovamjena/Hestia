-- Hestia Database Schema
-- Table order and constraints may not be valid for execution (for reference and matching logic context).

CREATE TABLE public.spatial_ref_sys (
  srid integer NOT NULL CHECK (srid > 0 AND srid <= 998999),
  auth_name character varying,
  auth_srid integer,
  srtext character varying,
  proj4text character varying,
  CONSTRAINT spatial_ref_sys_pkey PRIMARY KEY (srid)
);

CREATE TABLE public.user_roles (
  id uuid NOT NULL,
  user_type USER-DEFINED NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_roles_pkey PRIMARY KEY (id),
  CONSTRAINT user_roles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);

CREATE TABLE public.users (
  id uuid NOT NULL,
  full_name text NOT NULL,
  phone text UNIQUE,
  email text UNIQUE,
  phone_verified boolean NOT NULL DEFAULT false,
  onboarding_complete boolean NOT NULL DEFAULT false,
  photo_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  email_verified boolean,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);

CREATE TABLE public.household_members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  relationship text NOT NULL,
  date_of_birth date,
  care_notes text,
  primary_service_need USER-DEFINED,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT household_members_pkey PRIMARY KEY (id),
  CONSTRAINT household_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

CREATE TABLE public.recurrence_schedules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  frequency USER-DEFINED NOT NULL,
  days_of_week ARRAY,
  end_date date,
  prefer_same_professional boolean NOT NULL DEFAULT false,
  is_paused boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT recurrence_schedules_pkey PRIMARY KEY (id),
  CONSTRAINT recurrence_schedules_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

CREATE TABLE public.professional_locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL,
  professional_id uuid NOT NULL,
  coordinates USER-DEFINED NOT NULL,
  recorded_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT professional_locations_pkey PRIMARY KEY (id)
);

CREATE TABLE public.certifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  professional_id uuid NOT NULL,
  name text NOT NULL,
  issued_at date NOT NULL,
  expires_at date NOT NULL,
  status USER-DEFINED NOT NULL DEFAULT 'valid'::cert_status,
  document_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT certifications_pkey PRIMARY KEY (id)
);

CREATE TABLE public.session_feedback (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL,
  user_id uuid NOT NULL,
  rating integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  punctuality integer CHECK (punctuality >= 1 AND punctuality <= 5),
  professionalism integer CHECK (professionalism >= 1 AND professionalism <= 5),
  quality integer CHECK (quality >= 1 AND quality <= 5),
  comment text,
  submitted_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT session_feedback_pkey PRIMARY KEY (id),
  CONSTRAINT session_feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

CREATE TABLE public.invoices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL,
  user_id uuid NOT NULL,
  amount numeric NOT NULL,
  status USER-DEFINED NOT NULL DEFAULT 'pending'::invoice_status,
  payment_method text,
  issued_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT invoices_pkey PRIMARY KEY (id),
  CONSTRAINT invoices_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

CREATE TABLE public.audit_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL,
  action text NOT NULL,
  table_affected text NOT NULL,
  record_id uuid,
  old_value jsonb,
  new_value jsonb,
  ip_address inet,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT audit_logs_pkey PRIMARY KEY (id)
);

CREATE TABLE public.notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  target_app text NOT NULL CHECK (target_app = ANY (ARRAY['consumer'::text, 'employee'::text])),
  audience_type text NOT NULL CHECK (audience_type = ANY (ARRAY['all'::text, 'user'::text, 'hub'::text])),
  audience_id uuid,
  title text NOT NULL,
  body text NOT NULL,
  notification_type text DEFAULT 'general'::text,
  sent_by uuid,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT notifications_pkey PRIMARY KEY (id)
);

CREATE TABLE public.admin_alerts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL,
  message text NOT NULL,
  severity text NOT NULL DEFAULT 'medium'::text CHECK (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])),
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT admin_alerts_pkey PRIMARY KEY (id)
);

CREATE TABLE public.hubs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  address text,
  status text NOT NULL DEFAULT 'active'::text,
  max_professionals_per_shift integer DEFAULT 15,
  created_at timestamp with time zone DEFAULT now(),
  latitude double precision,
  longitude double precision,
  CONSTRAINT hubs_pkey PRIMARY KEY (id)
);

CREATE TABLE public.admin_users (
  id uuid NOT NULL,
  full_name text NOT NULL DEFAULT 'Manager'::text,
  employee_id text,
  role text NOT NULL DEFAULT 'hub_manager'::text,
  hub_id uuid,
  email text,
  phone text,
  created_at timestamp with time zone DEFAULT now(),
  is_active boolean DEFAULT true,
  CONSTRAINT admin_users_pkey PRIMARY KEY (id),
  CONSTRAINT admin_users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id),
  CONSTRAINT admin_users_hub_id_fkey FOREIGN KEY (hub_id) REFERENCES public.hubs(id)
);

CREATE TABLE public.professionals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  employee_id text UNIQUE,
  full_name text NOT NULL,
  phone text,
  email text,
  hub_id uuid,
  employment_status text DEFAULT 'active'::text,
  background_check_status text DEFAULT 'pending'::text,
  avg_rating numeric DEFAULT 0.00,
  total_sessions integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  service_pillars ARRAY DEFAULT '{}'::text[],
  years_of_experience integer DEFAULT 0,
  CONSTRAINT professionals_pkey PRIMARY KEY (id),
  CONSTRAINT professionals_hub_id_fkey FOREIGN KEY (hub_id) REFERENCES public.hubs(id)
);

CREATE TABLE public.addresses (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  hub_id uuid,
  flat text,
  street text,
  city text,
  pin_code text,
  is_primary boolean DEFAULT false,
  zone_verified boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT addresses_pkey PRIMARY KEY (id),
  CONSTRAINT addresses_hub_id_fkey FOREIGN KEY (hub_id) REFERENCES public.hubs(id)
);

CREATE TABLE public.caregivers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  phone text,
  email text,
  address text,
  medical_notes text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT caregivers_pkey PRIMARY KEY (id)
);

CREATE TABLE public.bookings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  hub_id uuid,
  professional_id uuid,
  service_type text DEFAULT 'Care'::text,
  status text NOT NULL DEFAULT 'pending'::text,
  scheduled_date date,
  scheduled_time time without time zone,
  duration_hours numeric DEFAULT 2,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT bookings_pkey PRIMARY KEY (id),
  CONSTRAINT bookings_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES public.professionals(id),
  CONSTRAINT bookings_hub_id_fkey FOREIGN KEY (hub_id) REFERENCES public.hubs(id),
  CONSTRAINT bookings_caregiver_id_fkey FOREIGN KEY (professional_id) REFERENCES public.caregivers(id)
);

CREATE TABLE public.sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  booking_id uuid,
  professional_id uuid,
  hub_id uuid,
  status text NOT NULL DEFAULT 'scheduled'::text,
  start_time timestamp with time zone,
  end_time timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT sessions_pkey PRIMARY KEY (id),
  CONSTRAINT sessions_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id),
  CONSTRAINT sessions_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES public.professionals(id),
  CONSTRAINT sessions_hub_id_fkey FOREIGN KEY (hub_id) REFERENCES public.hubs(id)
);

CREATE TABLE public.shifts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  professional_id uuid,
  start_time timestamp with time zone NOT NULL,
  end_time timestamp with time zone NOT NULL,
  status text DEFAULT 'scheduled'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT shifts_pkey PRIMARY KEY (id),
  CONSTRAINT shifts_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES public.professionals(id)
);

CREATE TABLE public.incidents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id uuid,
  professional_id uuid,
  type text NOT NULL,
  description text NOT NULL,
  status text NOT NULL DEFAULT 'open'::text,
  reported_at timestamp with time zone DEFAULT now(),
  CONSTRAINT incidents_pkey PRIMARY KEY (id),
  CONSTRAINT incidents_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id),
  CONSTRAINT incidents_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES public.professionals(id)
);

CREATE TABLE public.activity_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id uuid,
  professional_id uuid,
  activity_type text NOT NULL,
  note text NOT NULL,
  is_scope_flagged boolean DEFAULT false,
  logged_at timestamp with time zone DEFAULT now(),
  CONSTRAINT activity_logs_pkey PRIMARY KEY (id),
  CONSTRAINT activity_logs_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id),
  CONSTRAINT activity_logs_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES public.professionals(id)
);

CREATE TABLE public.messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id uuid,
  sender_type text NOT NULL,
  sender_id uuid NOT NULL,
  content text NOT NULL,
  sent_at timestamp with time zone DEFAULT now(),
  CONSTRAINT messages_pkey PRIMARY KEY (id),
  CONSTRAINT messages_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id)
);

CREATE TABLE public.applicants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  role text NOT NULL DEFAULT 'Service Professional'::text,
  status text NOT NULL DEFAULT 'Pending'::text,
  phone text,
  email text,
  applied_at timestamp with time zone DEFAULT now(),
  CONSTRAINT applicants_pkey PRIMARY KEY (id)
);

CREATE TABLE public.registrations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  phone text NOT NULL UNIQUE,
  email text NOT NULL,
  address text NOT NULL,
  latitude double precision,
  longitude double precision,
  document_type text,
  front_image_url text,
  back_image_url text,
  status text NOT NULL DEFAULT 'pending'::text,
  hub_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT registrations_pkey PRIMARY KEY (id),
  CONSTRAINT registrations_hub_id_fkey FOREIGN KEY (hub_id) REFERENCES public.hubs(id)
);
