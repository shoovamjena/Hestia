-- Consumer tracking needs lat/lng as plain numbers.
-- Staff app draws routes from on-device GPS; consumer reads professional_locations.
-- PostGIS geography is awkward to parse in Flutter, so expose an RPC.

CREATE OR REPLACE FUNCTION public.get_latest_professional_location(
  p_session_id uuid DEFAULT NULL,
  p_professional_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result json;
  v_allowed boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  -- Session-scoped lookup (preferred).
  IF p_session_id IS NOT NULL THEN
    -- Booking owner (consumer)
    SELECT EXISTS (
      SELECT 1
      FROM public.sessions s
      JOIN public.bookings b ON b.id = s.booking_id
      WHERE s.id = p_session_id
        AND b.user_id = auth.uid()
    )
    INTO v_allowed;

    -- Professional account (staff ids match professionals.id)
    IF NOT v_allowed THEN
      SELECT EXISTS (
        SELECT 1
        FROM public.sessions s
        WHERE s.id = p_session_id
          AND s.professional_id = auth.uid()
      )
      INTO v_allowed;
    END IF;

    IF v_allowed THEN
      SELECT json_build_object(
        'latitude', ST_Y(pl.coordinates::geometry),
        'longitude', ST_X(pl.coordinates::geometry),
        'recorded_at', pl.recorded_at
      )
      INTO v_result
      FROM public.professional_locations pl
      WHERE pl.session_id = p_session_id
      ORDER BY pl.recorded_at DESC
      LIMIT 1;

      IF v_result IS NOT NULL THEN
        RETURN v_result;
      END IF;
    END IF;
  END IF;

  -- Professional-scoped fallback for the assigned consumer booking.
  IF p_professional_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.professional_id = p_professional_id
        AND b.user_id = auth.uid()
    )
    OR p_professional_id = auth.uid()
    INTO v_allowed;

    IF v_allowed THEN
      SELECT json_build_object(
        'latitude', ST_Y(pl.coordinates::geometry),
        'longitude', ST_X(pl.coordinates::geometry),
        'recorded_at', pl.recorded_at
      )
      INTO v_result
      FROM public.professional_locations pl
      WHERE pl.professional_id = p_professional_id
      ORDER BY pl.recorded_at DESC
      LIMIT 1;
    END IF;
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_latest_professional_location(uuid, uuid)
  TO authenticated;

-- Enable realtime so consumer map updates as soon as staff inserts a location.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'professional_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.professional_locations;
  END IF;
END $$;
