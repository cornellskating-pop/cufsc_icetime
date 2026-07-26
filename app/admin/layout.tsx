"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabaseClient";
import { Loading } from "../../lib/ui";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const [authorized, setAuthorized] = useState(false);

  useEffect(() => {
    void supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) {
        window.location.replace("/login");
        return;
      }

      const { data: profile } = await supabase
        .from("users")
        .select("is_admin")
        .eq("id", data.user.id)
        .maybeSingle();

      if (!profile?.is_admin) {
        window.location.replace("/dashboard");
        return;
      }

      setAuthorized(true);
    });
  }, []);

  return authorized ? <>{children}</> : <Loading label="Checking admin access…" />;
}
