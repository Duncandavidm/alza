# Seguridad de las Edge Functions

Patron compartido que siguen `generate-insights`, `ask-finances`,
`prioritize-payments`, `verify-apple-receipt`, `parse-voice-transaction` y
`exchange-rate` (duplicado en cada `index.ts` — Supabase despliega cada
funcion de forma aislada, sin un directorio `_shared/` real entre
despliegues hechos via la herramienta MCP, asi que el codigo se repite a
proposito en vez de importarlo).

## 1. El `userId` viene SIEMPRE del JWT, nunca del body

Antes, varias funciones leian `{ userId }` directo del JSON que mandaba el
cliente y lo usaban con la **service role key** (que salta RLS por
diseño) para leer/escribir filas de esa tabla. Un usuario autenticado
podia mandar el `userId` de OTRA persona y leer sus datos financieros o
— en el caso de `verify-apple-receipt` — pisarle la suscripcion.

Como el gateway de Supabase ya verifica la firma del JWT antes de invocar
la funcion (`verify_jwt: true`), `getVerifiedUserId(req)` solo decodifica
el payload del JWT (`Authorization: Bearer <jwt>`) y usa el campo `sub`
(el user id real). El body ya no se usa para identidad, solo para los
demas parametros (pregunta, monto, etc.).

## 2. Rate limiting

`check_and_increment_rate_limit` (funcion de Postgres, migracion
`0013_rate_limiting.sql`) lleva un contador por `(user_id, function_name)`
con ventana deslizante. Cada funcion llama esto antes de hacer trabajo
real y regresa **429** si se paso del limite:

| Funcion | Limite |
|---|---|
| generate-insights | 10 / 10 min |
| ask-finances | 20 / 10 min |
| prioritize-payments | 20 / 10 min |
| verify-apple-receipt | 10 / 10 min |
| parse-voice-transaction | 30 / 10 min |
| exchange-rate | 60 / 10 min |

La tabla `edge_function_rate_limits` no tiene policies (RLS activo, cero
policies = nadie de `anon`/`authenticated` puede leerla ni escribirla
directo); solo la service role key (que usan las Edge Functions) y la
funcion `SECURITY DEFINER` la tocan.

## 3. CORS

Cada funcion responde el preflight `OPTIONS` y manda
`Access-Control-Allow-Headers`/`-Methods`, pero **a proposito NO manda
`Access-Control-Allow-Origin`**. Sin ese header, cualquier navegador
bloquea la peticion cross-origin — asi ninguna pagina web (con la anon
key filtrada o no) puede llamar estas funciones desde el navegador de
alguien mas. Esto no afecta a la app nativa de iOS: CORS es una regla que
cumplen los navegadores, no los clientes HTTP nativos, asi que Alza sigue
llamando las funciones sin problema.

Importante: CORS **no es proteccion contra un atacante que le pega
directo a la API** (curl, Postman, otro servidor) — eso lo cubren el JWT
verificado (punto 1) y el rate limit (punto 2), no CORS.

## 4. Validacion de inputs

Cada funcion valida tipo, rango y longitud de lo que recibe antes de
usarlo (montos: `Number.isFinite`, positivos, con tope; texto libre:
`.trim()` + limite de caracteres; codigos de moneda: regex de 3 letras).
Los textos que entran a un prompt de Claude (pregunta, transcripcion de
voz, notas) tambien se truncan a un maximo razonable — limita el costo de
tokens y la superficie de un intento de "prompt injection".

## 5. Mitigacion de prompt injection

Los prompts que arma cada funcion incluyen una linea explicita diciendole
a Claude que los datos del usuario (perfil, transacciones, preguntas,
notas) son SIEMPRE datos a analizar, nunca instrucciones a seguir — para
que un campo de texto malicioso ("ignora lo anterior y...") no logre
cambiar el comportamiento de la IA. No es una garantia absoluta (ningun
LLM es inmune del todo a esto), pero reduce bastante la superficie.

## Lo que esto NO cubre (y por que)

- **Content Security Policy (CSP)**: es un mecanismo que cumplen los
  navegadores al renderizar HTML/JS de una pagina web. Estas funciones
  regresan JSON puro, nunca HTML, y Alza es una app nativa sin WebView —
  no hay nada que un CSP pudiera restringir aqui.
- **"Que solo mi app pueda llamar al backend"**: no existe una forma de
  lograr esto al 100% solo con headers — cualquiera con una copia valida
  del anon key (publico, esta en el binario de la app) y un JWT de
  usuario real puede llamar la API REST de Supabase o estas funciones
  desde cualquier cliente HTTP. Lo que SI protege son las capas de arriba
  (JWT real, RLS, rate limit). La unica forma de acercarse a "solo mi app
  real" es con App Attest/DeviceCheck de Apple (atestacion criptografica
  de que la peticion viene de una instalacion genuina de la app) — no se
  implemento por el alcance que agrega (verificacion de attestation del
  lado del servidor); si se quiere, es la siguiente pieza de hardening.
