# Gotitas

Consultor virtual de agua para PyMEs de Aguascalientes (proyecto UTMA, Congreso Hidrico Universitario 2026).

## Estructura
- app/: interfaz de escritorio (Electron + React)
- backend/: API local (FastAPI + SQLite)
- motor/: motor analitico
- llm/: consultor con LLM
- datos/: dataset simulado y generador
- contratos/: esquema de la base de datos y JSON del motor
- docs/: paper y documentacion

## Reglas
- Una rama por tarea: feat/nombre-de-la-tarea.
- Todo cambio entra por Pull Request a main.
- No se cambia contratos/ sin avisar al lider.
- Nunca subir claves ni archivos .env.
