import "server-only";
import { cookies } from "next/headers";
import { SESSION_COOKIE_NAME, isValidSessionToken } from "./auth";

/// Las server actions se invocan con un POST a la ruta de la pagina, que
/// ya pasa por proxy.ts; aun asi, las acciones destructivas vuelven a
/// comprobar la cookie de sesion del panel por si una ruta quedara
/// publica por error.
export async function requireAdminSession(): Promise<void> {
  const token = (await cookies()).get(SESSION_COOKIE_NAME)?.value;
  if (!(await isValidSessionToken(token))) {
    throw new Error("Sesión de administrador inválida o vencida. Vuelve a iniciar sesión.");
  }
}
