"use client";

import { useEffect, useRef, useState } from "react";

type SpeechRec = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  maxAlternatives: number;
  start: () => void;
  stop: () => void;
  abort: () => void;
  onresult: ((ev: SpeechRecognitionEventLike) => void) | null;
  onerror: ((ev: { error: string }) => void) | null;
  onend: (() => void) | null;
};

type SpeechRecognitionEventLike = {
  resultIndex: number;
  results: {
    length: number;
    [i: number]: {
      isFinal: boolean;
      [j: number]: { transcript: string; confidence: number };
    };
  };
};

function getSpeechRecognitionCtor(): (new () => SpeechRec) | null {
  if (typeof window === "undefined") return null;
  const w = window as unknown as {
    SpeechRecognition?: new () => SpeechRec;
    webkitSpeechRecognition?: new () => SpeechRec;
  };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

/** طلب إذن الميكروفون صراحةً (يفتح حوار النظام) */
async function requestMicPermission(): Promise<
  "granted" | "denied" | "unsupported"
> {
  if (typeof navigator === "undefined") return "unsupported";
  if (!window.isSecureContext) return "denied";

  if (!navigator.mediaDevices?.getUserMedia) {
    // بعض المتصفحات تعتمد SpeechRecognition وحده
    return "granted";
  }

  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video: false,
    });
    for (const track of stream.getTracks()) track.stop();
    return "granted";
  } catch (err) {
    const name =
      err && typeof err === "object" && "name" in err
        ? String((err as { name: string }).name)
        : "";
    if (
      name === "NotAllowedError" ||
      name === "PermissionDeniedError" ||
      name === "SecurityError"
    ) {
      return "denied";
    }
    if (name === "NotFoundError" || name === "DevicesNotFoundError") {
      return "unsupported";
    }
    return "denied";
  }
}

const LANG_CANDIDATES = ["ar-IQ", "ar-SA", "ar-AE", "ar"] as const;

type Props = {
  value: string;
  onChange: (next: string) => void;
  placeholder?: string;
};

export function VoiceNotesField({ value, onChange, placeholder }: Props) {
  const [listening, setListening] = useState(false);
  const [starting, setStarting] = useState(false);
  const [interim, setInterim] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [supported, setSupported] = useState(true);
  const recRef = useRef<SpeechRec | null>(null);
  const baseRef = useRef(value);
  const wantListenRef = useRef(false);

  useEffect(() => {
    baseRef.current = value;
  }, [value]);

  useEffect(() => {
    setSupported(!!getSpeechRecognitionCtor());
    return () => {
      wantListenRef.current = false;
      try {
        recRef.current?.abort();
      } catch {
        /* ignore */
      }
    };
  }, []);

  const stop = () => {
    wantListenRef.current = false;
    setStarting(false);
    try {
      recRef.current?.stop();
    } catch {
      /* ignore */
    }
    setListening(false);
    setInterim("");
    setStatus(null);
  };

  const beginRecognition = (Ctor: new () => SpeechRec) => {
    try {
      recRef.current?.abort();
    } catch {
      /* ignore */
    }

    const rec = new Ctor();
    recRef.current = rec;
    wantListenRef.current = true;
    rec.lang = LANG_CANDIDATES[0];
    rec.continuous = true;
    rec.interimResults = true;
    rec.maxAlternatives = 3;

    rec.onresult = (ev) => {
      let finalChunk = "";
      let interimChunk = "";
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const row = ev.results[i];
        const best = row[0]?.transcript ?? "";
        if (row.isFinal) finalChunk += best;
        else interimChunk += best;
      }
      if (finalChunk.trim()) {
        const prev = baseRef.current.trim();
        const next = prev ? `${prev} ${finalChunk.trim()}` : finalChunk.trim();
        baseRef.current = next;
        onChange(next);
        setInterim("");
      } else {
        setInterim(interimChunk);
      }
    };

    rec.onerror = (ev) => {
      if (ev.error === "aborted") return;
      if (ev.error === "not-allowed") {
        setStatus("اسمح بالميكروفون من إعدادات المتصفح");
        wantListenRef.current = false;
        setListening(false);
        setStarting(false);
        return;
      }
      if (ev.error === "no-speech") {
        // استمر بالاستماع — لا تزعج المستخدم
        return;
      }
      if (ev.error === "network") {
        setStatus("يلزم إنترنت للتسجيل الصوتي");
        wantListenRef.current = false;
        setListening(false);
        setStarting(false);
        return;
      }
      setStatus("تعذّر التسجيل");
      wantListenRef.current = false;
      setListening(false);
      setStarting(false);
    };

    rec.onend = () => {
      if (wantListenRef.current) {
        try {
          rec.start();
          return;
        } catch {
          wantListenRef.current = false;
        }
      }
      setListening(false);
      setStarting(false);
      setInterim("");
    };

    try {
      rec.start();
      setListening(true);
      setStarting(false);
      setStatus(null);
    } catch {
      setStatus("تعذّر بدء التسجيل");
      wantListenRef.current = false;
      setListening(false);
      setStarting(false);
    }
  };

  const start = async () => {
    const Ctor = getSpeechRecognitionCtor();
    if (!Ctor) {
      setSupported(false);
      setStatus("استخدم Chrome أو Edge للتسجيل الصوتي");
      return;
    }

    setStarting(true);
    setStatus(null);

    const perm = await requestMicPermission();
    if (perm === "denied") {
      setStarting(false);
      setStatus("اسمح بالميكروفون ثم اضغط مرة أخرى");
      return;
    }
    if (perm === "unsupported") {
      setStarting(false);
      setStatus("لا يوجد ميكروفون على هذا الجهاز");
      return;
    }

    beginRecognition(Ctor);
  };

  const onMicClick = () => {
    if (listening || starting) {
      stop();
      return;
    }
    void start();
  };

  return (
    <div className="field-voice-wrap">
      <div className="field-voice-head">
        <label className="field-label" style={{ marginBottom: 0 }}>
          ملاحظات
        </label>
        <button
          type="button"
          className={`field-mic-btn ${listening ? "listening" : ""}`}
          onClick={onMicClick}
          disabled={!supported}
          aria-pressed={listening}
          aria-label={listening ? "إيقاف التسجيل" : "بدء التسجيل"}
        >
          <span aria-hidden>
            {starting ? "…" : listening ? "⏹" : "🎤"}
          </span>
        </button>
      </div>

      <div className="field-voice-box">
        <textarea
          className="field-textarea"
          value={
            interim
              ? `${value}${value.trim() ? " " : ""}${interim}`
              : value
          }
          onChange={(e) => {
            setInterim("");
            onChange(e.target.value);
            baseRef.current = e.target.value;
          }}
          placeholder={placeholder}
          rows={3}
        />
        {listening && (
          <div className="field-voice-pulse" aria-hidden>
            <span />
            <span />
            <span />
          </div>
        )}
      </div>

      {status && <p className="field-inline-status">{status}</p>}
      {listening && !status && (
        <p className="field-inline-status field-voice-live">يستمع… اضغط للإيقاف</p>
      )}
    </div>
  );
}
