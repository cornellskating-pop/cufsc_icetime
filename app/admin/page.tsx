"use client";
import { useEffect } from "react";

export default function AdminHome() {
  useEffect(() => {
    window.location.href = "/admin/sessions";
  }, []);
  return null;
}