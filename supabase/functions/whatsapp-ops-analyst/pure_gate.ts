import { PERSISTENCE_MS } from './constants.ts';

/** للاختبارات البحتة بدون DB. */
export function evaluatePersistencePure(args: {
  immediate: boolean;
  firstSeenAtMs: number | null;
  nowMs: number;
  persistenceMs?: number;
}): 'open_now' | 'create_candidate' | 'still_waiting' | 'promote' {
  const x = args.persistenceMs ?? PERSISTENCE_MS;
  if (args.immediate) return 'open_now';
  if (args.firstSeenAtMs == null) return 'create_candidate';
  if (args.nowMs - args.firstSeenAtMs >= x) return 'promote';
  return 'still_waiting';
}
