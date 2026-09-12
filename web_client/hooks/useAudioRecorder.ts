'use client';

// Mirrors the recording half of league_chat_screen.dart's
// _startRecording/_cancelRecording/_sendRecording (built on the `record`
// package there) using the browser's MediaRecorder API instead. Records to
// a Blob rather than a temp file — the caller uploads that Blob directly
// via uploadAudioFile.

import { useCallback, useRef, useState } from 'react';

export function useAudioRecorder() {
  const [isRecording, setIsRecording] = useState(false);
  const [elapsedMs, setElapsedMs] = useState(0);
  const [permissionDenied, setPermissionDenied] = useState(false);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const startedAtRef = useRef<number>(0);
  const tickerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const cleanupStream = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    if (tickerRef.current) {
      clearInterval(tickerRef.current);
      tickerRef.current = null;
    }
  }, []);

  const start = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      setPermissionDenied(false);

      streamRef.current = stream;
      chunksRef.current = [];

      const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus') ? 'audio/webm;codecs=opus' : undefined;
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };
      mediaRecorderRef.current = recorder;
      recorder.start();

      startedAtRef.current = Date.now();
      setElapsedMs(0);
      tickerRef.current = setInterval(() => setElapsedMs(Date.now() - startedAtRef.current), 250);
      setIsRecording(true);
    } catch (e) {
      setPermissionDenied(true);
      cleanupStream();
      throw e;
    }
  }, [cleanupStream]);

  const cancel = useCallback(() => {
    try {
      mediaRecorderRef.current?.stop();
    } catch {
      // ignore
    }
    cleanupStream();
    chunksRef.current = [];
    mediaRecorderRef.current = null;
    setIsRecording(false);
    setElapsedMs(0);
  }, [cleanupStream]);

  /** Stops recording and resolves with the recorded audio Blob + elapsed ms. */
  const stop = useCallback((): Promise<{ blob: Blob; durationMs: number }> => {
    return new Promise((resolve, reject) => {
      const recorder = mediaRecorderRef.current;
      if (!recorder) {
        reject(new Error('Not recording.'));
        return;
      }

      const durationMs = Date.now() - startedAtRef.current;
      recorder.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: recorder.mimeType || 'audio/webm' });
        cleanupStream();
        mediaRecorderRef.current = null;
        setIsRecording(false);
        setElapsedMs(0);
        resolve({ blob, durationMs });
      };
      recorder.stop();
    });
  }, [cleanupStream]);

  const elapsedLabel = (() => {
    const totalSeconds = Math.floor(elapsedMs / 1000);
    const mm = Math.floor(totalSeconds / 60).toString().padStart(2, '0');
    const ss = (totalSeconds % 60).toString().padStart(2, '0');
    return `${mm}:${ss}`;
  })();

  return { isRecording, elapsedMs, elapsedLabel, permissionDenied, start, stop, cancel };
}
