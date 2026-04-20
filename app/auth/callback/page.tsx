"use client";

import { useEffect } from "react";
import { supabase } from "../../../lib/supabaseClient";

export default function CallbackPage() {
  useEffect(() => {
    const finish = async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) window.location.href = "/";
      else window.location.href = "/login";
    };
    finish();
  }, []);

  return <p style={{ padding: 24 }}>Signing you in…</p>;
}
