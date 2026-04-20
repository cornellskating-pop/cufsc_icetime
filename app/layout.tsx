import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CUFSC Ice Time",
  description: "Cornell University Figure Skating Club — Ice Time Booking",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
