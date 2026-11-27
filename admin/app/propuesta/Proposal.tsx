"use client";

import { useEffect, useMemo, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import CajaDemo from "../aliados/CajaDemo";
import Reveal from "../aliados/Reveal";

// Propuesta generica para comercios: "Tu marca aqui". Todo lo que se
// escribe en el estudio (nombre, logo, color, oferta) cambia en vivo las
// pantallas de la app de esta pagina. Nada se guarda ni se envia.

type Offer = "descuento" | "premio" | "campana";

type Brand = {
  name: string;
  logo: string | null;
  color: string;
  offer: Offer;
  value: string;
  product: string;
};

const PLACEHOLDER = "Tu marca aquí";
const DEFAULT_COLOR = "#3B5BDB";
const COLORS = ["#3B5BDB", "#E4002B", "#111111", "#00A585", "#F08C00", "#7048E8", "#0B7285", "#C2255C"];

const OFFERS: { id: Offer; label: string; hint: string }[] = [
  { id: "descuento", label: "Descuento", hint: "Un % para quienes usan MonAvi" },
  { id: "premio", label: "Premio", hint: "Un producto que se canjea con cashback" },
  { id: "campana", label: "Campaña", hint: "Cashback extra por comprar en tu tienda" },
];

const OFFER_DEFAULTS: Record<Offer, { value: string; product: string }> = {
  descuento: { value: "10", product: "En toda la tienda" },
  premio: { value: "5.00", product: "Accesorio de regalo" },
  campana: { value: "2", product: "En tus compras con factura" },
};

const WHATSAPP_URL =
  "https://wa.me/50767389720?text=" + encodeURIComponent("Hola, vi la propuesta de MonAvi y quiero que mi marca esté en la app.");

// ---------------------------------------------------------------- helpers

function initials(name: string): string {
  const words = name.replace(PLACEHOLDER, "Tu Marca").trim().split(/\s+/).filter(Boolean);
  return ((words[0]?.[0] ?? "T") + (words[1]?.[0] ?? "")).toUpperCase();
}

function money(value: number): string {
  const digits = Math.abs(value) >= 100 ? 0 : 2;
  return "$" + value.toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

/// Recorta el espacio vacio alrededor del logo (fondo transparente o de un
/// solo color) para que se vea grande dentro del circulo. Si algo falla,
/// usa el archivo tal cual.
async function trimmedLogo(file: File): Promise<string> {
  const original = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = original;
    await img.decode();
    const w = img.naturalWidth || 400, h = img.naturalHeight || 400;
    const scale = Math.min(1, 800 / Math.max(w, h));
    const cw = Math.max(1, Math.round(w * scale)), ch = Math.max(1, Math.round(h * scale));
    const canvas = document.createElement("canvas");
    canvas.width = cw; canvas.height = ch;
    const ctx = canvas.getContext("2d");
    if (!ctx) return original;
    ctx.drawImage(img, 0, 0, cw, ch);
    const data = ctx.getImageData(0, 0, cw, ch).data;
    const at = (x: number, y: number) => { const i = (y * cw + x) * 4; return [data[i], data[i + 1], data[i + 2], data[i + 3]]; };
    const bg = at(1, 1);
    const transparent = bg[3] < 40;
    const isContent = (x: number, y: number) => {
      const p = at(x, y);
      if (transparent) return p[3] > 40;
      return p[3] > 40 && Math.abs(p[0] - bg[0]) + Math.abs(p[1] - bg[1]) + Math.abs(p[2] - bg[2]) > 36;
    };
    let minX = cw, minY = ch, maxX = -1, maxY = -1;
    for (let y = 0; y < ch; y += 2) for (let x = 0; x < cw; x += 2) {
      if (isContent(x, y)) { if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }
    }
    if (maxX < minX || maxY < minY) return original;
    const pad = Math.round(Math.max(maxX - minX, maxY - minY) * 0.06);
    const x0 = Math.max(0, minX - pad), y0 = Math.max(0, minY - pad);
    const x1 = Math.min(cw, maxX + pad + 2), y1 = Math.min(ch, maxY + pad + 2);
    if ((x1 - x0) * (y1 - y0) > cw * ch * 0.85) return original;
    const out = document.createElement("canvas");
    out.width = x1 - x0; out.height = y1 - y0;
    const octx = out.getContext("2d");
    if (!octx) return original;
    octx.drawImage(canvas, x0, y0, out.width, out.height, 0, 0, out.width, out.height);
    URL.revokeObjectURL(original);
    return out.toDataURL("image/png");
  } catch {
    return original;
  }
}

function offerTitle(brand: Brand): string {
  const n = Number(brand.value.replace(",", "."));
  switch (brand.offer) {
    case "descuento":
      return `${Number.isFinite(n) && n > 0 ? Math.min(90, Math.round(n)) : 10}% de descuento`;
    case "premio":
      return brand.product.trim() || "Tu producto";
    case "campana":
      return `${Number.isFinite(n) && n >= 2 ? `${Math.round(n)}x` : "Doble"} cashback`;
  }
}

function offerDetail(brand: Brand): string {
  switch (brand.offer) {
    case "descuento":
      return `${brand.product.trim() || "En toda la tienda"} · 1 vez por semana`;
    case "premio": {
      const n = Number(brand.value.replace(",", "."));
      return `Por ${money(Number.isFinite(n) && n > 0 ? n : 5)} de cashback`;
    }
    case "campana":
      return `${brand.product.trim() || "En tus compras"} · llega al verificar tu factura`;
  }
}

function makeCode(seed: string): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let h = 2166136261;
  for (const ch of seed) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  let out = "";
  for (let i = 0; i < 6; i++) {
    h = Math.imul(h ^ (h >>> 13), 2246822519);
    out += alphabet[Math.abs(h) % alphabet.length];
  }
  return out;
}

