const DEFAULT_EVO_BASE = 'http://72.61.191.237:8080';

export function evolutionInstanceNameForUser(userId: string): string {
  return `shop_${userId.replace(/-/g, '_')}`;
}

export async function evolutionFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const evoKey = Deno.env.get('EVOLUTION_API_KEY');
  const evoBase = Deno.env.get('EVOLUTION_BASE_URL') ?? DEFAULT_EVO_BASE;
  if (!evoKey) {
    throw new Error('EVOLUTION_API_KEY missing');
  }
  return fetch(`${evoBase}${path}`, {
    ...init,
    headers: {
      apikey: evoKey,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });
}

export function mapEvolutionState(raw: unknown): {
  connected: boolean;
  status: 'connecting' | 'connected' | 'disconnected';
  phone: string | null;
} {
  const obj = (raw ?? {}) as Record<string, unknown>;
  const inst = (obj.instance ?? obj) as Record<string, unknown>;
  const state = String(inst.state ?? obj.state ?? 'close').toLowerCase();
  const phoneRaw = inst.owner ?? obj.owner ?? inst.wuid ?? null;
  const phone = phoneRaw == null ? null : String(phoneRaw);
  if (state === 'open') {
    return { connected: true, status: 'connected', phone };
  }
  if (state === 'connecting') {
    return { connected: false, status: 'connecting', phone };
  }
  return { connected: false, status: 'disconnected', phone };
}
