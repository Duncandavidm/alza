#!/bin/bash
# Un solo comando para dejar tu Mac igual a GitHub y abrir Xcode:
#
#   ./actualizar.sh           baja cambios, sube los tuyos, regenera y abre Xcode
#   ./actualizar.sh --probar  ademas compila y corre los tests antes de abrir
#
# Si Claude en Xcode hizo commits que no se habian subido, tambien los sube.
set -e
cd "$(dirname "$0")"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "==> Rama: $BRANCH"

echo "==> Bajando cambios de GitHub..."
git pull --rebase --autostash origin "$BRANCH"

if [ -n "$(git log "origin/$BRANCH..HEAD" --oneline)" ]; then
  echo "==> Subiendo tus commits locales..."
  git push origin "$BRANCH"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Instalando XcodeGen..."
  brew install xcodegen
fi

echo "==> Generando el proyecto..."
xcodegen generate --quiet

if [ "$1" = "--probar" ]; then
  echo "==> Compilando y corriendo tests (tarda un par de minutos)..."
  xcodebuild test \
    -project MonAvi.xcodeproj \
    -scheme MonAvi \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
    -quiet
  echo "==> Compila y pasan los tests."
fi

echo "==> Abriendo Xcode..."
open MonAvi.xcodeproj
echo "==> Listo: $(git log -1 --format='%h %s')"