/// QR ilustrativo (no escaneable).
function qrCells(seed: string): boolean[] {
  const n = 15;
  let h = 2166136261;
  for (const ch of seed) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  const finder = (r: number, c: number) => {
    for (const [fr, fc] of [[0, 0], [0, n - 5], [n - 5, 0]]) {
      const y = r - fr, x = c - fc;
      if (y >= 0 && y < 5 && x >= 0 && x < 5) return y === 0 || y === 4 || x === 0 || x === 4 || (y === 2 && x === 2);
    }
    return null;
  };
  const cells: boolean[] = [];
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
    const f = finder(r, c);
    if (f !== null) { cells.push(f); continue; }
    h = Math.imul(h ^ (h >>> 15), 2246822519) ^ (r * 31 + c);
    cells.push((h >>> 7) % 100 < 46);
  }
  return cells;
}

// ------------------------------------------------------------ piezas UI

function BrandMark({ brand, size = 44 }: { brand: Brand; size?: number }) {
  if (brand.logo) {
    return (
      <span className="pp-mark logo" style={{ width: size, height: size, padding: Math.round(size * 0.12) }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={brand.logo} alt="" />
      </span>
    );
  }
  return (
    <span className="pp-mark" style={{ width: size, height: size, background: brand.color, fontSize: size * 0.38 }}>
      {initials(brand.name)}
    </span>
  );
}

function Phone({ children, label, dark = false }: { children: React.ReactNode; label?: string; dark?: boolean }) {
  return (
    <figure className="pp-phone-wrap">
      <div className={`pp-phone${dark ? " dark" : ""}`}>
        <div className="pp-notch" />
        <div className="pp-status"><span>9:41</span><span>●●● ▮</span></div>
        <div className="pp-screen">{children}</div>
      </div>
      {label && <figcaption>{label}</figcaption>}
    </figure>
  );
}

function ScreenMerchants({ brand }: { brand: Brand }) {
  return (
    <>
      <div className="pp-app-title">Dónde canjear</div>
      <div className="pp-seg"><span>Descuentos</span><span className="on">Comercios</span></div>
      <div className="pp-card featured" style={{ ["--b" as string]: brand.color } as React.CSSProperties}>
        <div className="pp-card-head">
          <BrandMark brand={brand} size={46} />
          <div>
            <b>{brand.name || PLACEHOLDER}</b>
            <small>Aliado de MonAvi · a 1.2 km</small>
          </div>
        </div>
        <div className="pp-offer-pill">{offerTitle(brand)}</div>
        <div className="pp-card-actions">
          <span className="ghost">Cómo llegar</span>
          <span className="solid">Ver oferta</span>
        </div>
      </div>
      {["Café de la esquina", "Barbería Central"].map((name, i) => (
        <div className="pp-card muted" key={name}>
          <div className="pp-card-head">
            <span className="pp-mark" style={{ width: 38, height: 38, background: i ? "#ADB5BD" : "#CED4DA", fontSize: 14 }}>{name[0]}</span>
            <div><b>{name}</b><small>{i ? "15% de descuento" : "Capuchino gratis"}</small></div>
          </div>
        </div>
      ))}
    </>
  );
}

function ScreenOffer({ brand }: { brand: Brand }) {
  const emoji = brand.offer === "premio" ? "🎁" : brand.offer === "campana" ? "💸" : "🏷️";
  return (
    <>
      <div className="pp-hero-photo" style={{ background: `linear-gradient(135deg, ${brand.color}, ${brand.color}99)` }}>
        <span>{emoji}</span>
        <div className="pp-hero-mark"><BrandMark brand={brand} size={54} /></div>
      </div>
      <div className="pp-offer-body">
        <small>{brand.name || PLACEHOLDER}</small>
        <h4>{offerTitle(brand)}</h4>
        <p>{offerDetail(brand)}</p>
        <ul>
          {brand.offer === "campana" ? (
            <>
              <li>Compra en {brand.name || "la tienda"} y pide tu factura</li>
              <li>Escanéala en MonAvi</li>
              <li>El cashback extra llega al verificarla</li>
            </>
          ) : (
            <>
              <li>Genera tu código antes de pagar</li>
              <li>Muéstralo en caja</li>
              <li>Pide tu factura y gana cashback también</li>
            </>
          )}
        </ul>
        <span className="pp-cta" style={{ background: brand.color }}>
          {brand.offer === "campana" ? "Escanear mi factura" : brand.offer === "premio" ? "Canjear" : "Generar mi código"}
        </span>
      </div>
    </>
  );
}

function ScreenCode({ brand }: { brand: Brand }) {
  const code = makeCode(brand.name + brand.offer + brand.value);
  const cells = useMemo(() => qrCells(code), [code]);
  return (
    <div className="pp-code">
      <BrandMark brand={brand} size={52} />
      <b>{brand.name || PLACEHOLDER}</b>
      <span className="pp-code-offer">{offerTitle(brand)}</span>
      <div className="pp-qr">
        {cells.map((on, i) => <i key={i} className={on ? "on" : ""} />)}
      </div>
      <div className="pp-code-text">{code.slice(0, 3)} {code.slice(3)}</div>
      <small>Muéstralo en caja · vence en 14:52</small>
    </div>
  );
}

function ScreenLock({ brand }: { brand: Brand }) {
  // La notificacion la "firma" la marca; el texto habla en primera persona
  // para no repetir "Tu marca aqui" dentro del mensaje.
  const sender = brand.name.trim() || "Tu marca";
  const notes = [
    { when: "ahora", title: "¡Ya estamos en MonAvi! 🎉", body: `${offerTitle(brand)}: ${offerDetail(brand).toLowerCase()}.` },
    { when: "hace 2 h", title: "Te alcanza para un premio", body: "Con tu cashback ya puedes canjearlo en nuestra tienda." },
    { when: "ayer", title: "Factura verificada ✅", body: "Ganaste cashback por tu compra con nosotros. ¡Gracias!" },
  ];
  return (
    <div className="pp-lock">
      <div className="pp-lock-time">9:41</div>
      <div className="pp-lock-date">viernes, 27 de noviembre</div>
      {notes.map((n, i) => (
        <motion.div
          key={n.title + i}
          className="pp-note"
          initial={{ opacity: 0, y: 12 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.15 + i * 0.25 }}
        >
          <BrandMark brand={brand} size={30} />
          <div>
            <div className="pp-note-top"><b>{sender}</b><span>{n.when}</span></div>
            <strong>{n.title}</strong>
            <p>{n.body}</p>
          </div>
        </motion.div>
      ))}
    </div>
  );
}

// ------------------------------------------------------------ calculadora

function Calculator({ brand }: { brand: Brand }) {
  const [customers, setCustomers] = useState(80);
  const [ticket, setTicket] = useState(120);
  const [returnRate, setReturnRate] = useState(30);
  const discountPct = brand.offer === "descuento" ? Math.min(90, Math.max(0, Number(brand.value) || 10)) : 10;

  const sales = customers * ticket;
  const investment = sales * (discountPct / 100);
  const repeatMonthly = customers * (returnRate / 100) * ticket;
  const yearly = sales - investment + repeatMonthly * 11;

  return (
    <div className="pp-calc">
      <div className="pp-calc-inputs">
        <label>
          <span>Clientes nuevos al mes desde MonAvi <b>{customers}</b></span>
          <input type="range" min={10} max={500} step={10} value={customers} onChange={(e) => setCustomers(Number(e.target.value))} />
        </label>
        <label>
          <span>Ticket promedio <b>{money(ticket)}</b></span>
          <input type="range" min={5} max={1500} step={5} value={ticket} onChange={(e) => setTicket(Number(e.target.value))} />
        </label>
        <label>
          <span>Clientes que vuelven cada mes <b>{returnRate}%</b></span>
          <input type="range" min={0} max={80} step={5} value={returnRate} onChange={(e) => setReturnRate(Number(e.target.value))} />
        </label>
        <p className="pp-calc-note">Descuento usado: {discountPct}% (cámbialo arriba en «Descuento»).</p>
      </div>
      <div className="pp-calc-out" style={{ ["--b" as string]: brand.color } as React.CSSProperties}>
        <div><small>Ventas del primer mes</small><b>{money(sales)}</b></div>
        <div><small>Tu inversión en el descuento</small><b>−{money(investment)}</b></div>
        <div><small>Ventas al mes de clientes que vuelven</small><b>+{money(repeatMonthly)}</b></div>
        <div className="big"><small>Ventas estimadas en 12 meses</small><b>{money(yearly)}</b></div>
        <p>Costo de MonAvi: <b>$0</b>. Ejemplo ilustrativo con tus números, no es una promesa de resultados.</p>
      </div>
    </div>
  );
}

// ------------------------------------------------------------ pagina

const WAYS = [
  { icon: "🏷️", title: "Descuento para usuarios MonAvi", text: "Un % que tú eliges (10%, 15%…) y cada persona usa las veces que decidas: 1 vez por semana, por mes. Genera un código único que vence en 15 minutos." },
  { icon: "🎁", title: "Premio con cashback", text: "Un producto o servicio que los usuarios canjean con el cashback que ganan escaneando sus facturas. Llegan a tu tienda a buscarlo." },
  { icon: "💸", title: "Campaña de marca", text: "Cashback extra por comprar tus productos. Solo premias compras reales: el bono llega cuando verificamos la factura electrónica." },
  { icon: "📍", title: "Avisos por cercanía", text: "Próximamente: cuando alguien pase cerca de tu tienda, MonAvi le recordará tu oferta.", soon: true },
];

const STEPS = [
  { title: "Nos envías tu logo y tu oferta", text: "Elegimos juntos el descuento, el premio o la campaña, con el cupo y las fechas que quieras." },
  { title: "Publicamos tu ficha", text: "Tu marca aparece en MonAvi con tu logo, tu oferta y el botón de «Cómo llegar»." },
  { title: "Avisamos a los usuarios", text: "Les llega una notificación con tu oferta el día que entras a la app." },
  { title: "Validas en caja", text: "El cliente muestra su código y lo validas desde cualquier celular o tablet con tu PIN." },
];

const INCLUDED = [
  "Ficha de tu marca con logo, fotos y Cómo llegar",
  "Descuentos, premios y campañas ilimitados",
  "Notificación a los usuarios cuando entras",
  "App de caja para celular o tablet, con sonido y cámara",
  "Panel con canjes, visitas y resultados",
  "Cupos, fechas y pausas cuando quieras",
];

const FAQ = [
  { q: "¿Cuánto cuesta?", a: "Nada. Sin cuota de afiliación, sin mensualidad y sin comisión por venta. Tu inversión es el descuento o premio que tú decides dar." },
  { q: "¿Necesito integrar mi sistema o comprar equipos?", a: "No. La caja de MonAvi funciona en el navegador de cualquier celular o tablet, con tu PIN." },
  { q: "¿Cómo evitan que un código se use dos veces?", a: "Cada código es único, se usa una sola vez y vence solo. El PIN de tu tienda tiene límite de intentos." },
  { q: "¿Qué datos del cliente veo?", a: "Su nombre con la inicial del apellido, los últimos 4 dígitos de su teléfono, el código y el producto. Nunca su correo ni sus finanzas." },
  { q: "¿Puedo cambiar o pausar la oferta?", a: "Sí, cuando quieras, sin contratos largos." },
];

export default function Proposal({ initialName, initialColor }: { initialName: string; initialColor: string }) {
  const [brand, setBrand] = useState<Brand>({
    name: initialName,
    logo: null,
    color: initialColor || DEFAULT_COLOR,
    offer: "descuento",
    value: OFFER_DEFAULTS.descuento.value,
    product: OFFER_DEFAULTS.descuento.product,
  });
  const [screen, setScreen] = useState(0);
  const shownName = brand.name.trim() || PLACEHOLDER;
  // En las frases: "comprando en tu negocio" mientras no haya nombre.
  const textName = brand.name.trim() || "tu negocio";

  // El logo vive solo en este navegador (URL temporal).
  useEffect(() => () => { if (brand.logo?.startsWith("blob:")) URL.revokeObjectURL(brand.logo); }, [brand.logo]);

  const update = (patch: Partial<Brand>) => setBrand((b) => ({ ...b, ...patch }));
  const setOffer = (offer: Offer) => update({ offer, ...OFFER_DEFAULTS[offer] });

  const screens = [
    { label: "Tu marca en la app", node: <ScreenMerchants brand={brand} /> },
    { label: "Tu oferta", node: <ScreenOffer brand={brand} /> },
    { label: "El código en caja", node: <ScreenCode brand={brand} /> },
  ];

  const style = { ["--b" as string]: brand.color } as React.CSSProperties;

  return (
    <div className="landing al pp" style={style}>
      <header className="al-nav">
        <span className="al-logo pp-lockup">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/monavi-mark.svg" alt="" aria-hidden="true" />
          MonAvi <em>para</em>
          <span className="pp-lockup-brand"><BrandMark brand={brand} size={26} /> {shownName}</span>
        </span>
        <a href="#empezar" className="al-btn small">Empezar</a>
      </header>

      {/* HERO */}
      <section className="al-hero pp-hero">
        <div className="al-hero-inner">
          <Reveal className="al-hero-text">
            <span className="al-eyebrow">Propuesta para {textName}</span>
            <h1>
              Clientes que cuidan su dinero, <span>comprando en {textName}</span>
            </h1>
            <p>
              MonAvi es la app donde las personas ordenan sus finanzas y ganan cashback con sus facturas. Pon tu marca
              frente a ellas justo cuando deciden dónde comprar.
            </p>
            <div className="al-hero-actions">
              <a href="#estudio" className="al-btn">Ver mi marca en MonAvi</a>
              <a href="#empezar" className="al-btn ghost">Quiero empezar</a>
            </div>
            <div className="al-stats">
              <div><b>$0</b><span>de afiliación</span></div>
              <div><b>0%</b><span>de comisión</span></div>
              <div><b>1 celular</b><span>para validar</span></div>
            </div>
          </Reveal>
          <div className="pp-hero-phones">
            <motion.div initial={{ opacity: 0, y: 30, rotate: -4 }} animate={{ opacity: 1, y: 0, rotate: -4 }} transition={{ duration: 0.7 }}>
              <Phone><ScreenMerchants brand={brand} /></Phone>
            </motion.div>
            <motion.div className="front" initial={{ opacity: 0, y: 40, rotate: 5 }} animate={{ opacity: 1, y: 0, rotate: 5 }} transition={{ duration: 0.7, delay: 0.15 }}>
              <Phone dark><ScreenLock brand={brand} /></Phone>
            </motion.div>
          </div>
        </div>
      </section>

      {/* ESTUDIO */}
      <section className="al-section pp-studio-section" id="estudio">
        <Reveal>
          <span className="al-kicker">Pruébalo en vivo</span>
          <h2>Así se ve tu marca dentro de MonAvi</h2>
          <p className="al-lead">Escribe tu marca, sube tu logo y elige tu oferta. Las pantallas cambian al instante. Nada se guarda.</p>
        </Reveal>
        <div className="pp-studio">
          <div className="pp-controls">
            <label>
              <span>Nombre de tu marca</span>
              <input value={brand.name} placeholder={PLACEHOLDER} maxLength={40} onChange={(e) => update({ name: e.target.value })} />
            </label>
            <label className="pp-file">
              <span>Tu logo (PNG, JPG o SVG)</span>
              <div className="pp-file-row">
                <BrandMark brand={brand} size={48} />
                <input
                  type="file"
                  accept="image/png,image/jpeg,image/webp,image/svg+xml"
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) trimmedLogo(file).then((logo) => update({ logo }));
                  }}
                />
                {brand.logo && <button type="button" className="pp-link" onClick={() => update({ logo: null })}>Quitar</button>}
              </div>
            </label>
            <div className="pp-field">
              <span>Color de tu marca</span>
              <div className="pp-colors">
                {COLORS.map((c) => (
                  <button key={c} type="button" aria-label={`Color ${c}`} className={c === brand.color ? "on" : ""} style={{ background: c }} onClick={() => update({ color: c })} />
                ))}
                <input type="color" value={brand.color} onChange={(e) => update({ color: e.target.value })} aria-label="Otro color" />
              </div>
            </div>
            <div className="pp-field">
              <span>Qué ofreces</span>
              <div className="pp-offers">
                {OFFERS.map((o) => (
                  <button key={o.id} type="button" className={brand.offer === o.id ? "on" : ""} onClick={() => setOffer(o.id)}>
                    <b>{o.label}</b><small>{o.hint}</small>
                  </button>
                ))}
              </div>
            </div>
            <div className="pp-two">
              <label>
                <span>{brand.offer === "descuento" ? "Descuento (%)" : brand.offer === "premio" ? "Valor en cashback (US$)" : "Multiplicador de cashback"}</span>
                <input value={brand.value} inputMode="decimal" maxLength={6} onChange={(e) => update({ value: e.target.value })} />
              </label>
              <label>
                <span>{brand.offer === "premio" ? "Producto" : "Aplica en"}</span>
                <input value={brand.product} maxLength={40} onChange={(e) => update({ product: e.target.value })} />
              </label>
            </div>
          </div>

          <div className="pp-preview">
            <div className="pp-tabs">
              {screens.map((s, i) => (
                <button key={s.label} type="button" className={i === screen ? "on" : ""} onClick={() => setScreen(i)}>{s.label}</button>
              ))}
            </div>
            <AnimatePresence mode="wait">
              <motion.div key={screen} initial={{ opacity: 0, x: 24 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -24 }} transition={{ duration: 0.25 }}>
                <Phone>{screens[screen].node}</Phone>
              </motion.div>
            </AnimatePresence>
          </div>
        </div>
      </section>

      {/* NOTIFICACIONES */}
      <section className="al-section dark">
        <div className="al-split">
          <Reveal>
            <span className="al-kicker light">Te anunciamos</span>
            <h2>Tu marca llega directo a su pantalla</h2>
            <ul className="al-checks">
              <li>El día que entras, los usuarios reciben una notificación con tu oferta.</li>
              <li>Cuando a alguien le alcanza el cashback para tu premio, también le avisamos.</li>
              <li>Cada factura verificada en tu tienda le recuerda dónde compró.</li>
            </ul>
          </Reveal>
          <Reveal delay={0.15}>
            <div className="pp-center"><Phone dark><ScreenLock brand={brand} /></Phone></div>
          </Reveal>
        </div>
      </section>

      {/* FORMAS DE CRECER */}
      <section className="al-section">
        <Reveal>
          <span className="al-kicker">Tú eliges</span>
          <h2>Formas de atraer clientes con MonAvi</h2>
        </Reveal>
        <div className="al-benefits">
          {WAYS.map((w, i) => (
            <Reveal key={w.title} delay={(i % 2) * 0.08} className={`al-benefit${w.soon ? " pp-soon" : ""}`}>
              <span className="al-benefit-icon" aria-hidden="true">{w.icon}</span>
              <h3>{w.title}</h3>
              <p>{w.text}</p>
            </Reveal>
          ))}
        </div>
      </section>

      {/* CALCULADORA */}
      <section className="al-section alt" id="calculadora">
        <Reveal>
          <span className="al-kicker">Haz números</span>
          <h2>¿Cuánto puede traerle MonAvi a {textName}?</h2>
          <p className="al-lead">Mueve los valores con los números de tu tienda.</p>
        </Reveal>
        <Reveal delay={0.1}><Calculator brand={brand} /></Reveal>
      </section>

      {/* PASOS + CAJA */}
      <section className="al-section">
        <Reveal>
          <span className="al-kicker">Cómo empezamos</span>
          <h2>Tu marca activa en 4 pasos</h2>
        </Reveal>
        <ol className="al-steps">
          {STEPS.map((step, index) => (
            <Reveal key={step.title} delay={index * 0.1} className="al-step">
              <span className="al-step-n">{index + 1}</span>
              <h3>{step.title}</h3>
              <p>{step.text}</p>
            </Reveal>
          ))}
        </ol>
      </section>

      <section className="al-section dark">
        <div className="al-split">
          <Reveal>
            <span className="al-kicker light">En tu caja</span>
            <h2>Validar un canje toma segundos</h2>
            <ul className="al-checks">
              <li>Celular o tablet, sin instalar sistemas ni comprar equipos.</li>
              <li>Escanea el QR del cliente o escribe su código.</li>
              <li>Sonido y vibración al confirmar, y el producto a entregar en pantalla.</li>
            </ul>
          </Reveal>
          <Reveal delay={0.15}><CajaDemo /></Reveal>
        </div>
      </section>

      {/* PLAN */}
      <section className="al-section alt">
        <Reveal>
          <span className="al-kicker">La propuesta</span>
          <h2>Plan Aliado para {textName}</h2>
        </Reveal>
        <Reveal delay={0.1}>
          <div className="pp-plan">
            <div className="pp-plan-price">
              <BrandMark brand={brand} size={64} />
              <span className="pp-plan-name">Plan Aliado</span>
              <b>$0</b>
              <small>al mes · sin comisión · sin permanencia</small>
            </div>
            <ul>
              {INCLUDED.map((item) => <li key={item}>{item}</li>)}
            </ul>
          </div>
        </Reveal>
      </section>

      {/* FAQ */}
      <section className="al-section">
        <Reveal>
          <span className="al-kicker">Preguntas</span>
          <h2>Lo que suelen preguntarnos</h2>
        </Reveal>
        <div className="al-faq">
          {FAQ.map((f) => (
            <details key={f.q}>
              <summary>{f.q}</summary>
              <p>{f.a}</p>
            </details>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="al-section dark pp-final" id="empezar">
        <Reveal>
          <div className="pp-final-lockup">
            <span className="pp-mm">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/monavi-mark.svg" alt="" />
            </span>
            <span>×</span>
            <BrandMark brand={brand} size={56} />
          </div>
          <h2>Pongamos a {textName} en MonAvi</h2>
          <p className="al-lead">Te ayudamos a armar tu oferta y publicamos tu ficha. Sin costo y sin compromiso.</p>
          <div className="al-hero-actions pp-final-actions">
            <a className="al-btn" href={WHATSAPP_URL} target="_blank" rel="noopener noreferrer">Escríbenos por WhatsApp</a>
            <a className="al-btn ghost" href="/aliados#solicitud">Llenar la solicitud</a>
          </div>
        </Reveal>
      </section>

      <footer className="al-footer">
        <div className="al-footer-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/monavi-mark.svg" alt="" aria-hidden="true" />
          <span>MonAvi · Ordena. Ahorra. Avanza. · Un producto de Maday</span>
        </div>
        <span className="al-footer-links">
          <a href="/legal">Documentos legales</a> · <a href="mailto:hola@maday.app">hola@maday.app</a>
        </span>
      </footer>
    </div>
  );
}
