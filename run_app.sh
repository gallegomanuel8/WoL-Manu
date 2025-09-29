#!/bin/bash
# Script para ejecutar la aplicación Wake-on-LAN

echo "🚀 Ejecutando aplicación Wake-on-LAN..."

# Buscar la aplicación compilada
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/WoL_Manu-*/Build/Products/Debug -name "WoL Manu.app" 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: Aplicación no encontrada. Asegúrate de que esté compilada."
    echo "   Para compilar: cd '$(pwd)' && xcodebuild -project 'WoL Manu.xcodeproj' -scheme 'WoL Manu' build"
    exit 1
fi

echo "📍 Ejecutando desde: $APP_PATH"
open "$APP_PATH"
echo "✅ Aplicación Wake-on-LAN iniciada correctamente!"