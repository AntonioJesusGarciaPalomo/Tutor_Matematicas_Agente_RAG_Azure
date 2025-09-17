#!/bin/bash
echo "🚀 Iniciando Math Tutor en modo local..."
echo "========================================="

# Función para matar procesos al salir
cleanup() {
    echo -e "\n🛑 Deteniendo servicios..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    exit
}

trap cleanup EXIT INT TERM

# Iniciar backend
echo "▶️ Iniciando Backend en http://localhost:8000"
cd backend
source .venv/bin/activate
python main.py &
BACKEND_PID=$!
cd ..

# Esperar a que el backend esté listo
echo "⏳ Esperando a que el backend esté listo..."
sleep 5

# Verificar que el backend está respondiendo
if curl -s http://localhost:8000/health > /dev/null; then
    echo "✅ Backend está listo"
else
    echo "❌ El backend no responde. Verifica los logs."
fi

# Iniciar frontend
echo "▶️ Iniciando Frontend en http://localhost:7860"
cd frontend
source .venv/bin/activate
export BACKEND_URI=http://localhost:8000
python app.py &
FRONTEND_PID=$!
cd ..

echo ""
echo "========================================="
echo "✅ Servicios iniciados:"
echo "   - Backend:  http://localhost:8000"
echo "   - Frontend: http://localhost:7860"
echo ""
echo "📝 Logs:"
echo "   - Presiona Ctrl+C para detener ambos servicios"
echo "========================================="

# Mantener el script ejecutándose
wait
