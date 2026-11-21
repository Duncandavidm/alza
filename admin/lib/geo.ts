import "server-only";

export type Coordinates = { latitude: number; longitude: number };

function valid(lat: number, lng: number): Coordinates | null {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  if (lat === 0 && lng === 0) return null;
  return { latitude: Math.round(lat * 1e6) / 1e6, longitude: Math.round(lng * 1e6) / 1e6 };
}

/// "9.0123, -79.5123" (lo que copia Google Maps al tocar el punto).
export function parseCoordinates(text: string): Coordinates | null {
  const match = text.trim().match(/^(-?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$/);
  return match ? valid(Number(match[1]), Number(match[2])) : null;
}

/// Coordenadas dentro de un enlace largo de Google Maps. El punto exacto
/// del lugar (!3d lat !4d lng) gana sobre el centro del mapa (@lat,lng).
export function coordinatesFromMapsUrl(url: string): Coordinates | null {
  let decoded = url;
  try {
    decoded = decodeURIComponent(url);
  } catch {
    // se usa tal cual
  }
  const place = decoded.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (place) return valid(Number(place[1]), Number(place[2]));
  const center = decoded.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (center) return valid(Number(center[1]), Number(center[2]));
  const query = decoded.match(/[?&](?:q|ll|query|destination|center)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/);
  if (query) return valid(Number(query[1]), Number(query[2]));
  return null;
}

/// Solo se siguen enlaces de Google (evita usar el panel para pedirle
/// cosas a otros servidores).
function isGoogleMapsHost(url: URL): boolean {
  const host = url.hostname.toLowerCase();
  return (
    host === "maps.app.goo.gl" ||
    host === "goo.gl" ||
    host === "g.co" ||
    host === "maps.google.com" ||
    /^(www\.)?google\.[a-z.]{2,6}$/.test(host)
  );
}

/// Saca la ubicacion de un enlace de Google Maps. Los cortos
/// (maps.app.goo.gl/...) redirigen al enlace largo, que trae las
/// coordenadas: se siguen hasta 5 redirecciones con un tope de 6 s.
export async function resolveMapsLocation(rawUrl: string): Promise<Coordinates | null> {
  const direct = coordinatesFromMapsUrl(rawUrl);
  if (direct) return direct;

  let current: URL;
  try {
    current = new URL(rawUrl);
  } catch {
    return null;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    for (let hop = 0; hop < 5; hop++) {
      if (current.protocol !== "https:" || !isGoogleMapsHost(current)) return null;
      const response = await fetch(current, {
        redirect: "manual",
        signal: controller.signal,
        headers: { "user-agent": "Mozilla/5.0 (MonAvi panel)" },
        cache: "no-store",
      });
      const location = response.headers.get("location");
      if (location) {
        const next = new URL(location, current);
        const found = coordinatesFromMapsUrl(next.toString());
        if (found) return found;
        current = next;
        continue;
      }
      if (response.ok) {
        // A veces la pagina final trae el punto en su HTML.
        const html = (await response.text()).slice(0, 400_000);
        return coordinatesFromMapsUrl(html);
      }
      return null;
    }
    return null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

export function mapsLinkFor(coords: Coordinates): string {
  return `https://www.google.com/maps?q=${coords.latitude},${coords.longitude}`;
}
