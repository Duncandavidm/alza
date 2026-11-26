-- Método MonAvi: plan de 7 pasos + base de enseñanzas.
--
-- finance_teachings guarda las enseñanzas del método. Se administran desde
-- el panel (Asesoría > Enseñanzas): cada una puede mostrarse en la app como
-- lección (show_in_app) y/o alimentar a la IA (use_in_ai), que la aplica a
-- los números de cada persona. step = paso del plan (1-7) o null si es
-- general. Texto propio de MonAvi (no copia de libros).

create table if not exists public.finance_teachings (
  id uuid primary key default gen_random_uuid(),
  step smallint check (step between 1 and 7),
  title text not null check (char_length(title) between 3 and 120),
  body text not null check (char_length(body) between 10 and 1500),
  ai_note text check (ai_note is null or char_length(ai_note) <= 800),
  source text check (source is null or char_length(source) <= 200),
  show_in_app boolean not null default true,
  use_in_ai boolean not null default true,
  active boolean not null default true,
  sort integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists finance_teachings_step_idx on public.finance_teachings (step, sort) where active;

alter table public.finance_teachings enable row level security;

-- La app solo lee las lecciones activas que se muestran; la IA (service
-- role) y el panel leen todo.
drop policy if exists finance_teachings_read on public.finance_teachings;
create policy finance_teachings_read on public.finance_teachings
  for select to authenticated using (active and show_in_app);

drop trigger if exists finance_teachings_set_updated_at on public.finance_teachings;
create trigger finance_teachings_set_updated_at
  before update on public.finance_teachings
  for each row execute procedure public.set_updated_at();

-- Enseñanzas iniciales del Método MonAvi (solo si la tabla está vacía).
insert into public.finance_teachings (step, sort, title, body, ai_note)
select * from (values
  -- Paso 1: Conoce tu foto
  (1, 10, 'Tu número más importante',
   'Tu patrimonio es lo que tienes menos lo que debes. No importa si hoy es negativo: lo importante es que cada mes suba un poco. Míralo una vez al mes, no todos los días.',
   'Calcula el patrimonio (cuentas menos deudas) y di si subió o bajó respecto al mes anterior cuando sea útil.'),
  (1, 20, 'Un mes anotando todo',
   'Durante un mes anota cada gasto, por pequeño que sea, sin juzgarte. No es para sentirte mal: es para ver la verdad. Con un mes de datos ya sabes en qué se te va la plata.',
   NULL),
  (1, 30, 'Los gastos hormiga',
   'Un café de $2.50 al día son $75 al mes y $900 al año. Los gastos pequeños y repetidos son los que más sorprenden. Identifícalos y decide cuáles valen la pena.',
   'Busca gastos pequeños y repetidos en los movimientos y muestra su total mensual y anual.'),
  -- Paso 2: Dale un trabajo a cada dólar
  (2, 10, 'El presupuesto te da libertad',
   'Un presupuesto no es una cárcel: es decidir antes, con calma, en qué vas a usar tu dinero. Así gastas sin culpa en lo que sí está planeado.',
   NULL),
  (2, 20, 'La regla 50/30/20, a tu medida',
   'Una guía para repartir tu ingreso: 50% para necesidades (vivienda, comida, transporte), 30% para gustos y 20% para ahorrar o pagar deudas. Si hoy no te alcanza, empieza con 5% de ahorro y súbelo poco a poco.',
   'Compara el reparto real de la persona contra 50/30/20 y propone un ajuste concreto en dólares, sin exigir llegar de golpe.'),
  (2, 30, 'Págate primero',
   'El día que cobras la quincena, aparta primero tu ahorro y después vive con el resto. Si esperas a ver qué sobra a fin de mes, casi nunca sobra nada.',
   'Si la persona no ahorra, sugiere apartar un monto fijo el día de cobro.'),
  -- Paso 3: Control constante
  (3, 10, 'Cierra el día en un minuto',
   'Antes de dormir revisa lo que gastaste hoy. Un minuto al día evita las sorpresas de fin de mes.',
   NULL),
  (3, 20, 'Revisión de quincena',
   'Cada quincena compara lo que gastaste con lo que presupuestaste. Si una categoría se pasó, ajusta la siguiente quincena en vez de rendirte.',
   NULL),
  (3, 30, 'La regla de las 48 horas',
   'Antes de una compra que no tenías planeada, espera 48 horas. Si después de dos días todavía la quieres y está en tu presupuesto, cómprala tranquilo.',
   NULL),
  -- Paso 4: Colchón inicial
  (4, 10, 'Primero un colchón pequeño',
   'Antes de atacar deudas o invertir, junta al menos un mes de gastos. Así un imprevisto (una llanta, una medicina) no se convierte en una deuda nueva.',
   'Si la persona no tiene al menos un mes de gastos ahorrado, esa es la prioridad antes de invertir o hacer pagos extra a deudas que no estén en mora.'),
  (4, 20, 'Dónde guardar tu fondo de emergencia',
   'Guárdalo en una cuenta de ahorro separada, que puedas usar el mismo día y que no veas a diario. No es para invertir ni para gustos: es tu seguro.',
   NULL),
  (4, 30, 'Empieza pequeño, pero empieza',
   '$20 por quincena son $480 al año. Lo importante no es el monto, es el hábito. Cuando te suban el sueldo, sube también lo que apartas.',
   NULL),
  -- Paso 5: Adiós deudas caras
  (5, 10, 'El método avalancha',
   'Paga el mínimo de todas tus deudas y todo lo extra que puedas a la que tiene la tasa más alta. Cuando la termines, pasa ese dinero a la siguiente. Es la forma más barata de salir de deudas.',
   'Ordena las deudas por tasa de interés y di exactamente a cuál mandar el dinero extra.'),
  (5, 20, 'La tasa anual real',
   'Un 3% mensual parece poco, pero son más de 36% al año. Ninguna inversión segura te paga eso, por eso pagar una tarjeta cara es la mejor "inversión" que puedes hacer.',
   'Convierte siempre las tasas mensuales a anuales (multiplica por 12) al explicarlas.'),
  (5, 30, 'La tarjeta no es parte del sueldo',
   'Usa la tarjeta de crédito solo para lo que ya tienes en tu presupuesto y págala completa cada mes. Si solo pagas el mínimo, pagas intereses sobre intereses.',
   NULL),
  -- Paso 6: Colchón completo
  (6, 10, '¿Cuánto debe tener tu colchón?',
   'Entre 3 y 6 meses de tus gastos. Si tus ingresos varían, trabajas por tu cuenta o tienes personas que dependen de ti, apunta a 6 meses.',
   'Usa 6 meses como meta si la persona tiene ingresos variables o dependientes; si no, entre 3 y 6.'),
  (6, 20, 'El décimo tercer mes y los bonos',
   'El décimo tercer mes, los bonos y los ingresos extra son la forma más rápida de completar tu colchón. Usa al menos la mitad para tu fondo antes de gastarlos.',
   NULL),
  (6, 30, 'Protege lo que ganas',
   'Un colchón completo y un seguro básico protegen tu ingreso. Un problema de salud sin protección puede borrar años de ahorro.',
   NULL),
  -- Paso 7: Pon tu dinero a trabajar
  (7, 10, 'Antes de invertir',
   'Invierte solo cuando tengas tu fondo de emergencia, no tengas deudas caras y gastes menos de lo que ganas. Si no, primero termina esos pasos: es lo que más te hace ganar.',
   'Antes de hablar de inversiones revisa: fondo de emergencia de al menos 3 meses, sin deudas caras ni en mora, y gasto menor que el ingreso. Si falta algo, di qué falta primero.'),
  (7, 20, 'El interés compuesto',
   'Cuando tu dinero gana intereses y esos intereses también ganan, el tiempo hace el trabajo pesado. Empezar temprano con poco suele ganarle a empezar tarde con mucho.',
   NULL),
  (7, 30, 'Riesgo, plazo y diversificación',
   'A mayor rendimiento, mayor riesgo. No pongas todo en un solo lugar, invierte solo dinero que no vas a necesitar pronto y desconfía de quien te prometa ganancias altas y seguras.',
   'Nunca recomiendes un producto, acción o entidad específica ni prometas rentabilidad. Explica conceptos y opciones en general.'),
  (7, 40, 'Opciones comunes para empezar',
   'Las opciones más comunes para empezar son los depósitos a plazo fijo, los bonos y los fondos de inversión. Antes de elegir, compara plazo, riesgo, comisiones y que la entidad esté regulada.',
   'Esto es educación general: no digas cuál elegir ni en qué entidad.')
) as seed(step, sort, title, body, ai_note)
where not exists (select 1 from public.finance_teachings);
