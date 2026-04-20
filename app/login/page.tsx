"use client";

import { supabase } from "../../lib/supabaseClient";
import { LogoMark, Wordmark } from "../../lib/ui";

export default function LoginPage() {
  const signIn = async () => {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${location.origin}/auth/callback` },
    });
    if (error) alert(error.message);
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "var(--ink)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 24,
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* background glow */}
      <div style={{
        position: "absolute", left: "-10%", bottom: "-10%",
        width: 600, height: 600,
        background: "radial-gradient(circle, rgba(179,27,27,0.15) 0%, transparent 65%)",
        pointerEvents: "none",
      }} />
      <div style={{
        position: "absolute", right: "-5%", top: "-5%",
        width: 400, height: 400,
        background: "radial-gradient(circle, rgba(179,27,27,0.08) 0%, transparent 70%)",
        pointerEvents: "none",
      }} />

      {/* card */}
      <div
        className="fade-up"
        style={{
          background: "var(--white)",
          borderRadius: 20,
          padding: "48px 40px",
          width: "100%",
          maxWidth: 400,
          position: "relative",
          zIndex: 1,
        }}
      >
        {/* logo */}
        <div style={{ textAlign: "center", marginBottom: 32 }}>
          <div style={{ display: "flex", justifyContent: "center", marginBottom: 14 }}>
            <LogoMark size={52} />
          </div>
          <Wordmark size={22} />
          <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 5 }}>
            Cornell University Figure Skating Club
          </div>
        </div>

        <div
          style={{
            fontFamily: "'Syne', sans-serif",
            fontWeight: 800,
            fontSize: 20,
            textAlign: "center",
            marginBottom: 6,
            letterSpacing: "-0.02em",
          }}
        >
          Welcome back
        </div>
        <div style={{ fontSize: 13, color: "var(--muted)", textAlign: "center", marginBottom: 32 }}>
          Sign in with your Cornell Google account to book ice time.
        </div>

        <button
          onClick={signIn}
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 10,
            width: "100%",
            padding: "13px 16px",
            border: "1.5px solid var(--border)",
            borderRadius: 10,
            fontSize: 14,
            fontWeight: 600,
            cursor: "pointer",
            background: "white",
            color: "var(--ink)",
            fontFamily: "'DM Sans', sans-serif",
            transition: "border-color .15s, color .15s",
          }}
          onMouseEnter={e => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = "var(--red)";
            (e.currentTarget as HTMLButtonElement).style.color = "var(--red)";
          }}
          onMouseLeave={e => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = "var(--border)";
            (e.currentTarget as HTMLButtonElement).style.color = "var(--ink)";
          }}
        >
          {/* Google G */}
          <svg width="18" height="18" viewBox="0 0 48 48">
            <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
            <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
            <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
            <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.18 1.48-4.97 2.31-8.16 2.31-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
          </svg>
          Continue with Cornell SSO
        </button>

        <div style={{ textAlign: "center", marginTop: 20, fontSize: 11, color: "var(--muted)" }}>
          netid@cornell.edu · Secure OAuth sign-in
        </div>
      </div>
    </div>
  );
}