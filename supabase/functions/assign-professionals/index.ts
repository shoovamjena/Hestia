// Assign professionals ~45 minutes before scheduled start.
// Invoke every 2–5 minutes via Supabase Scheduled Functions or pg_cron.
//
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Optional: FCM_SERVER_KEY (legacy) or FIREBASE_SERVICE_ACCOUNT_JSON for push

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type BookingRow = {
  id: string;
  user_id: string | null;
  hub_id: string | null;
  service_type: string | null;
  scheduled_date: string | null;
  scheduled_time: string | null;
  duration_hours: number | null;
  notes: string | null;
  status: string;
  professional_id: string | null;
};

/** Pad to 2 digits. */
function pad2(n: number): string {
  return n.toString().padStart(2, "0");
}

/**
 * Parse booking schedule as India local wall-clock (IST, UTC+05:30).
 * Edge runtimes are UTC — bare `new Date('YYYY-MM-DDTHH:MM')` would treat
 * the time as UTC and shift the calendar day for staff/consumer apps in IST.
 */
function parseScheduledStart(
  dateStr: string | null,
  timeStr: string | null,
): Date | null {
  if (!dateStr) return null;
  const day = dateStr.slice(0, 10);
  const raw = (timeStr ?? "").trim();
  if (!raw) {
    const d = new Date(`${day}T00:00:00+05:30`);
    return Number.isNaN(d.getTime()) ? null : d;
  }

  const upper = raw.toUpperCase();
  const hasAmPm = upper.includes("AM") || upper.includes("PM");

  let hour = 0;
  let minute = 0;

  if (!hasAmPm) {
    const parts = raw.split(":");
    if (parts.length < 2) return null;
    hour = parseInt(parts[0], 10);
    minute = parseInt(parts[1], 10);
  } else {
    const parts = upper.replace(/\s+/g, " ").split(":");
    if (parts.length < 2) return null;
    hour = parseInt(parts[0], 10);
    minute = parseInt(parts[1].split(" ")[0], 10);
    const isPm = upper.includes("PM");
    const isAm = upper.includes("AM");
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour === 12) hour = 0;
  }

  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;

  const d = new Date(`${day}T${pad2(hour)}:${pad2(minute)}:00+05:30`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function parseNotes(notes: string | null): Record<string, unknown> {
  if (!notes) return {};
  try {
    return JSON.parse(notes) as Record<string, unknown>;
  } catch {
    return {};
  }
}

/** Format for user-facing copy in IST. */
function formatTimeLabel(d: Date): string {
  const ist = new Date(d.getTime() + (5 * 60 + 30) * 60 * 1000);
  let h = ist.getUTCHours();
  const m = ist.getUTCMinutes();
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12;
  if (h === 0) h = 12;
  const mm = m.toString().padStart(2, "0");
  return `${h}:${mm} ${ampm}`;
}

/** Server coverage radius (must match public.coverage_radius_km()). */
const COVERAGE_RADIUS_KM = 7;

/**
 * Parse a DB coordinate. Critical: Number(null) === 0 in JS, which made
 * missing longitude look like "on the prime meridian" (~9000km errors).
 */
function parseCoord(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

function hasValidLatLng(lat: number | null, lng: number | null): boolean {
  if (lat === null || lng === null) return false;
  // Reject null-island / unset placeholders
  if (lat === 0 && lng === 0) return false;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return false;
  return true;
}

function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
}

type CoverageResolve = {
  hub_id: string | null;
  distance_km: number | null;
  zone_verified: boolean;
  reason?: string;
};

async function resolveCoverage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  lat: number,
  lng: number,
): Promise<CoverageResolve> {
  const { data, error } = await supabase.rpc("resolve_hub_coverage", {
    p_lat: lat,
    p_lng: lng,
  });
  if (!error && data) {
    return {
      hub_id: (data.hub_id as string | null) ?? null,
      distance_km: data.distance_km == null
        ? null
        : Number(data.distance_km),
      zone_verified: Boolean(data.zone_verified),
      reason: data.error as string | undefined,
    };
  }

  // Fallback if RPC not deployed yet
  const { data: hubs } = await supabase
    .from("hubs")
    .select("id, latitude, longitude");
  let best: { id: string; km: number } | null = null;
  for (const h of hubs ?? []) {
    const hLat = parseCoord(h.latitude);
    const hLng = parseCoord(h.longitude);
    if (!hasValidLatLng(hLat, hLng)) continue;
    const km = haversineKm(lat, lng, hLat!, hLng!);
    if (!best || km < best.km) best = { id: h.id as string, km };
  }
  if (!best) {
    return {
      hub_id: null,
      distance_km: null,
      zone_verified: false,
      reason: "no_hubs_with_coordinates",
    };
  }
  return {
    hub_id: best.id,
    distance_km: best.km,
    zone_verified: best.km <= COVERAGE_RADIUS_KM,
  };
}

