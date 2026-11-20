import Link from "next/link";
import { headers } from "next/headers";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { formatDateTime } from "@/lib/format";
import CopyButton from "@/components/CopyButton";
import { APPLICATION_STATUSES, applicationTabLabel, isApplicationStatus, type ApplicationStatus } from "@/lib/applications";

type Application = {
  id: string;
  business_name: string;
  ruc: string | null;
  contact_name: string;
  email: string;
  phone: string | null;
  category: string | null;
  status: ApplicationStatus;
  merchant_id: string | null;
  created_at: string;
};

async function countByStatus(status: ApplicationStatus): Promise<number> {
  const { count } = await supabaseAdmin()
    .from("merchant_applications")
    .select("id", { count: "exact", head: true })
    .eq("status", status);
  return count ?? 0;
}

export default async function ApplicationsPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status: rawStatus } = await searchParams;
  const status = isApplicationStatus(rawStatus) ? rawStatus : null;

  let query = supabaseAdmin()
    .from("merchant_applications")
    .select("id, business_name, ruc, contact_name, email, phone, category, status, merchant_id, created_at")
    .order("created_at", { ascending: false })
    .limit(300);
  if (status) query = query.eq("status", status);

  const [{ data: applications, error }, ...counts] = await Promise.all([
    query.returns<Application[]>(),
    ...APPLICATION_STATUSES.map(countByStatus),
  ]);
  const total = counts.reduce((sum, value) => sum + value, 0);

  const headerList = await headers();
  const host = headerList.get("x-forwarded-host") ?? headerList.get("host") ?? "monavi.vercel.app";
  const protocol = headerList.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  const landingUrl = `${protocol}://${host}/aliados`;

  return (
    <>
      <h1>Solicitudes de comercios</h1>
      <p className="text-dim">
        Comercios que pidieron ser aliados desde la landing pública{" "}
        <a href="/aliados" target="_blank" rel="noreferrer">
          /aliados
        </a>
        . Contáctalos, anota cómo va la conversación y, cuando digan que sí, crea el comercio aliado desde la solicitud.
      </p>
      <div className="card" style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
        <span className="text-dim">Enlace para compartir con comercios:</span>
        <code>{landingUrl}</code>
        <CopyButton value={landingUrl} />
      </div>

      <div className="tabs">
        <Link href="/applications" className={status === null ? "tab active" : "tab"}>
          Todas <span className="count">{total}</span>
        </Link>
        {APPLICATION_STATUSES.map((value, index) => (
          <Link key={value} href={`/applications?status=${value}`} className={status === value ? "tab active" : "tab"}>
            {applicationTabLabel(value)} <span className={`count${value === "nueva" && counts[index] > 0 ? " hot" : ""}`}>{counts[index]}</span>
          </Link>
        ))}
      </div>

      <div className="card table-scroll">
        {error && <p className="error">No se pudieron leer las solicitudes: {error.message}</p>}
        <table>
          <thead>
            <tr>
              <th>Recibida</th>
              <th>Negocio</th>
              <th>Contacto</th>
              <th>Categoría</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {(applications ?? []).map((application) => (
              <tr key={application.id}>
                <td className="text-dim">{formatDateTime(application.created_at)}</td>
                <td>
                  <Link href={`/applications/${application.id}`}>{application.business_name}</Link>
                  {application.ruc && <div className="text-dim">RUC {application.ruc}</div>}
                </td>
                <td>
                  {application.contact_name}
                  <div className="text-dim">
                    {application.email}
                    {application.phone ? ` · ${application.phone}` : ""}
                  </div>
                </td>
                <td className="text-dim">{application.category ?? "—"}</td>
                <td>
                  <span className={`badge ${application.status}`}>{application.status}</span>
                </td>
                <td>
                  <Link href={`/applications/${application.id}`}>Ver</Link>
                  {application.merchant_id && (
                    <>
                      {" · "}
                      <Link href={`/merchants/${application.merchant_id}`}>Comercio</Link>
                    </>
                  )}
                </td>
              </tr>
            ))}
            {(applications ?? []).length === 0 && !error && (
              <tr>
                <td colSpan={6} className="text-dim">
                  {status ? `No hay solicitudes en estado “${status}”.` : "Todavía no llegan solicitudes."}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}
