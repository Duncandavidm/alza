import type { Metadata } from "next";
import ApplicationForm from "./ApplicationForm";
import BusinessPreview from "./BusinessPreview";
import CajaDemo from "./CajaDemo";
import Reveal from "./Reveal";

// Landing PUBLICA (sin clave del panel, ver PUBLIC_PATHS en proxy.ts)
// para que los comercios de Panama pidan ser aliados de MonAvi.
export const metadata: Metadata = {
  title: "Comercios aliados — MonAvi",
  description:
    "Lleva clientes nuevos a tu negocio con MonAvi: ofrece un descuento por ser de MonAvi o un premio que se canjea con cashback, y recibe a clientes en tu local. Sin costo de afiliación ni integración.",
};

const STEPS = [
  { title: "Te registras", text: "Llenas el formulario en dos minutos. Te contactamos para conocer tu negocio y preparar tu ficha." },
  { title: "Eliges qué ofreces", text: "Un descuento por ser de MonAvi (10%, 20%…) que cada persona usa las veces que tú decidas, o un premio (un café, un postre, un servicio) que se canjea con cashback." },
  { title: "Te encuentran en la app", text: "Tu negocio aparece con tu logo, la foto del producto y un botón directo a Google Maps." },
  { title: "Validas en caja", text: "El cliente muestra su código. Lo validas desde cualquier celular con tu PIN y le entregas el producto." },
];

const BENEFITS = [
  { icon: "🚶", title: "Clientes que llegan decididos", text: "Quien usa tu descuento o canjea tu premio ya eligió visitarte, y muchas veces compra algo más o vuelve." },
  { icon: "📱", title: "Visibilidad en la app", text: "Tu ficha con logo, fotos y cómo llegar, frente a personas que cuidan su dinero." },
  { icon: "🔔", title: "Avisos que traen gente", text: "Cuando entras a MonAvi avisamos a los usuarios con tu descuento, y cuando a alguien le alcanza para tu premio también le llega una notificación." },
  { icon: "📊", title: "Mides los resultados", text: "Ves cuántas visitas te trajo MonAvi y el ticket promedio de esos clientes." },
  { icon: "🆓", title: "Cero costo", text: "Sin cuota de afiliación, sin mensualidad y sin comisión por venta." },
  { icon: "🔒", title: "Canjes seguros", text: "Cada código es único y no se puede usar dos veces: el de un descuento vence a los 15 minutos y el de un premio a los 7 días. El PIN tiene límite de intentos." },
  { icon: "🎛️", title: "Tú tienes el control", text: "Cambia o pausa tus descuentos y premios cuando quieras, y pon un cupo máximo. Sin contratos largos." },
];

const FAQ = [
  { q: "¿Cuánto cuesta ser aliado?", a: "Nada. No hay cuota de afiliación, mensualidad ni comisión." },
  { q: "¿Qué es un descuento por ser de MonAvi?", a: "Un descuento que ofreces a quienes usan MonAvi, por ejemplo 20% en toda la tienda. Tú eliges cada cuánto lo puede usar cada persona (1 vez por semana, por mes…). Se desbloquea cuando la persona escanea su primera factura y verifica su correo." },
  { q: "¿Quién paga el premio o el descuento?", a: "Tu negocio, como inversión para atraer y fidelizar clientes. MonAvi no reembolsa el producto ni el descuento." },
  { q: "¿Necesito instalar algo o un equipo especial?", a: "No. Solo un celular con navegador para abrir la página de canje y tu PIN." },
  { q: "¿Qué datos del cliente veo?", a: "Su nombre de pila con la inicial del apellido, los últimos 4 dígitos de su teléfono, el código y el producto. Nunca su correo, saldo ni movimientos." },
  { q: "¿Qué pasa si el cliente no usa su código?", a: "Vence solo (a los 15 minutos si es un descuento, a los 7 días si es un premio, y el cashback se le devuelve). Tú no pierdes nada." },
  { q: "¿Puedo hablar con alguien antes de inscribirme?", a: "Claro. Escríbenos por WhatsApp al +507 6738-9720 o a hola@maday.app y te explicamos todo." },
  { q: "¿Cómo ganan cashback los clientes?", a: "Con el 1% de sus facturas electrónicas de Panamá verificadas por la DGI y al invitar a sus amigos. Por eso MonAvi les recuerda pedir siempre su factura fiscal." },
];

const WHATSAPP_URL =
  "https://wa.me/50767389720?text=" +
  encodeURIComponent("Hola, tengo un negocio y quiero ser comercio aliado de MonAvi.");

function WhatsAppIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true">
      <path fill="currentColor" d="M19.05 4.91A9.82 9.82 0 0 0 12.04 2C6.6 2 2.17 6.43 2.17 11.87c0 1.74.46 3.44 1.32 4.94L2.08 22l5.33-1.4a9.86 9.86 0 0 0 4.63 1.18h.01c5.44 0 9.87-4.43 9.87-9.87 0-2.64-1.03-5.12-2.87-7Zm-7.01 15.2h-.01a8.2 8.2 0 0 1-4.18-1.15l-.3-.18-3.16.83.84-3.08-.2-.32a8.2 8.2 0 0 1-1.26-4.37c0-4.53 3.69-8.21 8.23-8.21 2.2 0 4.26.86 5.82 2.41a8.16 8.16 0 0 1 2.4 5.81c0 4.53-3.69 8.22-8.18 8.26Zm4.5-6.15c-.25-.12-1.46-.72-1.69-.8-.23-.08-.39-.12-.56.12-.16.25-.64.8-.78.97-.14.16-.29.18-.53.06-.25-.12-1.04-.38-1.98-1.22-.73-.65-1.23-1.46-1.37-1.7-.14-.25-.02-.38.11-.5.11-.11.25-.29.37-.43.12-.14.16-.25.25-.41.08-.16.04-.31-.02-.43-.06-.12-.56-1.35-.76-1.85-.2-.48-.41-.42-.56-.43h-.48a.92.92 0 0 0-.66.31c-.23.25-.86.84-.86 2.06 0 1.21.88 2.38 1 2.55.12.16 1.74 2.65 4.21 3.72.59.25 1.05.4 1.4.52.59.19 1.13.16 1.55.1.47-.07 1.46-.6 1.66-1.18.21-.58.21-1.07.14-1.18-.06-.1-.22-.16-.47-.29Z" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
      <path fill="currentColor" d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.2-1.7-3-1.9-3.6-2-1.5-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.5-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8s2 .8 3.3.8c1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.8-1.1-2.8-4.2zM13.9 5.1c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.3 2-1.1 3.1 1.1.1 2.3-.6 3-1.5z" />
    </svg>
  );
}

