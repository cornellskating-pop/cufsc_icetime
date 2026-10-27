"use client";
import { useEffect, useRef, type ReactNode } from "react";

export function AdminSessionEditor({ modal, onClose, children }: { modal: boolean; onClose: () => void; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (!modal) return;
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, [modal]);
  if (!modal) return <>{children}</>;
  return <dialog ref={ref} aria-label="Session editor" onCancel={event => { event.preventDefault(); onClose(); }}
    style={{ width:"min(600px, calc(100vw - 24px))", maxHeight:"calc(100dvh - 24px)", overflowY:"auto", padding:0, border:0, borderRadius:16, color:"var(--ink)" }}>
    {children}
    <style>{`dialog::backdrop { background:rgba(0,0,0,.5); }`}</style>
  </dialog>;
}
