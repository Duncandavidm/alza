-- Enseñanzas por país: null = para todos; 'PA' solo Panamá; 'CO' solo
-- Colombia. Las lecciones con montos o costumbres locales (décimo tercer
-- mes vs. prima, plazo fijo vs. CDT) tienen su versión para cada país.

alter table public.finance_teachings
  add column if not exists country text check (country in ('PA', 'CO'));

update public.finance_teachings set country = 'PA'
 where country is null and title in (
   'Los gastos hormiga', 'Empieza pequeño, pero empieza',
   'El décimo tercer mes y los bonos', 'Opciones comunes para empezar');

insert into public.finance_teachings (country, step, sort, title, body, ai_note)
select * from (values
  ('CO', 1, 30, 'Los gastos hormiga',
   'Un tinto de $3.000 al día son $90.000 al mes y más de $1.000.000 al año. Los gastos pequeños y repetidos son los que más sorprenden. Identifícalos y decide cuáles valen la pena.',
   'Busca gastos pequeños y repetidos en los movimientos y muestra su total mensual y anual en pesos.'),
  ('CO', 4, 30, 'Empieza pequeño, pero empieza',
   '$20.000 por quincena son $480.000 al año. Lo importante no es el monto, es el hábito. Cuando te suban el sueldo, sube también lo que apartas.',
   NULL),
  ('CO', 6, 20, 'La prima y los ingresos extra',
   'La prima de junio y diciembre, los bonos y los ingresos extra son la forma más rápida de completar tu colchón. Usa al menos la mitad para tu fondo antes de gastarla.',
   'En Colombia menciona la prima de servicios (junio y diciembre) como fuente para el colchón.'),
  ('CO', 7, 40, 'Opciones comunes para empezar',
   'Las opciones más comunes para empezar son los CDT, los fondos de inversión colectiva y los bonos. Antes de elegir, compara plazo, riesgo, comisiones y que la entidad esté vigilada por la Superintendencia Financiera.',
   'Esto es educación general: no digas cuál elegir ni en qué entidad.')
) as seed(country, step, sort, title, body, ai_note)
where not exists (select 1 from public.finance_teachings where country = 'CO');