export default function AliadosPage() {
  return (
    <div className="landing al">
      <header className="al-nav">
        <span className="al-logo">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/monavi-mark.svg" alt="" aria-hidden="true" />
          MonAvi <em>Aliados</em>
        </span>
        <a href="#solicitud" className="al-btn small">Quiero ser aliado</a>
      </header>

      {/* HERO */}
      <section className="al-hero">
        <div className="al-bills" aria-hidden="true">
          {Array.from({ length: 12 }).map((_, i) => (
            <span key={i} className="al-bill" style={{ ["--i" as string]: i } as React.CSSProperties}>$</span>
          ))}
        </div>
        <div className="al-hero-inner">
          <Reveal className="al-hero-text">
            <span className="al-eyebrow">Programa de comercios aliados · Panamá</span>
            <h1>
              Convierte el ahorro de la gente en <span>clientes para tu negocio</span>
            </h1>
            <p>
              En MonAvi, las personas ordenan su dinero y ganan cashback con sus facturas. Sé el lugar donde lo canjean
              y donde encuentran sus descuentos.
            </p>
            <div className="al-hero-actions">
              <a href="#solicitud" className="al-btn">Quiero ser aliado</a>
              <a href="#simulador" className="al-btn ghost">Ver cómo se vería mi negocio</a>
            </div>
            <div className="al-stats">
              <div><b>$0</b><span>de afiliación</span></div>
              <div><b>1 celular</b><span>para validar</span></div>
              <div><b>2 min</b><span>para registrarte</span></div>
            </div>
          </Reveal>
          <div className="al-hero-phones" aria-hidden="true">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className="p1" src="/aliados/resumen.webp" alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className="p2" src="/aliados/hoy.webp" alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className="p3" src="/aliados/cashback.webp" alt="" />
          </div>
        </div>
      </section>

      {/* SIMULADOR */}
      <section className="al-section" id="simulador">
        <Reveal>
          <span className="al-kicker">Pruébalo</span>
          <h2>Así se vería tu negocio en MonAvi</h2>
          <p className="al-lead">Escribe el nombre de tu negocio y el descuento o premio que darías. Mira cómo lo verían tus futuros clientes.</p>
        </Reveal>
        <Reveal delay={0.1}>
          <BusinessPreview />
        </Reveal>
      </section>

      {/* LA APP */}
      <section className="al-section alt">
        <Reveal>
          <span className="al-kicker">La app</span>
          <h2>Tus futuros clientes usan MonAvi todos los días</h2>
          <p className="al-lead">Es su app para anotar gastos, ver en qué se va su plata y ganar recompensas. Estas son pantallas reales.</p>
        </Reveal>
        <div className="al-screens">
          {[
            { img: "hoy", title: "Anotan su día", text: "Gastos, ingresos y ahorro en segundos, hasta con su voz." },
            { img: "resumen", title: "Entienden su mes", text: "En qué se fue la plata, por categorías." },
            { img: "cashback", title: "Ganan recompensas", text: "Cashback por sus facturas y descuentos en comercios como el tuyo." },
          ].map((s, i) => (
            <Reveal key={s.img} delay={i * 0.12} className="al-screen">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`/aliados/${s.img}.webp`} alt={`Pantalla de MonAvi: ${s.title}`} loading="lazy" />
              <h3>{s.title}</h3>
              <p>{s.text}</p>
            </Reveal>
          ))}
        </div>
      </section>

      {/* COMO FUNCIONA */}
      <section className="al-section" id="como-funciona">
        <Reveal>
          <span className="al-kicker">Cómo funciona</span>
          <h2>De la app a tu caja, en 4 pasos</h2>
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

      {/* CAJA */}
      <section className="al-section dark">
        <div className="al-split">
          <Reveal>
            <span className="al-kicker light">En tu caja</span>
            <h2>Validar un canje toma segundos</h2>
            <ul className="al-checks">
              <li>Desde cualquier celular, sin instalar nada.</li>
              <li>El cliente te muestra su código o su QR.</li>
              <li>Lo escribes o lo escaneas, con el PIN de tu negocio.</li>
              <li>La pantalla te confirma qué producto entregar.</li>
            </ul>
          </Reveal>
          <Reveal delay={0.15}>
            <CajaDemo />
          </Reveal>
        </div>
      </section>

      {/* BENEFICIOS */}
      <section className="al-section">
        <Reveal>
          <span className="al-kicker">Beneficios</span>
          <h2>Por qué ser aliado de MonAvi</h2>
        </Reveal>
        <div className="al-benefits">
          {BENEFITS.map((b, i) => (
            <Reveal key={b.title} delay={(i % 3) * 0.08} className="al-benefit">
              <span className="al-benefit-icon" aria-hidden="true">{b.icon}</span>
              <h3>{b.title}</h3>
              <p>{b.text}</p>
            </Reveal>
          ))}
        </div>
      </section>

      {/* FAQ */}
      <section className="al-section alt">
        <Reveal>
          <span className="al-kicker">Preguntas frecuentes</span>
          <h2>Lo que nos suelen preguntar</h2>
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

      {/* FORMULARIO */}
      <section className="al-section" id="solicitud">
        <Reveal>
          <span className="al-kicker">Súmate</span>
          <h2>Solicita ser comercio aliado</h2>
          <p className="al-lead">Cuéntanos de tu negocio. Te respondemos en pocos días hábiles, sin compromiso.</p>
          <a className="al-wa-inline" href={WHATSAPP_URL} target="_blank" rel="noopener noreferrer">
            <WhatsAppIcon size={20} /> ¿Prefieres hablar? Escríbenos por WhatsApp: +507 6738-9720
          </a>
        </Reveal>
        <Reveal delay={0.1}>
          <ApplicationForm />
        </Reveal>
      </section>

      <footer className="al-footer">
        <div className="al-footer-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/monavi-mark.svg" alt="" aria-hidden="true" />
          <span>MonAvi · Ordena. Ahorra. Avanza.</span>
        </div>
        <a className="al-store" href="https://apps.apple.com/app/monavi/id6830965654">
          <AppleIcon /> MonAvi en la App Store
        </a>
        <span className="al-footer-links">
          <a href={WHATSAPP_URL} target="_blank" rel="noopener noreferrer">WhatsApp +507 6738-9720</a> ·{" "}
          <a href="/legal">Documentos legales</a> · <a href="/support">Soporte</a> · <a href="mailto:hola@maday.app">hola@maday.app</a>
        </span>
      </footer>

      <a className="al-wa-float" href={WHATSAPP_URL} target="_blank" rel="noopener noreferrer" aria-label="Escríbenos por WhatsApp">
        <WhatsAppIcon size={30} />
        <span>¿Dudas? Escríbenos</span>
      </a>
    </div>
  );
}
