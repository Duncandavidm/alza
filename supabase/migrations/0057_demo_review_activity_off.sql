-- Se apagan los movimientos automaticos de la cuenta de revision (0054):
-- mejor que el revisor vea solo datos de ejemplo fijos y lo que el mismo
-- anote. Los datos de ejemplo ya cargados se quedan.
select cron.unschedule(jobname) from cron.job where jobname like 'demo-review-%';
drop function if exists public.demo_review_tick(int);
drop function if exists public.demo_review_insert(timestamptz, text, numeric, text, text, text);
