// =============================================================================
// server.js — DEMOSTRACION Hefesto
// =============================================================================
// App mínima que genera telemetría interesante sin depender de nada externo.
//
// Qué produce:
//   - 1 ruta rápida       → traza corta y sana
//   - 1 ruta lenta        → traza larga: sirve para ver el p95 subir
//   - 1 ruta que falla    → error y status 500: sirve para ver la tasa de error
//
// Se arranca con el SDK ya cargado:
//     npm install
//     node --require ./otel.js server.js
//
// Para tener la aplicación un rato adentro, ver LATENCIA_MS y RATE_ERROR.
// =============================================================================

'use strict';

const express = require('express');
const { metrics } = require('@opentelemetry/api');

const app = express();
const puerto = process.env.PORT || 3000;

// Valores por defecto para la demo. Súbelos desde el entorno.
const LATENCIA_MS = Number(process.env.DEMO_LATENCIA_MS || 250);
const RATE_ERROR = Number(process.env.DEMO_RATE_ERROR || 0.1); // 10 % de errores

// -----------------------------------------------------------------------------
// Métricas propias. Las que Uptime Kuma y Umami no te dan: no solo que la app
// falló, sino QUÉ tan rápido respondió y qué operación interna lo retrasó.
// -----------------------------------------------------------------------------
const contadorPeticiones = metrics.createCounter('demo_peticiones_total', {
  description: 'Peticiones atendidas por la app de demostración',
});

const histogramaLatencia = metrics.createHistogram('demo_latencia_ms', {
  description: 'Latencia de la operación de negocio simulada',
  unit: 'ms',
});

const temporizadorOperacion = (nombre) => {
  const inicio = Date.now();
  return () => histogramaLatencia.record(Date.now() - inicio, { operacion: nombre });
};

// -----------------------------------------------------------------------------
// Rutas
// -----------------------------------------------------------------------------

app.get('/', (_req, res) => {
  res.json({
    servicio: process.env.OTEL_SERVICE_NAME || 'demo-hefesto-api',
    rutas: ['/rapida', '/lenta', '/falla', '/stats'],
    nota: 'Demo Hefesto. Mira esta app en la UI de SigNoz.',
  });
});

// Ruta sana: responde rápido.
app.get('/rapida', (_req, res) => {
  contadorPeticiones.add(1, { ruta: '/rapida', resultado: 'ok' });
  console.log('[demo] /rapida atendida');
  res.json({ ok: true, operacion: 'rapida' });
});

// Ruta lenta: aquí se ve el p95 en el panel.
app.get('/lenta', async (_req, res) => {
  contadorPeticiones.add(1, { ruta: '/lenta', resultado: 'ok' });
  const medir = temporizadorOperacion('lenta');
  await new Promise((r) => setTimeout(r, LATENCIA_MS));
  medir();
  console.log(`[demo] /lenta demoró ${LATENCIA_MS} ms`);
  res.json({ ok: true, operacion: 'lenta', ms: LATENCIA_MS });
});

// Ruta que falla a propósito: así se ve el error en la traza y sube la tasa de error.
app.get('/falla', (_req, res) => {
  const debeFallar = Math.random() < RATE_ERROR;
  if (debeFallar) {
    contadorPeticiones.add(1, { ruta: '/falla', resultado: 'error' });
    console.error('[demo] /falla devolvió 500 (simulado)');
    res.status(500).json({ ok: false, error: 'fallo simulado para la demostración' });
    return;
  }
  contadorPeticiones.add(1, { ruta: '/falla', resultado: 'ok' });
  res.json({ ok: true, operacion: 'falla-control' });
});

app.listen(puerto, () => {
  console.log(`[demo] Escuchando en http://localhost:${puerto}`);
  console.log(`[demo] Latencia simulada: ${LATENCIA_MS} ms | Tasa de error: ${RATE_ERROR}`);
});