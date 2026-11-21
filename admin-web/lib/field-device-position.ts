/** قراءة موقع الجهاز بموثوقية أعلى على أندرويد */

export type DevicePosition = {
  lat: number;
  lng: number;
  accuracy: number | null;
};

export type DevicePositionError =
  | "unsupported"
  | "denied"
  | "timeout"
  | "unavailable";

function oncePosition(
  options: PositionOptions,
): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(Object.assign(new Error("unsupported"), { code: 0 }));
      return;
    }
    navigator.geolocation.getCurrentPosition(resolve, reject, options);
  });
}

function watchBestPosition(
  maxMs: number,
  options: PositionOptions,
): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(Object.assign(new Error("unsupported"), { code: 0 }));
      return;
    }
    let best: GeolocationPosition | null = null;
    const watchId = navigator.geolocation.watchPosition(
      (pos) => {
        if (
          !best ||
          (pos.coords.accuracy || 9999) < (best.coords.accuracy || 9999)
        ) {
          best = pos;
        }
        // دقة مقبولة → اكتفِ
        if (pos.coords.accuracy > 0 && pos.coords.accuracy <= 40) {
          navigator.geolocation.clearWatch(watchId);
          clearTimeout(timer);
          resolve(pos);
        }
      },
      (err) => {
        navigator.geolocation.clearWatch(watchId);
        clearTimeout(timer);
        if (best) resolve(best);
        else reject(err);
      },
      options,
    );
    const timer = setTimeout(() => {
      navigator.geolocation.clearWatch(watchId);
      if (best) resolve(best);
      else {
        reject(Object.assign(new Error("timeout"), { code: 3 }));
      }
    }, maxMs);
  });
}

export async function readDevicePosition(): Promise<
  | { ok: true; position: DevicePosition }
  | { ok: false; error: DevicePositionError }
> {
  if (typeof navigator === "undefined" || !navigator.geolocation) {
    return { ok: false, error: "unsupported" };
  }

  const mapErr = (err: unknown): DevicePositionError => {
    const code =
      err && typeof err === "object" && "code" in err
        ? Number((err as { code: number }).code)
        : -1;
    if (code === 1) return "denied";
    if (code === 3) return "timeout";
    if (code === 0) return "unsupported";
    return "unavailable";
  };

  const toPos = (p: GeolocationPosition): DevicePosition => ({
    lat: p.coords.latitude,
    lng: p.coords.longitude,
    accuracy:
      typeof p.coords.accuracy === "number" ? p.coords.accuracy : null,
  });

  // 1) محاولة دقيقة
  try {
    const p = await oncePosition({
      enableHighAccuracy: true,
      timeout: 15000,
      maximumAge: 0,
    });
    return { ok: true, position: toPos(p) };
  } catch (e1) {
    if (mapErr(e1) === "denied") return { ok: false, error: "denied" };
  }

  // 2) محاولة أسرع بدون high accuracy
  try {
    const p = await oncePosition({
      enableHighAccuracy: false,
      timeout: 12000,
      maximumAge: 30_000,
    });
    return { ok: true, position: toPos(p) };
  } catch (e2) {
    if (mapErr(e2) === "denied") return { ok: false, error: "denied" };
  }

  // 3) watch لبضع ثوانٍ (أنسب لبعض أجهزة أندرويد)
  try {
    const p = await watchBestPosition(10000, {
      enableHighAccuracy: true,
      maximumAge: 0,
      timeout: 10000,
    });
    return { ok: true, position: toPos(p) };
  } catch (e3) {
    return { ok: false, error: mapErr(e3) };
  }
}
