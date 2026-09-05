import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type CreateOwnerPayload = {
  email?: string;
  password?: string;
  generate_password?: boolean;
  display_name?: string;
  camper_name?: string;
};

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function generatePassword(length = 18): string {
  const chars =
    "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*";
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (x) => chars[x % chars.length]).join("");
}

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error(
    "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.",
  );
}

const adminClient = createClient(supabaseUrl, serviceRoleKey);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length)
    : "";
  if (!jwt) return json({ error: "Missing bearer token" }, 401);

  let payload: CreateOwnerPayload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 422);
  }

  const email = String(payload.email || "").trim().toLowerCase();
  const displayName = String(payload.display_name || "").trim() || null;
  const camperName = String(payload.camper_name || "").trim() || null;
  const wantsGeneratedPassword = Boolean(payload.generate_password);
  const inputPassword = String(payload.password || "");
  const shouldGeneratePassword = wantsGeneratedPassword || !inputPassword;
  const password = shouldGeneratePassword ? generatePassword() : inputPassword;
  if (!email || !EMAIL_REGEX.test(email)) {
    return json({ error: "Invalid email address" }, 422);
  }
  if (password.length < 12) {
    return json({ error: "Password must be at least 12 characters" }, 422);
  }

  const idempotencyKey = (req.headers.get("x-idempotency-key") || "").trim() ||
    null;

  const { data: callerData, error: callerError } = await adminClient.auth
    .getUser(jwt);
  const caller = callerData?.user ?? null;
  if (callerError || !caller) {
    return json({ error: "Unauthorized" }, 401);
  }

  const { data: adminRow, error: adminCheckError } = await adminClient
    .from("platform_admins")
    .select("user_id")
    .eq("user_id", caller.id)
    .eq("active", true)
    .eq("role", "head_admin")
    .maybeSingle();
  if (adminCheckError || !adminRow) {
    return json({ error: "Forbidden: head admin role required" }, 403);
  }

  if (idempotencyKey) {
    const { data: previous } = await adminClient
      .from("owner_provision_audit")
      .select("result")
      .eq("created_by", caller.id)
      .eq("idempotency_key", idempotencyKey)
      .eq("status", "success")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (previous?.result) {
      return json(previous.result, 200);
    }
  }

  const { data: existingProfile, error: existingProfileError } = await adminClient
    .from("profiles")
    .select("user_id")
    .eq("email", email)
    .maybeSingle();
  if (existingProfileError) {
    return json({ error: `Profile lookup failed: ${existingProfileError.message}` }, 500);
  }
  if (existingProfile) {
    return json({ error: "Email already exists" }, 409);
  }

  await adminClient.from("owner_provision_audit").insert({
    created_by: caller.id,
    target_email: email,
    idempotency_key: idempotencyKey,
    status: "attempt",
    result: {
      email,
      display_name: displayName,
      camper_name: camperName,
    },
  });

  const { data: createdAuth, error: createAuthError } = await adminClient.auth.admin
    .createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: displayName ? { display_name: displayName } : undefined,
    });

  if (createAuthError || !createdAuth?.user) {
    const message = createAuthError?.message || "Unknown auth error";
    const status = /already|exists|registered|duplicate/i.test(message) ? 409 : 500;
    await adminClient.from("owner_provision_audit").insert({
      created_by: caller.id,
      target_email: email,
      idempotency_key: idempotencyKey,
      status: "failed",
      error_message: message,
    });
    return json({ error: message }, status);
  }

  const targetUserId = createdAuth.user.id;
  const { data: provisionRows, error: provisionError } = await adminClient.rpc(
    "provision_camper_owner_data",
    {
      p_user_id: targetUserId,
      p_email: email,
      p_display_name: displayName,
      p_camper_name: camperName,
    },
  );

  if (provisionError) {
    await adminClient.auth.admin.deleteUser(targetUserId);
    await adminClient.from("owner_provision_audit").insert({
      created_by: caller.id,
      target_user_id: targetUserId,
      target_email: email,
      idempotency_key: idempotencyKey,
      status: "failed",
      error_message: provisionError.message,
    });
    return json({ error: `Provisioning failed: ${provisionError.message}` }, 500);
  }

  const provisionResult = Array.isArray(provisionRows)
    ? provisionRows[0]
    : provisionRows;
  const responseBody = {
    status: "ok",
    user_id: targetUserId,
    profile_id: provisionResult?.profile_id ?? targetUserId,
    camper_id: provisionResult?.camper_id ?? null,
    generated_password: shouldGeneratePassword ? password : null,
  };

  await adminClient.from("owner_provision_audit").insert({
    created_by: caller.id,
    target_user_id: targetUserId,
    target_email: email,
    idempotency_key: idempotencyKey,
    status: "success",
    result: responseBody,
  });

  return json(responseBody, 200);
});
