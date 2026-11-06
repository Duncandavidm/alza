import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Política de Privacidad — MonAvi",
};

const UPDATED_AT = "6 de noviembre de 2026";

export default function PrivacyPage() {
  return (
    <div className="page" style={{ maxWidth: 760 }}>
      <h1>Política de Privacidad de MonAvi</h1>
      <p className="text-dim">Última actualización: {UPDATED_AT}</p>

      <div className="card">
        <h3>1. Quién es responsable de tus datos</h3>
        <p>
          MonAvi es una app desarrollada y operada por David Muñoz Duncan. Si tienes alguna pregunta sobre esta
          política o sobre tus datos, escribe a{" "}
          <a href="mailto:soporte@monavi.app">soporte@monavi.app</a>.
        </p>
      </div>

      <div className="card">
        <h3>2. Qué datos recopilamos</h3>
        <ul>
          <li>
            <strong>Cuenta:</strong> tu correo electrónico (si inicias sesión con correo/contraseña) o un
            identificador que Apple nos entrega al iniciar sesión con &quot;Iniciar sesión con Apple&quot; — en ese
            caso, si eliges ocultar tu correo real, nosotros nunca lo vemos.
          </li>
          <li>
            <strong>Información financiera que tú ingresas:</strong> cuentas, movimientos (ingresos, gastos,
            transferencias), presupuestos, deudas, metas de ahorro, facturas y recibos que registras en la app.
            Esto es el propósito central de MonAvi — sin estos datos la app no puede funcionar.
          </li>
          <li>
            <strong>Voz (opcional):</strong> si usas &quot;anotar por voz&quot;, tu dispositivo transcribe el
            audio a texto (en el dispositivo, cuando es compatible). Solo el texto ya transcrito se envía a
            nuestro servidor para interpretar el movimiento — nunca guardamos ni transmitimos la grabación de
            audio.
          </li>
          <li>
            <strong>Facturas que escaneas (opcional):</strong> si usas &quot;Facturas que suman&quot;, el código
            único (CUFE) de tus facturas electrónicas y, una vez que la DGI de Panamá las confirma, los datos
            públicos de esa factura: el comercio que la emitió, la fecha y hora de la compra, el monto, la forma de
            pago (por ejemplo, &quot;tarjeta de crédito&quot; o &quot;efectivo&quot;, nunca el número de tu
            tarjeta) y el detalle de productos comprados.
          </li>
          <li>
            <strong>Puntos y canjes:</strong> los puntos que ganas y los productos que canjeas en comercios
            aliados (qué producto, en qué comercio, el código de canje y si ya se entregó).
          </li>
          <li>
            <strong>Perfil (opcional):</strong> tu edad, género y otros datos que decidas darnos en el estudio
            inicial (estado civil, dependientes, ocupación, metas). Puedes dejarlos en blanco o cambiarlos en
            Ajustes &gt; Mi perfil.
          </li>
          <li>
            <strong>Notificaciones:</strong> si las permites, un identificador de tu dispositivo que Apple nos
            entrega para poder enviarte avisos (por ejemplo, &quot;sumaste puntos&quot;). Se borra al cerrar
            sesión.
          </li>
          <li>
            <strong>Soporte y sugerencias:</strong> lo que nos escribes directamente (correo de soporte, buzón de
            sugerencias dentro de la app).
          </li>
          <li>
            <strong>Compras:</strong> el estado de tu suscripción (activa, vencida, qué plan) — las compras en sí
            las procesa Apple; nosotros solo recibimos la confirmación de que ocurrieron.
          </li>
        </ul>
        <p>No recopilamos tu ubicación, contactos, ni datos de salud.</p>
      </div>

      <div className="card">
        <h3>3. Para qué usamos tus datos</h3>
        <ul>
          <li>Para que la app funcione: mostrar tus cuentas, movimientos, presupuestos, etc.</li>
          <li>
            Para generar los insights y respuestas de IA que pides dentro de la app (por ejemplo,
            &quot;¿cuánto gasté en comida este mes?&quot; o el consejo de qué pagar primero).
          </li>
          <li>Para verificar y acreditar tus puntos, y para gestionar tus canjes en comercios aliados.</li>
          <li>Para enviarte recordatorios y avisos que tú activas (pagos, puntos sumados).</li>
          <li>
            Para elaborar estudios de mercado con datos <strong>anónimos y agregados</strong>, como se explica en
            la sección 5.
          </li>
          <li>Para darte soporte cuando nos escribes.</li>
        </ul>
        <p>
          Nunca vendemos tus datos personales ni los usamos para mostrarte publicidad de terceros.
        </p>
      </div>

      <div className="card">
        <h3>4. Con quién compartimos datos</h3>
        <p>No vendemos tus datos. Los compartimos únicamente con los proveedores que necesitamos para operar:</p>
        <ul>
          <li>
            <strong>Supabase</strong> — aloja nuestra base de datos y autenticación. Tiene acceso técnico a los
            datos como cualquier proveedor de infraestructura.
          </li>
          <li>
            <strong>Anthropic</strong> — procesa la información financiera relevante que tú pides analizar
            (insights, preguntas, el consejo de qué pagar primero, la interpretación de un movimiento dictado por
            voz) únicamente para generar esa respuesta. No la usa para entrenar sus modelos con tus datos
            identificables, según su política de API comercial.
          </li>
          <li>
            <strong>Apple</strong> — procesa el inicio de sesión (si usas &quot;Iniciar sesión con Apple&quot;) y
            las compras dentro de la app.
          </li>
          <li>
            <strong>Apple (notificaciones)</strong> — entrega los avisos a tu dispositivo. Solo recibe el texto del
            aviso y el identificador del dispositivo.
          </li>
          <li>
            <strong>El comercio aliado donde canjeas</strong> — cuando muestras tu código de canje en caja, el
            comercio ve solo el código y el producto canjeado. No ve tu nombre, tu correo ni tus movimientos.
          </li>
        </ul>
      </div>

      <div className="card">
        <h3>5. Estudios de mercado con datos anónimos</h3>
        <p>
          Con la información de las facturas verificadas y de los movimientos registrados en MonAvi elaboramos
          estadísticas agregadas sobre hábitos de consumo: por ejemplo, los medios de pago más usados, las
          categorías y productos más comprados, los horarios y días de mayor compra, el ticket promedio, o cómo
          se distribuyen estas cifras por rango de edad y género. Podemos compartir estos informes con los
          comercios aliados y usarlos para mejorar MonAvi.
        </p>
        <ul>
          <li>
            Los informes <strong>nunca incluyen datos que te identifiquen</strong>: ni tu nombre, ni tu correo, ni
            tus movimientos individuales. Solo muestran totales, promedios y porcentajes de grupos de personas.
          </li>
          <li>
            Ningún grupo de <strong>menos de 5 personas</strong> aparece en un informe, para que no se pueda
            deducir la compra de una persona en particular.
          </li>
          <li>
            Si prefieres que tus datos no se incluyan en estas estadísticas, escríbenos a{" "}
            <a href="mailto:soporte@monavi.app">soporte@monavi.app</a> y los excluiremos.
          </li>
        </ul>
      </div>

      <div className="card">
        <h3>6. Seguridad</h3>
        <p>
          Tu sesión se guarda cifrada en el Keychain de tu dispositivo (nunca en texto plano). Cada usuario solo
          puede leer y modificar sus propios datos — está impuesto a nivel de base de datos (Row Level Security),
          no solo en la app. Donde aplica, ofrecemos verificación en dos pasos (Ajustes &gt; Seguridad).
        </p>
      </div>

      <div className="card">
        <h3>7. Tus derechos</h3>
        <p>
          Puedes pedirnos en cualquier momento, escribiendo a{" "}
          <a href="mailto:soporte@monavi.app">soporte@monavi.app</a>:
        </p>
        <ul>
          <li>Una copia de los datos que tenemos sobre ti.</li>
          <li>La corrección de datos incorrectos.</li>
          <li>La eliminación completa de tu cuenta y tus datos (también puedes hacerlo tú en Ajustes &gt; Eliminar cuenta).</li>
          <li>Que tus datos no se incluyan en los estudios de mercado anónimos.</li>
        </ul>
        <p>
          Respondemos estas solicitudes en un plazo razonable, generalmente dentro de 30 días, conforme a la Ley
          81 de 2019 de Protección de Datos Personales de Panamá.
        </p>
      </div>

      <div className="card">
        <h3>8. Menores de edad</h3>
        <p>MonAvi no está dirigida a menores de 13 años y no recopilamos a sabiendas datos de menores de esa edad.</p>
      </div>

      <div className="card">
        <h3>9. Cambios a esta política</h3>
        <p>
          Si hacemos cambios importantes, lo indicaremos actualizando la fecha al inicio de esta página y, cuando
          corresponda, avisando dentro de la app.
        </p>
      </div>
    </div>
  );
}
