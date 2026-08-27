import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function normalizeRoleLabel(role: string) {
  if (role === 'editor') return 'Editor';
  return 'Viewer';
}

function buildAcceptUrl(appUrl: string, invitationToken: string) {
  const url = new URL(appUrl);
  const basePath = url.pathname.replace(/\/[^/]*$/, '/');
  return `${url.origin}${basePath}join-camper/${encodeURIComponent(invitationToken)}`;
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (character) => {
    if (character === '&') return '&amp;';
    if (character === '<') return '&lt;';
    if (character === '>') return '&gt;';
    if (character === '"') return '&quot;';
    return '&#39;';
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed.' }, 405);
  }

  const resendApiKey = Deno.env.get('RESEND_API_KEY');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const authorization = request.headers.get('Authorization');

  if (!resendApiKey) {
    return jsonResponse({ error: 'Missing RESEND_API_KEY secret.' }, 500);
  }

  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: 'Missing Supabase environment configuration.' }, 500);
  }

  if (!authorization) {
    return jsonResponse({ error: 'Missing Authorization header.' }, 401);
  }

  let body: { invitationToken?: string; appUrl?: string; camperName?: string; inviterName?: string } | null = null;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }

  const invitationToken = body?.invitationToken?.trim();
  const appUrl = body?.appUrl?.trim();
  const camperNameFromBody = body?.camperName?.trim();
  const inviterName = body?.inviterName?.trim();

  if (!invitationToken) {
    return jsonResponse({ error: 'invitationToken is required.' }, 400);
  }

  if (!appUrl) {
    return jsonResponse({ error: 'appUrl is required.' }, 400);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  });

  const { data: authData, error: authError } = await supabase.auth.getUser();
  if (authError || !authData.user) {
    return jsonResponse({ error: 'Unauthorized.' }, 401);
  }

  const { data: invitation, error: invitationError } = await supabase
    .from('invitations')
    .select('id,email,role,status,expires_at,camper_id')
    .eq('invitation_token', invitationToken)
    .maybeSingle();

  if (invitationError) {
    return jsonResponse({ error: `Invitation lookup failed: ${invitationError.message}` }, 400);
  }

  if (!invitation) {
    return jsonResponse({ error: 'Invitation not found.' }, 404);
  }

  if (invitation.status !== 'pending') {
    return jsonResponse({ error: 'Invitation is no longer pending.' }, 409);
  }

  if (invitation.expires_at && new Date(invitation.expires_at).getTime() <= Date.now()) {
    return jsonResponse({ error: 'Invitation has expired.' }, 409);
  }

  const acceptUrl = buildAcceptUrl(appUrl, invitationToken);
  const camperName = camperNameFromBody || `camper #${invitation.camper_id}`;
  const safeCamperName = escapeHtml(camperName);
  const safeInviterName = inviterName ? escapeHtml(inviterName) : '';
  const roleLabel = normalizeRoleLabel(invitation.role || 'viewer');
  const safeRoleLabel = escapeHtml(roleLabel);
  const greetingName = escapeHtml(invitation.email);
  const safeAcceptUrl = escapeHtml(acceptUrl);
  const subject = `[TEST] Uitnodiging voor ${camperName}`;
  const inviterLine = safeInviterName
    ? `<p style="margin:0 0 16px;">${safeInviterName} heeft je uitgenodigd voor het camperlogboek van <strong>${safeCamperName}</strong>.</p>`
    : `<p style="margin:0 0 16px;">Je bent uitgenodigd voor het camperlogboek van <strong>${safeCamperName}</strong>.</p>`;

  const html = `
    <div style="font-family:Arial,sans-serif;line-height:1.6;color:#20252b;max-width:640px;margin:0 auto;">
      <p style="margin:0 0 16px;">Hallo ${greetingName},</p>
      ${inviterLine}
      <p style="margin:0 0 16px;">Je rol in deze TEST-uitnodiging is: <strong>${safeRoleLabel}</strong>.</p>
      <p style="margin:0 0 24px;">Klik op de knop hieronder om de uitnodiging te accepteren en toegang te krijgen tot Making Memories.</p>
      <p style="margin:0 0 24px;">
        <a href="${safeAcceptUrl}" style="display:inline-block;background:#20252b;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:700;">
          Uitnodiging accepteren
        </a>
      </p>
      <p style="margin:0 0 16px;">Werkt de knop niet? Gebruik dan deze link:</p>
      <p style="margin:0 0 24px;word-break:break-all;">
        <a href="${safeAcceptUrl}">${safeAcceptUrl}</a>
      </p>
      <p style="margin:0;color:#66717d;font-size:13px;">Deze TEST-uitnodiging is 7 dagen geldig en werkt alleen in de TEST-omgeving.</p>
    </div>
  `.trim();

  const resendResponse = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + resendApiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Making Memories TEST <onboarding@resend.dev>',
      to: [invitation.email],
      subject,
      html,
    }),
  });

  const resendResult = await resendResponse.json().catch(() => null);

  if (!resendResponse.ok) {
    return jsonResponse(
      {
        error: 'Resend email request failed.',
        details: resendResult,
      },
      502,
    );
  }

  return jsonResponse({
    success: true,
    emailId: resendResult?.id ?? null,
    acceptUrl,
  });
});
