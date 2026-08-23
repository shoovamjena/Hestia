-- Server-side hub coverage authority (7 km).
-- Run in Supabase SQL Editor (or via supabase db push).
--
-- Adds address coordinates, haversine helpers, RPC for clients,
-- and triggers so zone_verified / hub_id cannot be spoofed by the app.

-- 1) Persist coordinates on addresses
ALTER TABLE public.addresses
  ADD COLUMN IF NOT EXISTS latitude double precision;

ALTER TABLE public.addresses
  ADD COLUMN IF NOT EXISTS longitude double precision;

COMMENT ON COLUMN public.addresses.latitude IS
  'Saved pin latitude; used for server-side hub coverage checks';
COMMENT ON COLUMN public.addresses.longitude IS
  'Saved pin longitude; used for server-side hub coverage checks';

-- 2) Single source of truth for radius (change here only)
CREATE OR REPLACE FUNCTION public.coverage_radius_km()
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 7.0::double precision;
$$;

-- 3) Haversine distance in km
CREATE OR REPLACE FUNCTION public.haversine_km(
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 2 * 6371 * asin(
    sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) *
      power(sin(radians(lon2 - lon1) / 2), 2)
    )
  );
$$;

-- 4) Nearest hub + whether it is within coverage
CREATE OR REPLACE FUNCTION public.find_nearest_hub(
  p_lat double precision,
  p_lng double precision
)
RETURNS TABLE (
  hub_id uuid,
  distance_km double precision,
  within_coverage boolean
)
LANGUAGE sql
STABLE
AS $$
  WITH ranked AS (
    SELECT
      h.id AS hub_id,
      public.haversine_km(p_lat, p_lng, h.latitude, h.longitude) AS distance_km
    FROM public.hubs h
    WHERE h.latitude IS NOT NULL
      AND h.longitude IS NOT NULL
      AND NOT (h.latitude = 0 AND h.longitude = 0)
      AND COALESCE(h.status, 'active') <> 'inactive'
  )
  SELECT
    r.hub_id,
    r.distance_km,
    (r.distance_km <= public.coverage_radius_km()) AS within_coverage
  FROM ranked r
  ORDER BY r.distance_km ASC
  LIMIT 1;
$$;

-- 5) RPC used by Flutter / edge functions
CREATE OR REPLACE FUNCTION public.resolve_hub_coverage(
  p_lat double precision,
  p_lng double precision
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  nearest record;
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN jsonb_build_object(
      'hub_id', NULL,
      'distance_km', NULL,
      'zone_verified', false,
      'coverage_radius_km', public.coverage_radius_km(),
      'error', 'missing_coordinates'
    );
  END IF;

  SELECT * INTO nearest FROM public.find_nearest_hub(p_lat, p_lng);

  IF nearest.hub_id IS NULL THEN
    RETURN jsonb_build_object(
      'hub_id', NULL,
      'distance_km', NULL,
      'zone_verified', false,
      'coverage_radius_km', public.coverage_radius_km(),
      'error', 'no_hubs'
    );
  END IF;

  RETURN jsonb_build_object(
    'hub_id', nearest.hub_id,
    'distance_km', nearest.distance_km,
    'zone_verified', nearest.within_coverage,
    'coverage_radius_km', public.coverage_radius_km()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_hub_coverage(double precision, double precision)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.coverage_radius_km() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.haversine_km(double precision, double precision, double precision, double precision)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.find_nearest_hub(double precision, double precision)
  TO anon, authenticated, service_role;

-- 6) On address write: recompute hub + zone from coordinates (server authority)
CREATE OR REPLACE FUNCTION public.addresses_apply_coverage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  nearest record;
BEGIN
  IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
    -- Without coordinates we cannot verify; keep client hub_id but force unverified
    -- unless an existing verified row is being updated without changing coords.
    IF TG_OP = 'INSERT' THEN
      NEW.zone_verified := false;
    ELSIF NEW.latitude IS DISTINCT FROM OLD.latitude
       OR NEW.longitude IS DISTINCT FROM OLD.longitude THEN
      NEW.zone_verified := false;
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO nearest
  FROM public.find_nearest_hub(NEW.latitude, NEW.longitude);

  IF nearest.hub_id IS NULL THEN
    NEW.zone_verified := false;
    RETURN NEW;
  END IF;

  -- Always bind to the nearest hub for ops, but only mark serviceable inside radius
  NEW.hub_id := nearest.hub_id;
  NEW.zone_verified := nearest.within_coverage;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_addresses_apply_coverage ON public.addresses;
CREATE TRIGGER trg_addresses_apply_coverage
  BEFORE INSERT OR UPDATE OF latitude, longitude, hub_id, zone_verified
  ON public.addresses
  FOR EACH ROW
  EXECUTE FUNCTION public.addresses_apply_coverage();

-- 7) Block new bookings when the linked address is outside coverage
CREATE OR REPLACE FUNCTION public.bookings_require_hub_coverage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  addr_id uuid;
  addr_verified boolean;
  addr_lat double precision;
  addr_lng double precision;
  nearest record;
BEGIN
  -- Only enforce for newly created consumer bookings
  IF TG_OP <> 'INSERT' THEN
    RETURN NEW;
  END IF;

  BEGIN
    addr_id := NULLIF(NEW.notes::jsonb ->> 'address_id', '')::uuid;
  EXCEPTION WHEN others THEN
    addr_id := NULL;
  END;

  IF addr_id IS NOT NULL THEN
    SELECT zone_verified, latitude, longitude
      INTO addr_verified, addr_lat, addr_lng
    FROM public.addresses
    WHERE id = addr_id;
  ELSIF NEW.user_id IS NOT NULL THEN
    SELECT zone_verified, latitude, longitude
      INTO addr_verified, addr_lat, addr_lng
    FROM public.addresses
    WHERE user_id = NEW.user_id
    ORDER BY is_primary DESC, created_at DESC
    LIMIT 1;
  END IF;

  -- Prefer stored flag when present
  IF addr_verified IS TRUE THEN
    RETURN NEW;
  END IF;

  -- Recompute if we have coordinates (covers stale zone_verified)
  IF addr_lat IS NOT NULL AND addr_lng IS NOT NULL THEN
    SELECT * INTO nearest FROM public.find_nearest_hub(addr_lat, addr_lng);
    IF nearest.within_coverage IS TRUE THEN
      NEW.hub_id := COALESCE(NEW.hub_id, nearest.hub_id);
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Address is outside the % km hub coverage radius',
      public.coverage_radius_km()
      USING ERRCODE = 'check_violation';
  END IF;

  -- No coords and not verified → reject (prevents spoofed hub_id bookings)
  IF addr_verified IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Address is not in a serviceable hub coverage area'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bookings_require_hub_coverage ON public.bookings;
CREATE TRIGGER trg_bookings_require_hub_coverage
  BEFORE INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.bookings_require_hub_coverage();
