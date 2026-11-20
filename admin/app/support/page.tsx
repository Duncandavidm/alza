import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Soporte — MonAvi",
};

export default function SupportPage() {
  return (
    <div className="page" style={{ maxWidth: 760 }}>
      <h1>Soporte de MonAvi</h1>
      <p className="text-dim">
        ¿Tienes un problema, una pregunta, o una idea para MonAvi? Escríbenos a{" "}
        <a href="mailto:hola@maday.app">hola@maday.app</a> y te respondemos lo antes posible. También
        puedes escribirnos directo desde la app en Ajustes.
      </p>

      <div className="card">
        <h3>Preguntas frecuentes</h3>

        <div style={{ marginBottom: 18 }}>
          <strong>¿Cómo cancelo mi suscripción?</strong>
          <p className="text-dim">
            Las suscripciones de MonAvi las administra Apple. En tu iPhone: Ajustes del sistema → tu nombre →
            Suscripciones → MonAvi → Cancelar suscripción. También puedes llegar ahí desde dentro de la app en
            Ajustes → Suscripción → &quot;Administrar suscripción&quot;.
          </p>
        </div>

        <div style={{ marginBottom: 18 }}>
          <strong>Cancelé pero todavía tengo acceso, ¿es un error?</strong>
          <p className="text-dim">
            No — al cancelar, Apple no corta el acceso de inmediato. Sigues teniendo el plan Pro hasta que termina
            el periodo que ya pagaste. MonAvi te avisa en la pantalla principal y en Ajustes cuándo termina.
          </p>
        </div>

        <div style={{ marginBottom: 18 }}>
          <strong>Cambié de teléfono, ¿cómo recupero mi suscripción?</strong>
          <p className="text-dim">
            Inicia sesión con la misma cuenta y usa &quot;Restaurar compras&quot; en la pantalla de suscripción —
            tu plan activo se vincula a tu cuenta de MonAvi, no al teléfono.
          </p>
        </div>

        <div style={{ marginBottom: 18 }}>
          <strong>¿Cómo elimino mi cuenta y mis datos?</strong>
          <p className="text-dim">
            Escríbenos a <a href="mailto:hola@maday.app">hola@maday.app</a> pidiendo la eliminación de tu
            cuenta y la procesamos — se borra toda tu información financiera de nuestros servidores. Esta acción
            no se puede deshacer.
          </p>
        </div>

        <div style={{ marginBottom: 18 }}>
          <strong>¿Qué es &quot;Facturas que suman&quot;?</strong>
          <p className="text-dim">
            Escaneas el código QR de tu factura electrónica y, una vez que la verificamos, ganas 1% de
            cashback. Cada factura solo se puede registrar una vez en toda la app.
          </p>
        </div>

        <div>
          <strong>Encontré un error o algo no funciona como esperaba</strong>
          <p className="text-dim">
            Cuéntanos qué pasó (qué pantalla, qué esperabas que pasara, qué pasó en realidad) a{" "}
            <a href="mailto:hola@maday.app">hola@maday.app</a> — entre más detalle, más rápido lo
            resolvemos.
          </p>
        </div>
      </div>

      <div className="card">
        <h3>Política de privacidad</h3>
        <p className="text-dim">
          Puedes leerla completa en <a href="/privacy">monavi.maday.app/privacy</a>.
        </p>
      </div>
    </div>
  );
}
