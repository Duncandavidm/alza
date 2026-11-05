import Link from "next/link";
import { logout } from "../login/actions";

export default function ProtectedLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <nav className="top">
        <span className="brand">MonAvi Admin</span>
        <Link href="/">Resumen</Link>
        <Link href="/merchants">Comercios y ofertas</Link>
        <Link href="/card-reports">Reportes de tarjeta</Link>
        <Link href="/bank-partners">Bancos patrocinadores</Link>
        <Link href="/bank-reports">Reportes de banco</Link>
        <Link href="/alerts">Alertas</Link>
        <form action={logout}>
          <button type="submit" className="secondary">
            Salir
          </button>
        </form>
      </nav>
      <div className="page">{children}</div>
    </>
  );
}
