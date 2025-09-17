#!/bin/bash
echo "🚀 Iniciando Frontend..."
cd frontend
source .venv/bin/activate
export BACKEND_URI=http://localhost:8000
python app.py