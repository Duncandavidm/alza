import { supabaseAdmin } from "@/lib/supabase-admin";
import { createTeaching, deleteTeaching, setTeachingActive, updateTeaching } from "./actions";

export const dynamic = "force-dynamic";

type Teaching = {
  id: string;
  step: number | null;
  title: string;
  body: string;
  ai_note: string | null;
  source: string | null;
  show_in_app: boolean;
  use_in_ai: boolean;
  active: boolean;
  sort: number;
};

const STEPS: Record<number, string> = {
  1: "Paso 1 · Conoce tu foto",
  2: "Paso 2 · Dale un trabajo a cada dólar",
  3: "Paso 3 · Control constante",
  4: "Paso 4 · Colchón inicial",
  5: "Paso 5 · Adiós deudas caras",
  6: "Paso 6 · Colchón completo",
  7: "Paso 7 · Pon tu dinero a trabajar",
};

function TeachingFields({ t }: { t?: Teaching }) {
  return (
    <>
      <div className="field">
        <label>Paso del plan</label>
        <select name="step" defaultValue={t?.step ? String(t.step) : ""}>
          <option value="">General (todos los días)</option>
          {Object.entries(STEPS).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>
      </div>
      <div className="field">
        <label>Título</label>
        <input type="text" name="title" defaultValue={t?.title} maxLength={120} required placeholder="Ej. La regla de las 48 horas" />
      </div>
      <div className="field" style={{ gridColumn: "1 / -1" }}>
        <label>Enseñanza (lo que verá la persona en la app)</label>
        <textarea name="body" defaultValue={t?.body} maxLength={1500} rows={4} required placeholder="Explícalo en lenguaje sencillo, como se lo dirías a un amigo." />
      </div>
      <div className="field" style={{ gridColumn: "1 / -1" }}>
        <label>Cómo debe aplicarla la IA (opcional)</label>
        <textarea name="ai_note" defaultValue={t?.ai_note ?? ""} maxLength={800} rows={2} placeholder="Ej. Si la persona hace compras grandes no planeadas, sugiérele esperar 48 horas." />
      </div>
      <div className="field">
        <label>Fuente (solo para ti, opcional)</label>
        <input type="text" name="source" defaultValue={t?.source ?? ""} maxLength={200} placeholder="Ej. idea propia, libro que leí" />
      </div>
      <div className="field">
        <label>Orden dentro del paso</label>
        <input type="number" name="sort" defaultValue={t?.sort ?? 100} min={0} max={10000} />
      </div>
      <div className="field">
        <label>
          <input type="checkbox" name="show_in_app" defaultChecked={t?.show_in_app ?? true} /> Mostrar como lección en la app
        </label>
        <label>
          <input type="checkbox" name="use_in_ai" defaultChecked={t?.use_in_ai ?? true} /> Que la IA la aplique
        </label>
      </div>
    </>
  );
}

export default async function EnsenanzasPage() {
  const { data } = await supabaseAdmin()
    .from("finance_teachings")
    .select("id, step, title, body, ai_note, source, show_in_app, use_in_ai, active, sort")
    .order("step", { ascending: true, nullsFirst: false })
    .order("sort", { ascending: true })
    .returns<Teaching[]>();
  const teachings = data ?? [];
  const groups: { label: string; items: Teaching[] }[] = [
    ...Object.entries(STEPS).map(([step, label]) => ({ label, items: teachings.filter((t) => t.step === Number(step)) })),
    { label: "Generales", items: teachings.filter((t) => t.step === null) },
  ].filter((g) => g.items.length > 0);

  return (
    <>
      <h1>Método MonAvi · Enseñanzas</h1>
      <p className="text-dim">
        Estas enseñanzas son la base de la asesoría de MonAvi. Las que marcas como lección aparecen en la app, en “Tu plan
        en 7 pasos”. Las que marcas para la IA se aplican en el análisis y en las respuestas, usando los números de cada
        persona. Si lees algo valioso en un libro, escríbelo con tus propias palabras y agrégalo aquí: la app lo empieza a
        usar de inmediato, sin publicar una versión nueva.
      </p>

      <div className="card">
        <h3>Agregar enseñanza</h3>
        <form action={createTeaching} className="grid-form">
          <TeachingFields />
          <div className="field" style={{ alignSelf: "end" }}>
            <button type="submit">Agregar</button>
          </div>
        </form>
      </div>

      {groups.map((group) => (
        <div className="card" key={group.label}>
          <h3>{group.label}</h3>
          {group.items.map((t) => (
            <details key={t.id} style={{ borderTop: "1px solid var(--border)", padding: "10px 0" }}>
              <summary style={{ cursor: "pointer" }}>
                <strong>{t.title}</strong>{" "}
                {!t.active && <span className="badge paused">apagada</span>}{" "}
                {t.active && t.show_in_app && <span className="badge active">app</span>}{" "}
                {t.active && t.use_in_ai && <span className="badge active">IA</span>}
                <div className="text-dim" style={{ marginTop: 4 }}>{t.body}</div>
              </summary>
              <form action={updateTeaching} className="grid-form" style={{ marginTop: 10 }}>
                <input type="hidden" name="id" value={t.id} />
                <TeachingFields t={t} />
                <div className="field" style={{ alignSelf: "end" }}>
                  <button type="submit">Guardar cambios</button>
                </div>
              </form>
              <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                <form action={setTeachingActive.bind(null, t.id, !t.active)}>
                  <button type="submit" className={t.active ? "secondary" : undefined}>{t.active ? "Apagar" : "Activar"}</button>
                </form>
                <form action={deleteTeaching.bind(null, t.id)}>
                  <button type="submit" className="danger">Eliminar</button>
                </form>
              </div>
            </details>
          ))}
        </div>
      ))}
    </>
  );
}
