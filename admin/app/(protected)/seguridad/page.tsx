import QRCode from "qrcode";
import ActionForm from "@/components/ActionForm";
import { getAdminSecurity } from "@/lib/admin-login-guard";
import { otpauthUri } from "@/lib/totp";
import { confirmTotpSetup, disableTotp, startTotpSetup } from "./actions";

export const dynamic = "force-dynamic";

function groups(secret: string): string {
  return secret.replace(/(.{4})/g, "$1 ").trim();
}

export default async function SecurityPage() {
  const security = await getAdminSecurity();
  const pending = security.totp_pending_secret;
  const qrSvg = pending ? await QRCode.toString(otpauthUri(pending), { type: "svg", margin: 1, width: 200 }) : null;

  return (
    <>
      <h1>Seguridad del panel</h1>

      <div className="card">
        <h2>Verificación en dos pasos</h2>
        {security.totp_enabled ? (
          <>
            <p>
              <span className="badge active">Activada</span> El inicio de sesión pide la clave y un código de 6
              dígitos de tu app de autenticación.
            </p>
            <ActionForm action={disableTotp} submitLabel="Desactivar" submitClassName="danger" inline
              confirm="¿Seguro? El panel quedará protegido solo con la clave.">
              <input type="text" name="code" inputMode="numeric" maxLength={7} required placeholder="Código actual" autoComplete="one-time-code" />
            </ActionForm>
          </>
        ) : pending && qrSvg ? (
          <>
            <ol>
              <li>Abre Google Authenticator, Microsoft Authenticator o 1Password en tu teléfono.</li>
              <li>Escanea este código QR (o escribe la clave a mano).</li>
              <li>Escribe el código de 6 dígitos que muestra la app y toca Activar.</li>
            </ol>
            <div className="qr-box" dangerouslySetInnerHTML={{ __html: qrSvg }} />
            <p className="text-dim">
              Clave: <code>{groups(pending)}</code>
            </p>
            <ActionForm action={confirmTotpSetup} submitLabel="Activar" inline>
              <input type="text" name="code" inputMode="numeric" maxLength={7} required placeholder="Código de 6 dígitos" autoComplete="one-time-code" />
            </ActionForm>
            <p className="text-dim" style={{ marginTop: 12 }}>
              Guarda la app de autenticación con cuidado: si pierdes el teléfono, la verificación solo se puede
              quitar desde la base de datos.
            </p>
          </>
        ) : (
          <>
            <p>
              <span className="badge">Desactivada</span> Hoy el panel solo pide la clave. Actívala para pedir también
              un código que cambia cada 30 segundos.
            </p>
            <form action={startTotpSetup}>
              <button type="submit">Configurar verificación en dos pasos</button>
            </form>
          </>
        )}
      </div>

      <div className="card">
        <h2>Protecciones activas</h2>
        <ul>
          <li>Sesión en cookie segura (httpOnly, Secure, SameSite=Strict) de 12 horas; nunca en el almacenamiento del navegador.</li>
          <li>Cada página y cada acción del panel verifican la sesión en el servidor.</li>
          <li>Límite de intentos: 5 fallidos en 15 minutos bloquean esa conexión; 30 en total bloquean el inicio de sesión por 15 minutos.</li>
          <li>Política de seguridad de contenido (CSP): el navegador solo ejecuta scripts del propio panel.</li>
        </ul>
      </div>
    </>
  );
}
