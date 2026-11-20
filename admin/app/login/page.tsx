import { login } from "./actions";
import { getAdminSecurity } from "@/lib/admin-login-guard";

export const dynamic = "force-dynamic";

const ERRORS: Record<string, string> = {
  "1": "Clave incorrecta.",
  "2fa": "Clave o código incorrecto.",
  locked: "Demasiados intentos fallidos. Espera 15 minutos y vuelve a intentar.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const security = await getAdminSecurity().catch(() => null);
  const needsCode = security?.totp_enabled ?? false;

  return (
    <div className="page" style={{ maxWidth: 360, paddingTop: 80 }}>
      <h1>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className="brand-mark" src="/monavi-mark.svg" alt="" aria-hidden="true" />
        MonAvi Admin
      </h1>
      <p className="text-dim">Panel interno — clave compartida del equipo.</p>
      <form action={login} className="card">
        <div className="field">
          <label htmlFor="password">Clave</label>
          <input id="password" name="password" type="password" autoFocus required autoCapitalize="off" autoCorrect="off" spellCheck={false} autoComplete="current-password" style={{ width: "100%" }} />
        </div>
        {needsCode && (
          <div className="field">
            <label htmlFor="code">Código de 6 dígitos (app de autenticación)</label>
            <input type="text" id="code" name="code" inputMode="numeric" pattern="[0-9 ]{6,7}" maxLength={7} required autoComplete="one-time-code" style={{ width: "100%" }} />
          </div>
        )}
        <button type="submit" style={{ width: "100%" }}>
          Entrar
        </button>
        {error && <p className="error">{ERRORS[error] ?? "No se pudo iniciar sesión."}</p>}
      </form>
    </div>
  );
}
