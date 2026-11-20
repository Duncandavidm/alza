"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { checkAdminPassword, createSessionToken, SESSION_COOKIE_NAME, SESSION_MAX_AGE_SECONDS } from "@/lib/auth";
import { clientIp, getAdminSecurity, isLoginLocked, recordLoginAttempt, updateAdminSecurity } from "@/lib/admin-login-guard";
import { verifyTotp } from "@/lib/totp";

export async function login(formData: FormData) {
  const password = String(formData.get("password") ?? "").slice(0, 200);
  const code = String(formData.get("code") ?? "").slice(0, 12);
  const ip = await clientIp();

  if (await isLoginLocked(ip)) {
    redirect("/login?error=locked");
  }

  const security = await getAdminSecurity();
  let ok = checkAdminPassword(password);
  let usedStep: number | null = null;
  if (ok && security.totp_enabled && security.totp_secret) {
    usedStep = verifyTotp(security.totp_secret, code, security.totp_last_step);
    ok = usedStep !== null;
  }

  await recordLoginAttempt(ip, ok);
  if (!ok) {
    redirect(security.totp_enabled ? "/login?error=2fa" : "/login?error=1");
  }
  if (usedStep !== null) {
    await updateAdminSecurity({ totp_last_step: usedStep });
  }

  const token = await createSessionToken();
  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, token, {
    httpOnly: true,
    secure: true,
    sameSite: "strict",
    maxAge: SESSION_MAX_AGE_SECONDS,
    path: "/",
  });

  redirect("/");
}

export async function logout() {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
  redirect("/login");
}
