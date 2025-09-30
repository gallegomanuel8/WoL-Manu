#!/bin/bash

# Script para ejecutar todos los tests unitarios del proyecto WoL-Manu
# Incluye tests del servidor Python y del cliente Swift

set -e  # Parar en caso de error

echo "=============================================="
echo "🧪 EJECUTANDO TESTS UNITARIOS WoL-Manu"
echo "=============================================="

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para mostrar el resultado
show_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2 - PASADOS${NC}"
    else
        echo -e "${RED}❌ $2 - FALLARON${NC}"
        return 1
    fi
}

# Variables para tracking de resultados
PYTHON_RESULT=0
SWIFT_RESULT=0
TOTAL_ERRORS=0

echo ""
echo "📋 TESTS DEL SERVIDOR PYTHON"
echo "=============================================="

# Ejecutar tests del servidor Python
cd wol-server
if python3 test_validations.py > ../python_tests.log 2>&1; then
    show_result 0 "Tests del servidor Python"
    echo "   ✓ Validación de direcciones MAC"
    echo "   ✓ Validación de direcciones IP" 
    echo "   ✓ Construcción de paquetes mágicos"
    echo "   ✓ Tests de integración"
    echo "   ✓ Protección contra DoS"
else
    PYTHON_RESULT=1
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    show_result 1 "Tests del servidor Python"
    echo "   ❌ Ver detalles en python_tests.log"
fi

cd ..

echo ""
echo "📱 TESTS DEL CLIENTE SWIFT"  
echo "=============================================="

# Ejecutar tests del cliente Swift
if xcodebuild -project "WoL Manu.xcodeproj" -scheme "WoL Manu" -sdk macosx -destination 'platform=macOS' test -only-testing:"WoL ManuTests/WakeOnLANServiceTests" > swift_tests.log 2>&1; then
    show_result 0 "Tests del cliente Swift"
    echo "   ✓ Parseo de direcciones MAC"
    echo "   ✓ Construcción de paquetes mágicos"
    echo "   ✓ Tests de integración MAC+Magic Packet"
    echo "   ✓ Validación de casos edge"
    echo "   ✓ Tests de rendimiento"
else
    SWIFT_RESULT=1
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    show_result 1 "Tests del cliente Swift"
    echo "   ❌ Ver detalles en swift_tests.log"
fi

echo ""
echo "=============================================="
echo "📊 RESUMEN FINAL"
echo "=============================================="

# Mostrar resumen final
if [ $TOTAL_ERRORS -eq 0 ]; then
    echo -e "${GREEN}🎉 TODOS LOS TESTS PASARON EXITOSAMENTE${NC}"
    echo ""
    echo "   ✅ Tests del servidor Python: PASADOS"
    echo "   ✅ Tests del cliente Swift: PASADOS"
    echo ""
    echo "   📊 Total de suites: 2"
    echo "   📊 Total de errores: 0"
    echo ""
    echo -e "${GREEN}   El proyecto está listo para producción! 🚀${NC}"
else
    echo -e "${RED}❌ ALGUNOS TESTS FALLARON${NC}"
    echo ""
    if [ $PYTHON_RESULT -ne 0 ]; then
        echo -e "   ${RED}❌ Tests del servidor Python: FALLARON${NC}"
    else
        echo -e "   ${GREEN}✅ Tests del servidor Python: PASARON${NC}"
    fi
    
    if [ $SWIFT_RESULT -ne 0 ]; then
        echo -e "   ${RED}❌ Tests del cliente Swift: FALLARON${NC}"
    else
        echo -e "   ${GREEN}✅ Tests del cliente Swift: PASARON${NC}"
    fi
    
    echo ""
    echo "   📊 Total de suites: 2"
    echo "   📊 Total de errores: $TOTAL_ERRORS"
    echo ""
    echo -e "${YELLOW}   Revisa los logs para más detalles:${NC}"
    
    if [ $PYTHON_RESULT -ne 0 ]; then
        echo "   - python_tests.log"
    fi
    if [ $SWIFT_RESULT -ne 0 ]; then
        echo "   - swift_tests.log"  
    fi
    
    exit 1
fi

echo "=============================================="