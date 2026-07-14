import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  evolutionFetch,
  evolutionInstanceNameForUser,
  mapEvolutionState,
} from './evolution.ts';

type GatewayAction = 'provision' | 'qr' | 'status' | 'report_disconnected';

type RequestBody = {
  action?: GatewayAction;
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userErr || !user) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json({ ok: false, error: 'invalid_json' }, { status: 400 });
  }

  const action = body.action;
  if (!action) {
    return Response.json({ ok: false, error: 'missing_action' }, { status: 400 });
  }

  const instanceName = evolutionInstanceNameForUser(user.id);
  const now = new Date().toISOString();

  if (action === 'provision') {
    try {
      await evolutionFetch('/instance/create', {
        method: 'POST',
        body: JSON.stringify({
          instanceName,
          integration: 'WHATSAPP-BAILEYS',
          qrcode: false,
        }),
      });
    } catch (e) {
      console.warn('provision create skipped', e);
    }

    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      {
        user_id: user.id,
        evolution_instance_name: instanceName,
        status: 'connecting',
        updated_at: now,
      },
      { onConflict: 'user_id' },
    );
    if (error) {
      console.error('provision upsert failed', error);
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }

    return Response.json({ ok: true, instance_name: instanceName });
  }

  if (action === 'qr') {
    const res = await evolutionFetch(`/instance/connect/${instanceName}`);
    let data: Record<string, unknown> = {};
    try {
      data = await res.json();
    } catch {
      data = {};
    }

    await supabase.from('tenant_whatsapp_gateways').upsert(
      {
        user_id: user.id,
        evolution_instance_name: instanceName,
        status: 'connecting',
        updated_at: now,
      },
      { onConflict: 'user_id' },
    );

    return Response.json({
      ok: res.ok,
      base64: data.base64 ?? null,
      pairing_code: data.pairingCode ?? data.code ?? null,
    });
  }

  if (action === 'status') {
    const res = await evolutionFetch(`/instance/connectionState/${instanceName}`);
    let data: unknown = {};
    try {
      data = await res.json();
    } catch {
      data = {};
    }

    const mapped = mapEvolutionState(data);
    const patch: Record<string, unknown> = {
      user_id: user.id,
      evolution_instance_name: instanceName,
      status: mapped.status,
      whatsapp_phone: mapped.phone,
      updated_at: now,
    };
    if (mapped.connected) {
      patch.last_connected_at = now;
    } else if (mapped.status === 'disconnected') {
      patch.last_disconnected_at = now;
    }

    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      patch,
      { onConflict: 'user_id' },
    );
    if (error) {
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }

    return Response.json({
      ok: true,
      status: mapped.status,
      connected: mapped.connected,
      phone: mapped.phone,
      instance_name: instanceName,
    });
  }

  if (action === 'report_disconnected') {
    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      {
        user_id: user.id,
        evolution_instance_name: instanceName,
        status: 'disconnected',
        last_disconnected_at: now,
        updated_at: now,
      },
      { onConflict: 'user_id' },
    );
    if (error) {
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }
    return Response.json({ ok: true, status: 'disconnected' });
  }

  return Response.json({ ok: false, error: 'unknown_action' }, { status: 400 });
});
