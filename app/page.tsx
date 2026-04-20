"use client";

import { useEffect } from "react";
import { supabase } from "../lib/supabaseClient";

export default function Home() {
  useEffect(() => {
    const go = async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) window.location.href = "/dashboard";
      else window.location.href = "/login";
    };
    go();
  }, []);

  return <p style={{ padding: 24 }}>Loading…</p>;
}
