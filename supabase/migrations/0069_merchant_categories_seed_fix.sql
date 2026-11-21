-- Las categorias iniciales deben ser las mismas que ofrece la landing de
-- aliados (admin/lib/merchant-categories.ts), para que las solicitudes y
-- los reportes agrupen igual. Se quitan las de 0068 que nadie usa.
delete from public.merchant_categories mc
where mc.name in ('Restaurantes y cafés', 'Supermercados', 'Salud y farmacias', 'Ropa y accesorios')
  and not exists (select 1 from public.partner_merchants pm where pm.category = mc.name);

insert into public.merchant_categories (name, emoji, sort_order) values
  ('Restaurantes y cafeterías', '🍽️', 1),
  ('Supermercados y abarroterías', '🛒', 2),
  ('Farmacias y salud', '💊', 3),
  ('Belleza y cuidado personal', '💅', 4),
  ('Moda y accesorios', '👗', 5),
  ('Tecnología y electrónica', '📱', 6),
  ('Hogar y ferretería', '🏠', 7),
  ('Mascotas', '🐾', 8),
  ('Deportes y bienestar', '🏋️', 9),
  ('Entretenimiento', '🎬', 10),
  ('Educación', '📚', 11),
  ('Servicios', '🧰', 12),
  ('Otro', '🏷️', 99)
on conflict (name) do update set emoji = excluded.emoji, sort_order = excluded.sort_order;
