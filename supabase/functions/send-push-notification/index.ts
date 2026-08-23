// Send FCM push to all device tokens for a user (FCM HTTP v1).
//
// Secrets:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   FIREBASE_SERVICE_ACCOUNT_JSON — full JSON from Firebase → Project settings
//     → Service accounts → Generate new private key
//
// Legacy FCM_SERVER_KEY is no longer used (Legacy API disabled in new projects).

import { create } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type PushBody = {
  user_id: string;
  title: string;
  body: string;
  data?: Record<string, string | null | undefined>;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

function pemToCryptoKey(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const key = await pemToCryptoKey(sa.private_key);
  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    key,
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OAuth token error: ${res.status} ${text}`);
  }

  const json = await res.json();
  return json.access_token as string;
}

async function sendFcmV1(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: "HIGH" },
        },
      }),
    },
  );
  return {
    status: res.status,
    ok: res.ok,
    body: await res.text(),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = (await req.json()) as PushBody;
    if (!payload.user_id || !payload.title) {
      return new Response(
        JSON.stringify({ ok: false, error: "user_id and title required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
    if (!saJson) {
      return new Response(
        JSON.stringify({
          ok: false,
          error:
            "FIREBASE_SERVICE_ACCOUNT_JSON not set. Generate a service account key in Firebase → Project settings → Service accounts.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const sa = JSON.parse(saJson) as ServiceAccount;
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const supabase = createClient(supabaseUrl, serviceKey);
    const { data: rows, error } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", payload.user_id);

    if (error) throw error;

    const tokens = (rows ?? [])
      .map((r) => r.token as string)
      .filter((t) => t && t.length > 10);

    if (!tokens.length) {
      return new Response(
        JSON.stringify({ ok: true, sent: 0, reason: "no_device_tokens" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const data: Record<string, string> = {};
    for (const [k, v] of Object.entries(payload.data ?? {})) {
      if (v != null) data[k] = String(v);
    }

    const accessToken = await getAccessToken(sa);
    const results = [];
    for (const token of tokens) {
      results.push(
        await sendFcmV1(
          accessToken,
          sa.project_id,
          token,
          payload.title,
          payload.body ?? "",
          data,
        ),
      );
    }

    return new Response(
      JSON.stringify({ ok: true, sent: tokens.length, results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
