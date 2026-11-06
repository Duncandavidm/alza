#!/bin/bash
# Capturas para App Store Connect, con el tamaño que Apple pide para
# iPhone 6.9" (1320 x 2868, simulador iPhone 17 Pro Max) y barra de estado
# limpia (9:41, batería llena, señal completa).
#
# Antes: corre la app en el simulador "iPhone 17 Pro Max" desde Xcode (⌘R)
# con la cuenta de demostración. Luego, en la Terminal:
#
#   ./capturas.sh           modo claro
#   ./capturas.sh --oscuro  modo oscuro
#
# El script te dice qué pantalla abrir; la abres en el simulador y
# presionas Enter. Las capturas quedan en capturas-appstore/<fecha>/.
set -e
cd "$(dirname "$0")"

DEVICE="iPhone 17 Pro Max"
UDID=$(xcrun simctl list devices available | grep -m1 "    $DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$UDID" ]; then
  echo "No encontré el simulador \"$DEVICE\". Instálalo en Xcode > Settings > Platforms."
  exit 1
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null

APPEARANCE="light"
[ "$1" = "--oscuro" ] && APPEARANCE="dark"
xcrun simctl ui "$UDID" appearance "$APPEARANCE"

xcrun simctl status_bar "$UDID" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
trap 'xcrun simctl status_bar "$UDID" clear' EXIT

OUT="capturas-appstore/$(date +%Y%m%d-%H%M)-$APPEARANCE"
mkdir -p "$OUT"

SHOTS=(
  "01-hoy|Hoy, con varios movimientos del día"
  "02-anotar|Anotar movimiento, con un monto ya escrito (ej. 24.50) y una categoría elegida"
  "03-resumen-torta|Resumen en modo torta (Gastos, Mensual)"
  "04-resumen-barras|Resumen en modo barras, con una barra tocada"
  "05-que-pagar|\"Qué pagar primero\" o Cuentas por pagar"
  "06-analisis|Análisis, con insights generados"
  "07-nivel|Puntos > Nivel e insignias"
  "08-presupuestos|Presupuestos"
  "09-metas|Metas de ahorro"
  "10-voz|Anotar por voz (pantalla de escucha)"
)

echo ""
echo "Capturas en: $OUT"
echo "Para cada una: abre esa pantalla en el simulador y presiona Enter."
echo "Escribe s + Enter para saltarla."
echo ""
for item in "${SHOTS[@]}"; do
  name="${item%%|*}"
  desc="${item#*|}"
  read -r -p "→ $desc: " answer
  if [ "$answer" = "s" ]; then
    echo "  (saltada)"
    continue
  fi
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null
  echo "  ✓ $name.png"
done

echo ""
echo "Listo. Abriendo la carpeta..."
open "$OUT"
