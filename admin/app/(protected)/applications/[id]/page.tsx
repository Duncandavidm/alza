import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { APPLICATION_STATUSES } from "@/lib/applications";
import { formatDateTime } from "@/lib/format";
import ActionForm from "@/components/ActionForm";
import { createMerchantFromApplication, updateApplication } from "./actions";

type Application = {
  id: string;
  business_name: string;
  ruc: string | null;
  contact_name: string;
  email: string;
  phone: string | null;
  category: string | null;
  address: string | null;
  maps_url: string | null;
  instagram: string | null;
  message: string | null;
  status: string;
  notes: string | null;
  merchant_id: string | null;
  created_at: string;
  updated_at: string;
};

function instagramUrl(handle: string): string {
  if (/^https?:\/\//i.test(handle)) return handle;
  return `https://instagram.com/${handle.replace(/^@/, "")}`;
}

function safeHttpUrl(value: string): string | null {
  return /^https?:\/\//i.test(value) ? value : null;
}

export default async function ApplicationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = supabaseAdmin();
  const { data: application } = await supabase
    .from("merchant_applications")
    .select(
      "id, business_name, ruc, contact_name, email, phone, category, address, maps_url, instagram, message, status, notes, merchant_id, created_at, updated_at"
    )
    .eq("id", id)
    .maybeSingle<Application>();
  if (!application) notFound();

  const { data: merchant } = application.merchant_id
    ? await supabase
        .from("partner_merchants")
        .select("id, name")
        .eq("id", application.merchant_id)
        .maybeSingle<{ id: string; name: string }>()
    : { data: null };

  const mapsHref = application.maps_url ? safeHttpUrl(application.maps_url) : null;
  const phoneDigits = application.phone?.replace(/[^\d+]/g, "") ?? "";

  return (
    <>
      <p className="text-dim">
        <Link href="/applications">← Solicitudes</Link>
      </p>
      <h1>{application.business_name}</h1>
      <p className="text-dim">
        Recibida el {formatDateTime(application.created_at)} · <span className={`badge ${application.status}`}>{application.status}</span>
      </p>

      <div className="card">
        <h3>Datos de la solicitud</h3>
        <dl className="detail-list">
          <dt>Negocio</dt>
          <dd>{application.business_name}</dd>
          <dt>RUC</dt>
          <dd>{application.ruc ?? <span className="text-dim">No lo indicó</span>}</dd>
          <dt>Contacto</dt>
          <dd>{application.contact_name}</dd>
          <dt>Correo</dt>
          <dd>
            <a href={`mailto:${application.email}`}>{application.email}</a>
          </dd>
          <dt>Teléfono</dt>
          <dd>
            {application.phone ? (
              <>
                <a href={`tel:${phoneDigits}`}>{application.phone}</a>
                {phoneDigits && (
                  <>
                    {" · "}
                    <a href={`https://wa.me/${phoneDigits.replace(/^\+/, "")}`} target="_blank" rel="noreferrer">
                      WhatsApp
                    </a>
                  </>
                )}
              </>
            ) : (
              "—"
            )}
          </dd>
          <dt>Categoría</dt>
          <dd>{application.category ?? "—"}</dd>
          <dt>Dirección</dt>
          <dd>{application.address ?? "—"}</dd>
          <dt>Google Maps</dt>
          <dd>
            {mapsHref ? (
              <a href={mapsHref} target="_blank" rel="noreferrer">
                {application.maps_url}
              </a>
            ) : (
              (application.maps_url ?? "—")
            )}
          </dd>
          <dt>Instagram</dt>
          <dd>
            {application.instagram ? (
              <a href={instagramUrl(application.instagram)} target="_blank" rel="noreferrer">
                {application.instagram}
              </a>
            ) : (
              "—"
            )}
          </dd>
          <dt>Mensaje</dt>
          <dd style={{ whiteSpace: "pre-wrap" }}>{application.message ?? "—"}</dd>
        </dl>
      </div>

      <div className="card">
        <h3>Seguimiento interno</h3>
        <ActionForm action={updateApplication.bind(null, application.id)} submitLabel="Guardar">
          <div className="field">
            <label>Estado</label>
            <select name="status" defaultValue={application.status}>
              {APPLICATION_STATUSES.map((status) => (
                <option key={status} value={status}>
                  {status}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Notas internas (no las ve el comercio)</label>
            <textarea name="notes" rows={5} maxLength={4000} defaultValue={application.notes ?? ""} style={{ width: "100%" }} />
          </div>
        </ActionForm>
      </div>

      <div className="card">
        <h3>Comercio aliado</h3>
        {merchant ? (
          <p>
            Esta solicitud ya tiene comercio aliado: <Link href={`/merchants/${merchant.id}`}>{merchant.name}</Link>. Ahí se
            suben el logo y los productos canjeables.
          </p>
        ) : (
          <>
            <p className="text-dim">
              Crea el comercio aliado con los datos de esta solicitud (nombre, RUC, categoría, dirección y enlace de Maps).
              La solicitud pasa a “aprobada” y te llevamos al comercio para subir el logo y los productos.
            </p>
            <ActionForm
              action={createMerchantFromApplication.bind(null, application.id)}
              className="grid-form"
              submitLabel="Crear comercio aliado"
              pendingLabel="Creando…"
            >
              <div className="field">
                <label>Nombre del comercio</label>
                <input type="text" name="name" required maxLength={120} defaultValue={application.business_name} />
              </div>
              <div className="field">
                <label>RUC {application.ruc ? "" : "(no lo indicó: pídeselo)"}</label>
                <input type="text" name="ruc" required maxLength={40} defaultValue={application.ruc ?? ""} />
              </div>
            </ActionForm>
          </>
        )}
      </div>
    </>
  );
}
