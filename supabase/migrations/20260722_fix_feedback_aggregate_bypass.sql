-- Fix: session_feedback rating updates blocked by aggregate protect trigger
-- Cause: older update_professional_avg_rating() is SECURITY DEFINER but never
-- sets app.allow_professional_aggregate_write, so prevent_* raises P0001.
-- Run in Supabase SQL Editor.

-- 1. Remove legacy rating triggers/functions
DROP TRIGGER IF EXISTS on_session_feedback_change ON public.session_feedback;
DROP TRIGGER IF EXISTS trg_session_feedback_rating_agg ON public.session_feedback;
DROP FUNCTION IF EXISTS public.update_professional_avg_rating();

-- 2. Bypass helper
CREATE OR REPLACE FUNCTION public._set_aggregate_write_bypass(enabled boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'app.allow_professional_aggregate_write',
    CASE WHEN enabled THEN '1' ELSE '0' END,
    true
  );
END;
$$;

-- 3. Protect trigger: allow nested trigger writes + explicit bypass
CREATE OR REPLACE FUNCTION public.prevent_client_professional_aggregate_writes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Nested trigger updates (from session_feedback / sessions aggregates)
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  IF coalesce(current_setting('app.allow_professional_aggregate_write', true), '0') = '1' THEN
    RETURN NEW;
  END IF;

  IF NEW.avg_rating IS DISTINCT FROM OLD.avg_rating
     OR NEW.total_sessions IS DISTINCT FROM OLD.total_sessions
     OR NEW.rating_count IS DISTINCT FROM OLD.rating_count
     OR NEW.rating_sum IS DISTINCT FROM OLD.rating_sum THEN
    RAISE EXCEPTION
      'Clients cannot update professionals aggregate columns (avg_rating, total_sessions, rating_count, rating_sum)';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_client_professional_aggregate_writes ON public.professionals;
CREATE TRIGGER trg_prevent_client_professional_aggregate_writes
BEFORE UPDATE ON public.professionals
FOR EACH ROW
EXECUTE FUNCTION public.prevent_client_professional_aggregate_writes();

-- 4. Ensure aggregate columns exist
ALTER TABLE public.professionals
  ADD COLUMN IF NOT EXISTS rating_count integer NOT NULL DEFAULT 0;
ALTER TABLE public.professionals
  ADD COLUMN IF NOT EXISTS rating_sum numeric NOT NULL DEFAULT 0;

-- 5. Rating delta trigger (owns aggregate writes)
CREATE OR REPLACE FUNCTION public.apply_session_feedback_rating_delta()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_professional_id uuid;
  v_old_professional_id uuid;
  v_old_rating numeric := 0;
  v_new_rating numeric := 0;
  v_delta_sum numeric := 0;
  v_delta_count integer := 0;
BEGIN
  PERFORM public._set_aggregate_write_bypass(true);

  IF TG_OP = 'DELETE' THEN
    SELECT s.professional_id INTO v_professional_id
    FROM public.sessions s
    WHERE s.id = OLD.session_id;

    v_old_rating := COALESCE(OLD.rating, 0);
    v_delta_sum := -v_old_rating;
    v_delta_count := -1;
  ELSIF TG_OP = 'UPDATE' THEN
    SELECT s.professional_id INTO v_professional_id
    FROM public.sessions s
    WHERE s.id = NEW.session_id;

    v_old_rating := COALESCE(OLD.rating, 0);
    v_new_rating := COALESCE(NEW.rating, 0);

    IF OLD.session_id IS DISTINCT FROM NEW.session_id THEN
      SELECT s.professional_id INTO v_old_professional_id
      FROM public.sessions s
      WHERE s.id = OLD.session_id;

      IF v_old_professional_id IS NOT NULL THEN
        UPDATE public.professionals
        SET
          rating_sum = GREATEST(0, COALESCE(rating_sum, 0) - v_old_rating),
          rating_count = GREATEST(0, COALESCE(rating_count, 0) - 1)
        WHERE id = v_old_professional_id;

        UPDATE public.professionals
        SET avg_rating = CASE
          WHEN rating_count > 0 THEN ROUND(rating_sum / rating_count, 2)
          ELSE 0
        END
        WHERE id = v_old_professional_id;
      END IF;

      v_delta_sum := v_new_rating;
      v_delta_count := 1;
    ELSE
      v_delta_sum := v_new_rating - v_old_rating;
      v_delta_count := 0;
    END IF;
  ELSE
    SELECT s.professional_id INTO v_professional_id
    FROM public.sessions s
    WHERE s.id = NEW.session_id;

    v_new_rating := COALESCE(NEW.rating, 0);
    v_delta_sum := v_new_rating;
    v_delta_count := 1;
  END IF;

  IF v_professional_id IS NOT NULL AND (v_delta_sum <> 0 OR v_delta_count <> 0) THEN
    UPDATE public.professionals
    SET
      rating_sum = GREATEST(0, COALESCE(rating_sum, 0) + v_delta_sum),
      rating_count = GREATEST(0, COALESCE(rating_count, 0) + v_delta_count)
    WHERE id = v_professional_id;

    UPDATE public.professionals
    SET avg_rating = CASE
      WHEN rating_count > 0 THEN ROUND(rating_sum / rating_count, 2)
      ELSE 0
    END
    WHERE id = v_professional_id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_session_feedback_rating_agg
AFTER INSERT OR UPDATE OR DELETE ON public.session_feedback
FOR EACH ROW
EXECUTE FUNCTION public.apply_session_feedback_rating_delta();
