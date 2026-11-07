import type { Metadata } from "next";
import ApplicationForm from "./ApplicationForm";

// Landing PUBLICA (sin clave del panel, ver PUBLIC_PATHS en proxy.ts)
// para que los comercios de Panama pidan ser aliados de MonAvi.
export const metadata: Metadata = {
  title: "Comercios aliados — MonAvi",
  description:
    "Lleva clientes nuevos a tu negocio con MonAvi: publica un producto canjeable y recibe a clientes que canjean sus puntos en tu local. Sin costo de integración.",
};

const STEPS = [
  {
    title: "Te registras",
    text: "Llena el formulario en dos minutos. Te contactamos para conocer tu negocio y preparar tu ficha en la app.",
  },
  {
    title: "Publicas un producto canjeable",
    text: "Eliges qué ofreces a cambio de puntos: un café, un postre, un servicio. Nosotros lo mostramos con foto, tu logo y cómo llegar.",
  },
  {
    title: "Los clientes de MonAvi te visitan",
    text: "Las personas que acumulan puntos con sus facturas van a tu local a canjearlos, y muchas vuelven a comprar.",
  },
];

const BENEFITS = [
  {
    icon: "people",
    title: "Clientes nuevos y recurrentes",
    text: "Personas que ya compran en Panamá y buscan dónde usar sus puntos llegan a tu puerta, y regresan.",
  },
  {
    icon: "phone",
    title: "Visibilidad en la app",
    text: "Tu negocio aparece con tu logo, la foto de tu producto y un botón directo a Google Maps.",
  },
  {
    icon: "chart",
    title: "Reportes anónimos de tus clientes",
    text: "Conoce horarios, ticket promedio, edades y hábitos de compra de tu clientela, siempre agregados y sin datos personales.",
  },
  {
    icon: "code",
    title: "Sin costo de integración",
    text: "No instalas nada: el cliente muestra un código en caja y listo. Sin terminales, sin sistemas nuevos.",
  },
];

export default function AliadosPage() {
  return (
    <div className="landing">
      <header className="landing-nav">
        <span className="landing-logo">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="landing-logo-mark" src="/monavi-mark.svg" alt="" aria-hidden="true" />
          MonAvi
        </span>
        <a href="#solicitud" className="landing-nav-cta">
          Quiero ser aliado
        </a>
      </header>

      <section className="landing-hero">
        <div className="landing-hero-text">
          <span className="landing-eyebrow">Programa de comercios aliados · Panamá</span>
          <h1>Lleva clientes nuevos a tu negocio con MonAvi</h1>
          <p>
            MonAvi es la app de finanzas personales donde las personas en Panamá ganan puntos escaneando sus facturas
            electrónicas de la DGI. Conviértete en aliado y deja que vengan a canjearlos en tu local.
          </p>
          <div className="landing-hero-actions">
            <a href="#solicitud" className="landing-button">
              Quiero ser aliado
            </a>
            <a href="#como-funciona" className="landing-button ghost">
              Cómo funciona
            </a>
          </div>
        </div>

        <div className="landing-phone" aria-hidden="true">
          <div className="landing-phone-card">
            <div className="landing-phone-header">
              <span className="landing-phone-logo">T</span>
              <strong>Tu negocio</strong>
            </div>
            <div className="landing-phone-photo">
              <svg viewBox="0 0 64 48" width="72" height="54" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round">
                <path d="M14 18h30v14a10 10 0 0 1-10 10H24a10 10 0 0 1-10-10z" />
                <path d="M44 22h4a6 6 0 0 1 0 12h-4" />
                <path d="M22 6c0 4 4 4 4 8M30 6c0 4 4 4 4 8" />
              </svg>
            </div>
            <div className="landing-phone-row">
              <span>Café latte grande</span>
              <span className="landing-pill">800 pts</span>
            </div>
            <div className="landing-phone-buttons">
              <span className="outline">Cómo llegar</span>
              <span className="filled">Canjear</span>
            </div>
          </div>
        </div>
      </section>

      <section className="landing-section" id="como-funciona">
        <h2>Cómo funciona</h2>
        <ol className="landing-steps">
          {STEPS.map((step, index) => (
            <li key={step.title}>
              <span className="landing-step-number">{index + 1}</span>
              <h3>{step.title}</h3>
              <p>{step.text}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="landing-section alt">
        <h2>Beneficios para tu negocio</h2>
        <div className="landing-benefits">
          {BENEFITS.map((benefit) => (
            <div key={benefit.title} className="landing-benefit">
              <span className="landing-benefit-icon" aria-hidden="true">
                <BenefitIcon name={benefit.icon} />
              </span>
              <h3>{benefit.title}</h3>
              <p>{benefit.text}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="landing-section" id="solicitud">
        <h2>Solicita ser comercio aliado</h2>
        <p className="landing-lead">Cuéntanos de tu negocio. Te respondemos en pocos días hábiles, sin compromiso.</p>
        <ApplicationForm />
      </section>

      <footer className="landing-footer">
        <span>© {new Date().getFullYear()} MonAvi · Panamá</span>
        <span>
          <a href="/privacy">Privacidad</a> · <a href="/support">Soporte</a> ·{" "}
          <a href="mailto:hola@maday.app">hola@maday.app</a>
        </span>
      </footer>
    </div>
  );
}

function BenefitIcon({ name }: { name: string }) {
  const common = {
    viewBox: "0 0 24 24",
    width: 26,
    height: 26,
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  };
  switch (name) {
    case "people":
      return (
        <svg {...common}>
          <circle cx="9" cy="8" r="3.5" />
          <path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
          <circle cx="17" cy="9" r="2.5" />
          <path d="M16 14.2a5 5 0 0 1 5.5 5.8" />
        </svg>
      );
    case "phone":
      return (
        <svg {...common}>
          <rect x="6" y="2.5" width="12" height="19" rx="2.5" />
          <path d="M10.5 18h3" />
        </svg>
      );
    case "chart":
      return (
        <svg {...common}>
          <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
        </svg>
      );
    default:
      return (
        <svg {...common}>
          <rect x="3" y="5" width="18" height="14" rx="2" />
          <path d="M7 9v6M10 9v6M13 9v6M17 9v6" />
        </svg>
      );
  }
}
