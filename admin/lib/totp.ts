import "server-only";
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

// TOTP (RFC 6238): codigos de 6 digitos que cambian cada 30 s, compatibles
// con Google Authenticator, Microsoft Authenticator, 1Password, etc.

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const STEP_SECONDS = 30;

export function generateTotpSecret(): string {
  const bytes = randomBytes(20);
  let bits = "";
  for (const byte of bytes) bits += byte.toString(2).padStart(8, "0");
  let out = "";
  for (let i = 0; i + 5 <= bits.length; i += 5) out += ALPHABET[parseInt(bits.slice(i, i + 5), 2)];
  return out;
}

function base32Decode(input: string): Buffer {
  const clean = input.toUpperCase().replace(/[^A-Z2-7]/g, "");
  let bits = "";
  for (const char of clean) bits += ALPHABET.indexOf(char).toString(2).padStart(5, "0");
  const bytes: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(bytes);
}

function codeForStep(secret: string, step: number): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const digest = createHmac("sha1", base32Decode(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const value = (digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000;
  return value.toString().padStart(6, "0");
}

/// Devuelve el paso de tiempo del codigo si es valido (acepta +-1 paso por
/// diferencias de reloj), o null. El llamador guarda el paso para que un
/// mismo codigo no se pueda usar dos veces.
export function verifyTotp(secret: string, code: string, lastUsedStep: number | null): number | null {
  const candidate = code.replace(/\s/g, "");
  if (!/^\d{6}$/.test(candidate)) return null;
  const now = Math.floor(Date.now() / 1000 / STEP_SECONDS);
  for (const step of [now - 1, now, now + 1]) {
    if (lastUsedStep !== null && step <= lastUsedStep) continue;
    const expected = Buffer.from(codeForStep(secret, step));
    if (timingSafeEqual(expected, Buffer.from(candidate))) return step;
  }
  return null;
}

export function otpauthUri(secret: string): string {
  const label = encodeURIComponent("MonAvi Admin");
  return `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent("MonAvi")}&algorithm=SHA1&digits=6&period=${STEP_SECONDS}`;
}
