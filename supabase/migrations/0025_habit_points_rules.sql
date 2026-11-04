-- Valores de puntos por cada logro de habitos (Fase 2) — ver
-- award-habit-points. Todo configurable, nada hardcodeado en la Edge
-- Function ni en la app.
insert into public.points_rules (source, key, value) values
  ('habito', 'streak_points_per_week', '20'::jsonb),
  ('habito', 'weekly_budget_points', '15'::jsonb),
  ('habito', 'monthly_budget_points', '30'::jsonb)
on conflict (source, key) do nothing;
