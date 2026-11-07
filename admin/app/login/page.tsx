import { login } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

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
          <input id="password" name="password" type="password" autoFocus required style={{ width: "100%" }} />
        </div>
        <button type="submit" style={{ width: "100%" }}>
          Entrar
        </button>
        {error && <p className="error">Clave incorrecta.</p>}
      </form>
    </div>
  );
}
