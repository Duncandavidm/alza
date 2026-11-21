import Link from "next/link";

/// Las dos formas de dar un cupon, en una sola seccion "Cupones".
export default function CouponTabs({ active }: { active: "habitos" | "regalar" }) {
  const tab = (href: string, key: "habitos" | "regalar", label: string, hint: string) => (
    <Link
      href={href}
      className="card"
      style={{
        flex: 1,
        minWidth: 220,
        textDecoration: "none",
        color: "inherit",
        borderColor: active === key ? "var(--accent, #0f9d6b)" : undefined,
        borderWidth: active === key ? 2 : undefined,
        margin: 0,
      }}
    >
      <strong>{label}</strong>
      <div className="text-dim">{hint}</div>
    </Link>
  );
  return (
    <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 16 }}>
      {tab("/cupones", "habitos", "🤖 Automáticos por buenos hábitos", "Se entregan solos a quien cumple una regla (ahorro, metas, presupuestos…).")}
      {tab("/cupones/regalar", "regalar", "🎁 Regalar cupones", "Tú eliges a quién: clientes por correo o un grupo, con la cantidad que compraste.")}
    </div>
  );
}
