// =============================================================================
// otel.js — DEMOSTRACION Hefesto
// =============================================================================
// Inicializa OpenTelemetry ANTES que cualquier otra cosa de la app. Por eso el
// arranque es `node --require ./otel.js server.js`.
//
// Envía trazas, métricas y logs a SigNoz por OTLP/gRPC en el puerto 4317.
//
// Sin secretos. El endpoint se toma de variables de entorno; los valores por
// defecto apuntan al compose de este kit ejecutándose en el mismo servidor.
// =============================================================================

'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-grpc');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-grpc');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const {
  resourceFromAttributes,
} = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } = require('@opentelemetry/semantic-conventions');

// -----------------------------------------------------------------------------
// Configuración por variable de entorno, con valores por defecto inofensivos.
// -----------------------------------------------------------------------------
const OTLP_HOST = process.env.OTEL_EXPORTER_OTLP_HOST || '127.0.0.1';
const OTLP_PORT = process.env.OTEL_EXPORTER_OTLP_PORT || '4317';
const endpoint = `http://${OTLP_HOST}:${OTLP_PORT}`;

const serviceName = process.env.OTEL_SERVICE_NAME || 'demo-hefesto-api';
const serviceVersion = process.env.OTEL_SERVICE_VERSION || '1.0.0';

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: serviceName,
    [ATTR_SERVICE_VERSION]: serviceVersion,
    // Grupo por cliente cuando la instancia sea compartida. Ver la advertencia
    // de multi-tenancy en docs/08-SERVICIOS-COMERCIALES.md.
    'deploy.environment.name': process.env.DEPLOY_ENVIRONMENT || 'demo',
  }),

  // --- Trazas: por dónde se ven las peticiones y dónde se fue el tiempo ---
  traceExporter: new OTLPTraceExporter({ url: endpoint }),

  // --- Métricas: p95 de latencia, tasa de error, throughput ---
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({ url: endpoint }),
    exportIntervalMillis: 15000,
  }),

  // --- Logs: lo que la app escribe por consola ---
  logRecordProcessors: [
    new BatchLogRecordProcessor(new OTLPLogExporter({ url: endpoint })),
  ],

  // Auto-instrumentación: HTTP, Express, base de datos, etc.
  instrumentations: [
    getNodeAutoInstrumentations({
      // Desactiva lo que no aplique y solo haga ruido.
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': {
        enabled: true,
        // Un DNS que se demora es información real; localhost se ignora porque
        // solo genera ruido.
        ignoreHostnames: ['localhost'],
      },
    }),
  ],
});

sdk.start();

process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
});

console.log(`[demo] OpenTelemetry enviando a ${endpoint} como "${serviceName}"`);