/** Distance to a specific hub; null coords → null distance. */
async function distanceToHubKm(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  hubId: string,
  lat: number,
  lng: number,
): Promise<{ distance_km: number | null; has_coords: boolean }> {
  const { data: hub } = await supabase
    .from("hubs")
    .select("id, latitude, longitude")
    .eq("id", hubId)
    .maybeSingle();
  if (!hub) return { distance_km: null, has_coords: false };
  const hLat = parseCoord(hub.latitude);
  const hLng = parseCoord(hub.longitude);
  if (!hasValidLatLng(hLat, hLng)) {
    return { distance_km: null, has_coords: false };
  }
  return {
    distance_km: haversineKm(lat, lng, hLat!, hLng!),
    has_coords: true,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    let body: { booking_id?: string; force?: boolean } = {};
    try {
      body = await req.json();
    } catch {
      // empty body is fine for cron
    }
    const forceBookingId = body.booking_id?.trim() || null;
    const force = Boolean(body.force) && Boolean(forceBookingId);

    const now = new Date();
    const windowEnd = new Date(now.getTime() + 50 * 60 * 1000);

    // Pull confirmed, unassigned bookings; filter in JS because scheduled_time
    // may be text like "2:45 PM". Debug force skips the T-45 time window.
    let query = supabase
      .from("bookings")
      .select(
        "id, user_id, hub_id, service_type, scheduled_date, scheduled_time, duration_hours, notes, status, professional_id",
      )
      .eq("status", "confirmed")
      .is("professional_id", null)
      .in("assignment_status", ["pending", "unassigned_failed"]);

    if (forceBookingId) {
      query = query.eq("id", forceBookingId);
    }

    const { data: candidates, error: fetchErr } = await query;
    if (fetchErr) throw fetchErr;

    const due = ((candidates ?? []) as BookingRow[]).filter((b) => {
      const start = parseScheduledStart(b.scheduled_date, b.scheduled_time);
      if (!start) return false;
      if (force && b.id === forceBookingId) {
        // Debug: assign now even if outside the T-45 window
        return true;
      }
      // Within 50 minutes before start, and not yet started
      return start.getTime() > now.getTime() &&
        start.getTime() <= windowEnd.getTime();
    });

    if (force && due.length === 0) {
      return new Response(
        JSON.stringify({
          ok: false,
          error:
            "No matching unassigned booking found for debug force (need status=confirmed, professional_id=null, assignment_status pending|unassigned_failed)",
          booking_id: forceBookingId,
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const results: Array<Record<string, unknown>> = [];

    for (const booking of due) {
      const start = parseScheduledStart(
        booking.scheduled_date,
        booking.scheduled_time,
      )!;
      const notes = parseNotes(booking.notes);
      const userId = (booking.user_id ?? notes["user_id"]) as string | undefined;
      const preferSame = Boolean(notes["prefer_same_professional"]);
      const durationHours = Number(booking.duration_hours ?? 2) || 2;
      const end = new Date(
        start.getTime() + Math.round(durationHours * 60) * 60 * 1000,
      );

      // Resolve hub + enforce 7 km coverage against the booking/address hub.
      // Do NOT replace a local hub with a distant "nearest hub that has GPS"
      // (that caused Brahmapur bookings to fail against Bangalore hubs).
      let hubId = booking.hub_id;
      let coverageOk = false;
      let coverageError = `outside_${COVERAGE_RADIUS_KM}km_hub_coverage`;
      let coverageDistanceKm: number | null = null;
      const notesAddressId = notes["address_id"] as string | undefined;

      let addrQuery = supabase
        .from("addresses")
        .select("id, hub_id, latitude, longitude, zone_verified");
      if (notesAddressId) {
        addrQuery = addrQuery.eq("id", notesAddressId);
      } else if (userId) {
        addrQuery = addrQuery.eq("user_id", userId).eq("is_primary", true);
      } else {
        addrQuery = addrQuery.limit(0);
      }

      const { data: addr } = await addrQuery.limit(1).maybeSingle();
      if (addr) {
        hubId = hubId ?? (addr.hub_id as string | null);
        const lat = parseCoord(addr.latitude);
        const lng = parseCoord(addr.longitude);
        const hasCoords = hasValidLatLng(lat, lng);

        if (hasCoords && hubId) {
          const toHub = await distanceToHubKm(supabase, hubId, lat!, lng!);
          if (toHub.has_coords && toHub.distance_km != null) {
            coverageDistanceKm = toHub.distance_km;
            coverageOk = toHub.distance_km <= COVERAGE_RADIUS_KM;
            if (!coverageOk) {
              coverageError =
                `outside_${COVERAGE_RADIUS_KM}km_hub_coverage` +
                ` (distance_km=${toHub.distance_km.toFixed(2)})`;
            }
          } else {
            // Assigned hub has no GPS yet — trust stored zone flag
            coverageOk = Boolean(addr.zone_verified);
            if (!coverageOk) {
              coverageError =
                "hub_missing_coordinates_and_zone_unverified";
            }
          }
        } else if (hasCoords) {
          const coverage = await resolveCoverage(supabase, lat!, lng!);
          coverageOk = coverage.zone_verified;
          coverageDistanceKm = coverage.distance_km;
          if (coverage.hub_id) hubId = coverage.hub_id;
          if (!coverageOk) {
            coverageError = coverage.reason
              ? `${coverage.reason}`
              : `outside_${COVERAGE_RADIUS_KM}km_hub_coverage` +
                (coverage.distance_km != null
                  ? ` (nearest_km=${coverage.distance_km.toFixed(2)})`
                  : "");
          }
        } else {
          // Missing/partial coords (e.g. longitude null → used to become 0)
          coverageOk = Boolean(addr.zone_verified);
          if (!coverageOk) {
            coverageError =
              lat !== null && lng === null
                ? "address_missing_longitude"
                : lat === null && lng !== null
                ? "address_missing_latitude"
                : "address_missing_coordinates_and_zone_unverified";
          }
        }
      } else if (hubId) {
        // No address row — allow hub-scoped matching (legacy bookings)
        coverageOk = true;
      }

      if (!coverageOk) {
        await supabase
          .from("bookings")
          .update({ assignment_status: "unassigned_failed" })
          .eq("id", booking.id);
        results.push({
          booking_id: booking.id,
          assigned: false,
          error: coverageError,
          distance_km: coverageDistanceKm,
          hub_id: hubId,
        });
        continue;
      }

      // Candidate professionals — prefer hub, then global fallback.
      // NOTE: professionals table uses employment_status / duty_status (not is_active).
      const proSelect =
        "id, full_name, hub_id, avg_rating, total_sessions, background_check_status, employment_status, duty_status";

      let hubProCount = 0;
      let proFetchError: string | null = null;

      let proQuery = supabase.from("professionals").select(proSelect);
      if (hubId) {
        proQuery = proQuery.eq("hub_id", hubId);
      }
      let { data: pros, error: hubProErr } = await proQuery;
      if (hubProErr) {
        proFetchError = hubProErr.message;
        pros = [];
      }
      hubProCount = pros?.length ?? 0;

      if (!pros?.length) {
        const global = await supabase.from("professionals").select(proSelect);
        if (global.error) {
          proFetchError = global.error.message;
        }
        pros = global.data ?? [];
      }

      // Employed + assignable duty. Force/debug also allows off_duty for testing.
      let pool = (pros ?? []).filter((p) => {
        const employment =
          (p.employment_status as string | null)?.toLowerCase() ?? "active";
        if (employment === "inactive" || employment === "terminated") {
          return false;
        }
        const duty = (p.duty_status as string | null)?.toLowerCase() ?? "";
        if (force) return true; // debug: any employed pro
        if (duty === "off_duty") return false;
        // active, standby, empty/unknown → ok
        return true;
      });
      const activeCount = pool.length;

      // Prefer on-duty / standby before anyone else
      const dutyRank = (p: Record<string, unknown>) => {
        const duty = (p.duty_status as string | null)?.toLowerCase() ?? "";
        if (duty === "active") return 0;
        if (duty === "standby") return 1;
        if (duty === "off_duty") return 3;
        return 2;
      };

      // Exclude pros with overlapping bookings
      const proIds = pool.map((p) => p.id as string);
      if (proIds.length) {
        const { data: overlaps } = await supabase
          .from("bookings")
          .select(
            "professional_id, scheduled_date, scheduled_time, duration_hours, status",
          )
          .in("professional_id", proIds)
          .in("status", ["pending", "confirmed", "active", "in_progress"]);

        const busy = new Set<string>();
        for (const o of overlaps ?? []) {
          const oStart = parseScheduledStart(
            o.scheduled_date as string,
            o.scheduled_time as string,
          );
          if (!oStart) continue;
          const oDur = Number(o.duration_hours ?? 2) || 2;
          const oEnd = new Date(
            oStart.getTime() + Math.round(oDur * 60) * 60 * 1000,
          );
          if (oStart < end && oEnd > start) {
            busy.add(o.professional_id as string);
          }
        }
        pool = pool.filter((p) => !busy.has(p.id as string));
      }
      const availableCount = pool.length;

      // Soft rank: duty → rating → sessions
      pool.sort((a, b) => {
        const d = dutyRank(a) - dutyRank(b);
        if (d !== 0) return d;
        const ra = Number(a.avg_rating ?? 0);
        const rb = Number(b.avg_rating ?? 0);
        if (rb !== ra) return rb - ra;
        return Number(b.total_sessions ?? 0) - Number(a.total_sessions ?? 0);
      });

      // Prefer previously used professional if requested
      if (preferSame && userId && pool.length) {
        const { data: past } = await supabase
          .from("bookings")
          .select("professional_id")
          .eq("user_id", userId)
          .not("professional_id", "is", null)
          .order("created_at", { ascending: false })
          .limit(5);
        const preferredIds = new Set(
          (past ?? []).map((p) => p.professional_id as string),
        );
        pool.sort((a, b) => {
          const ap = preferredIds.has(a.id as string) ? 1 : 0;
          const bp = preferredIds.has(b.id as string) ? 1 : 0;
          return bp - ap;
        });
      }

      const chosen = pool[0];
      if (!chosen) {
        await supabase
          .from("bookings")
          .update({ assignment_status: "unassigned_failed" })
          .eq("id", booking.id);

        const noProError = proFetchError
          ? `professionals_query_failed: ${proFetchError}`
          : activeCount === 0
          ? (hubProCount === 0
            ? `no_professionals_in_hub_or_globally (hub_id=${hubId ?? "null"})`
            : `no_active_professionals (hub_pros=${hubProCount})`)
          : `all_professionals_busy (available=0, active=${activeCount}, hub_pros=${hubProCount})`;

        // Still finding notice when within 20 minutes of start
        if (userId && start.getTime() - now.getTime() <= 20 * 60 * 1000) {
          const { data: notif } = await supabase
            .from("user_notifications")
            .insert({
              user_id: userId,
              notification_type: "assignment_pending",
              title: "Still finding a professional",
              body:
                `We're still matching a caregiver for your ${
                  formatTimeLabel(start)
                } booking.`,
              booking_id: booking.id,
              metadata: { booking_id: booking.id },
            })
            .select("id, user_id, title, body, booking_id")
            .maybeSingle();
          if (notif) {
            await fetch(
              `${supabaseUrl}/functions/v1/send-push-notification`,
              {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                  Authorization: `Bearer ${serviceKey}`,
                },
                body: JSON.stringify({
                  user_id: userId,
                  title: notif.title,
                  body: notif.body,
                  data: {
                    type: "assignment_pending",
                    booking_id: booking.id,
                    notification_id: notif.id,
                  },
                }),
              },
            );
          }
        }

        results.push({
          booking_id: booking.id,
          assigned: false,
          error: noProError,
          hub_id: hubId,
          hub_pro_count: hubProCount,
          active_count: activeCount,
          available_count: availableCount,
        });
        continue;
      }

      const professionalId = chosen.id as string;
      const professionalName =
        (chosen.full_name as string) || "Your professional";

      // caregivers FK safety
      await supabase.from("caregivers").upsert({
        id: professionalId,
        full_name: professionalName,
      });

      const { error: updErr } = await supabase
        .from("bookings")
        .update({
          professional_id: professionalId,
          assignment_status: "assigned",
          assigned_at: new Date().toISOString(),
        })
        .eq("id", booking.id)
        .is("professional_id", null);

      if (updErr) {
        results.push({
          booking_id: booking.id,
          assigned: false,
          error: updErr.message,
        });
        continue;
      }

      // Create session for tracking at assignment time (staff app lists sessions).
      // If a session already exists for this booking, reuse/update it.
      let sessionId: string | null = null;
      const { data: existingSession } = await supabase
        .from("sessions")
        .select("id")
        .eq("booking_id", booking.id)
        .maybeSingle();

      if (existingSession?.id) {
        sessionId = existingSession.id as string;
        await supabase
          .from("sessions")
          .update({
            professional_id: professionalId,
            hub_id: hubId,
            status: "scheduled",
            start_time: start.toISOString(),
            end_time: end.toISOString(),
          })
          .eq("id", sessionId);
      } else {
        const { data: session, error: sessionErr } = await supabase
          .from("sessions")
          .insert({
            booking_id: booking.id,
            professional_id: professionalId,
            hub_id: hubId,
            status: "scheduled",
            start_time: start.toISOString(),
            end_time: end.toISOString(),
          })
          .select("id")
          .maybeSingle();
        if (sessionErr) {
          console.error("session insert failed", booking.id, sessionErr.message);
        }
        sessionId = session?.id ?? null;
      }

      const totalAmount = Number(notes["total_amount"] ?? 0);
      const paymentId = notes["payment_id"] as string | undefined;
      if (sessionId && userId) {
        await supabase.from("invoices").insert({
          session_id: sessionId,
          user_id: userId,
          amount: totalAmount,
          status: "pending",
          payment_method: paymentId ? "online" : "unpaid",
        });
      }

      let notificationId: string | null = null;
      if (userId) {
        const { data: notif } = await supabase
          .from("user_notifications")
          .insert({
            user_id: userId,
            notification_type: "professional_assigned",
            title: "Professional assigned",
            body:
              `${professionalName} will arrive for your booking at ${
                formatTimeLabel(start)
              }.`,
            booking_id: booking.id,
            session_id: sessionId,
            metadata: {
              booking_id: booking.id,
              professional_id: professionalId,
              professional_name: professionalName,
            },
          })
          .select("id")
          .maybeSingle();
        notificationId = notif?.id ?? null;

        await fetch(`${supabaseUrl}/functions/v1/send-push-notification`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${serviceKey}`,
          },
          body: JSON.stringify({
            user_id: userId,
            title: "Professional assigned",
            body:
              `${professionalName} will arrive for your booking at ${
                formatTimeLabel(start)
              }.`,
            data: {
              type: "professional_assigned",
              booking_id: booking.id,
              notification_id: notificationId,
            },
          }),
        });
      }

      // Best-effort push to the professional (same device_tokens.user_id = auth uid).
      if (professionalId && sessionId) {
        await fetch(`${supabaseUrl}/functions/v1/send-push-notification`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${serviceKey}`,
          },
          body: JSON.stringify({
            user_id: professionalId,
            title: "New session assigned",
            body:
              `You have a care session at ${formatTimeLabel(start)}. Open the app to view details.`,
            data: {
              type: "session_assigned",
              booking_id: booking.id,
              session_id: sessionId,
            },
          }),
        });
      }

      results.push({
        booking_id: booking.id,
        assigned: true,
        professional_id: professionalId,
        professional_name: professionalName,
      });
    }

    return new Response(
      JSON.stringify({
        ok: true,
        checked: due.length,
        force,
        booking_id: forceBookingId,
        results,
        at: now.toISOString(),
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
