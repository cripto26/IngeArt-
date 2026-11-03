> Entrega actual: [preparación para Google Cloud y Caddy](docs/Preparacion_despliegue_2026-11-03.md).
> La copia LAN depurada se encuentra en `D:\Ingear-caddy- local`; iniciar con `INICIAR.cmd` y consultar `LEEME.md`.
> World Office queda aplazado y con TLS validado por decisión del usuario. Los recursos cloud se definirán después.

# IngeArt / IngeAr App - Contexto para nuevos hilos

Este workspace contiene el sistema interno de IngeArt/IngeAr para automatizar procesos comerciales y operativos: clientes, contactos, oportunidades, cotizaciones, productos, APU, proyectos, cuentas de cobro, despachos, empleados, permisos por area, notificaciones e integraciones externas.

La idea de este README es servir como mapa rapido para cualquier nuevo hilo de trabajo. Antes de modificar codigo, lee este archivo y luego revisa los archivos especificos del modulo afectado.

## Vista general

- `API_Ingear/`: backend FastAPI + SQLAlchemy conectado a PostgreSQL.
- `Front_Ingear/`: frontend PWA con React + TypeScript + Vite.
- `backups/`: respaldos locales de PostgreSQL; se conservan para recuperacion y no se incluyen en el despliegue.
- La documentacion vigente de desarrollo y operacion esta en este README, la guia de despliegue y los directorios `docs/` de cada aplicacion.
- `tmp/`, `tmp-brave-cdp/`, `node_modules/`, `dist/`, logs y archivos generados: no asumir que son fuente de verdad.

Los informes de Word/PDF, referencias administrativas y resultados de trabajos
anteriores que no participan en el desarrollo ni en el despliegue se retiraron
de este workspace. En `entregables/` se conserva una guia de despliegue Word para
consulta manual. Los temporales se pueden regenerar; los scripts de instalacion,
migracion, mantenimiento, pruebas y despliegue de cada aplicacion se conservan.

El flujo principal de negocio es:

1. Se administran empleados, clientes, contactos, productos y paises.
2. Comercial registra oportunidades.
3. Desde una oportunidad se crean cotizaciones con productos, costos, TRM, margenes, descuentos, particiones y PDF.
4. Las cotizaciones pueden tener versiones, estados de aprobacion y envio por email.
5. Si una cotizacion se gana, puede alimentar proyectos y cuentas de cobro.
6. Logistica, Ingenieria, Administracion y Gerencia consultan o gestionan vistas segun rol/permisos.

## Estado de repos

La raiz `D:\IngeArt` es un workspace con repos Git internos en:

- `D:\IngeArt\API_Ingear`
- `D:\IngeArt\Front_Ingear`

Cuando abras un hilo nuevo, ejecuta `git status --short` en la raiz y tambien dentro de cada subrepo. Es normal encontrar cambios locales, logs o temporales. No reviertas cambios existentes sin confirmacion explicita del usuario.

## Backend: API_Ingear

Stack principal:

- FastAPI
- SQLAlchemy 2.0
- PostgreSQL con `psycopg` binario; `pg8000` es la alternativa probada por separado
- Pydantic v2 y `pydantic-settings`
- Uvicorn
- JWT + refresh cookie
- bcrypt
- Google/Gmail APIs
- Cloudflare Turnstile opcional
- World Office via ODBC opcional
- OpenPyXL para exportes

Puntos de entrada:

- `API_Ingear/app/main.py`: crea la app, configura CORS por ambiente, monta `/api/v1` y verifica configuracion/base al iniciar. Las migraciones se ejecutan aparte.
- `API_Ingear/app/api/v1/api.py`: registra routers.
- `API_Ingear/app/db/session.py`: engine, fallback de driver y `get_db()`.
- `API_Ingear/app/core/config.py`: variables de entorno esperadas.
- `API_Ingear/app/api/deps.py`: dependencias de autenticacion, roles y permisos.
- `API_Ingear/app/core/view_permissions.py`: permisos finos de vistas comerciales.

Routers principales bajo `/api/v1`:

- `/auth`: login, refresh, logout, me, cambio de clave.
- `/empleados`: empleados, roles inferidos por area/cargo y permisos.
- `/clientes`, `/contactos`: CRM base.
- `/oportunidades`: oportunidades comerciales.
- `/cotizaciones`: cotizaciones, versiones, aprobacion y envio por email.
- `/cuentas-cobro`: cuentas de cobro y prefill desde proyecto.
- `/productos`: productos, imagenes, datos para cotizador, inventario World Office.
- `/apu`: analisis de precios unitarios.
- `/proyectos`: proyectos y relaciones M:N con empleados/clientes/despachos.
- `/despachos`, `/paises`, `/fx`, `/notificaciones`.

Modelos importantes:

- `Empleado`: credenciales, area, cargo, estado, jefe, permisos de vistas.
- `Producto`: codigo unico, costos, descuentos, pais, moneda, inventario, imagenes, categoria, PVP.
- `Oportunidad`: cliente, proyecto, responsable, marca, rubro, cierre y cotizaciones relacionadas.
- `Cotizacion`: empleado, oportunidad, TRM, subtotal, total, productos serializados y estado.
- `CotizacionVersion`: historico en `cotizacion_versiones_v2`.
- `Proyecto`: estados por area, oportunidad y relaciones M:N.
- `CuentaCobro`: datos comerciales/contables para cobro.

Servicios relevantes:

- `gmail_service.py`: envio de correos de cotizacion.
- `fx_service.py`: tasas USD/COP y EUR/COP.
- `world_office_inventory_service.py`: sincronizacion de inventario externo.
- `product_image_service.py`: imagenes de productos.
- `notificacion_service.py`: notificaciones internas.
- `turnstile_service.py` y `login_protection_service.py`: proteccion de login.
- `auth_session_service.py`: refresh sessions.
- `app/jobs/reminders.py` y `reminder_worker.py`: recordatorios en un proceso separado con bloqueo PostgreSQL, reintentos y logs; no se programan desde la API.

Variables de entorno backend:

No copies valores reales al README. `API_Ingear/.env` existe y esta ignorado. Variables clave:

- `DATABASE_URL`
- `GOOGLE_SERVICE_ACCOUNT_FILE`
- `SECRET_KEY`
- `JWT_ALGORITHM`
- `ACCESS_TOKEN_EXPIRE_MINUTES`
- `REFRESH_TOKEN_EXPIRE_HOURS`
- `REFRESH_COOKIE_NAME`, `REFRESH_COOKIE_PATH`, `REFRESH_COOKIE_SECURE`, `REFRESH_COOKIE_SAMESITE`, `REFRESH_COOKIE_DOMAIN`
- `TURNSTILE_ENABLED`, `TURNSTILE_SECRET_KEY`, `TURNSTILE_SITEVERIFY_URL`
- `WORLD_OFFICE_ENABLED`, `WORLD_OFFICE_SERVER`, `WORLD_OFFICE_DATABASE`, `WORLD_OFFICE_USERNAME`, `WORLD_OFFICE_PASSWORD`, `WORLD_OFFICE_ODBC_DRIVER`
- limites de login: `LOGIN_RATE_LIMIT_*`, `LOGIN_FAILURE_*`

Comandos habituales backend:

```powershell
cd D:\IngeArt\API_Ingear
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_backend.ps1
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Para mantener los recordatorios durante las pruebas locales/LAN, abrir otra
terminal en `API_Ingear` y ejecutar `run-reminders.bat`. La API ya no inicia ese
trabajo. Para Google Cloud, consultar `API_Ingear/docs/reminders_f16.md` y preparar
el Job, Cloud Scheduler y sus alertas antes de habilitar el aplicativo.

El bootstrap crea `.venv` con CPython 3.14.8 y dependencias verificadas por hash. Si ya existe, usar `-Recreate` para archivarlo y reconstruirlo; no copiar entornos de otros equipos. Las dependencias directas se declaran en `requirements*.in`, y los locks `requirements*.txt` fijan tambien las transitivas. Las pruebas completas requieren PostgreSQL 18 desechable separado y se ejecutan con `scripts/quality_backend.py --disposable-database`; consultar el README del backend y `docs/reproducibility_f15.md`. El control productivo completo esta en `API_Ingear/scripts/preflight_production_f13.py`.

## Frontend: Front_Ingear

Stack principal:

- React 18 + TypeScript
- Vite
- React Router
- PWA con `vite-plugin-pwa`
- Tailwind CSS v4 via plugin de Vite
- jsPDF + jspdf-autotable para PDFs de cotizacion
- IndexedDB/localStorage para caches y trabajo offline

Puntos de entrada:

- `Front_Ingear/src/main.tsx`: monta providers, PWA y sincronizacion offline.
- `Front_Ingear/src/App.tsx`: rutas por modulo y guards de acceso.
- `Front_Ingear/src/config/env.ts`: `VITE_API_BASE_URL`, modo auth y Turnstile.
- `Front_Ingear/src/lib/http.ts`: wrapper fetch, token, cookies y normalizacion de texto.
- `Front_Ingear/src/auth/AuthContext.tsx`: sesion, refresh, cache offline y sincronizacion inicial.
- `Front_Ingear/src/features/cotizador/CotizadorUI.tsx`: nucleo del cotizador.

Rutas/modulos:

- `/login`
- `/`: inicio autenticado
- `/comercial/*`
- `/administracion/*`
- `/logistica/*`
- `/ingenieria/*`
- `/gerencia/*`
- subrutas compartidas: `cotizador`, `oportunidades`, `proyectos`, `cuentas-cobro`, `productos`, `clientes`, `contactos`

Permisos:

- Los roles se infieren desde `area` y `cargo`: `COMERCIAL`, `ADMINISTRACION`, `LOGISTICA`, `INGENIERIA`, `GERENCIA`, `OTRO`.
- Los permisos finos viven en `permisos_vistas`.
- Hay logica paralela en backend (`app/core/view_permissions.py`) y frontend (`src/features/cotizador/rules.ts`). Si cambias permisos, actualiza ambos.
- Marcador importante: `comercial.views.v2`.

Cotizador:

- Calculos en `src/features/cotizador/calc*.ts`.
- Tipos base en `cotizadorTypes.ts`.
- Persistencia de borrador local en `lib/quotePersistence.ts`.
- Flujo guardar/editar en `hooks/useQuotePersistenceFlow.ts`.
- Hidratacion de edicion en `hooks/useQuoteEditHydration.ts`.
- Validaciones en `lib/quoteValidation.ts`.
- Totales en `lib/quoteTotals.ts`.
- PDF en `src/lib/pdf/quotePdf.ts` y `template.ts`.
- Envio de email en `QuoteEmailModal.tsx` + endpoint backend `/cotizaciones/{id}/enviar-email`.
- Trabajo offline de cotizaciones en `features/cotizador/offline/*`.

Caches frontend:

- Productos: `src/lib/productCache.ts`
- Clientes/contactos: `src/lib/clientContactCache.ts`
- Oportunidades: `src/lib/oportunidadCache.ts`
- Paises: `src/lib/paisCache.ts`
- Registros por interfaz: `src/lib/interfaceRecordCache.ts`
- Sincronizacion global: `src/lib/browserCacheSync.ts`

Variables de entorno frontend:

`Front_Ingear/.env` existe y esta ignorado. Variables clave:

- `VITE_API_BASE_URL`: por defecto `/api/v1`, bajo el mismo origen que el frontend.
- `VITE_AUTH_MODE`: `api`, autenticacion real contra el backend.
- `VITE_TURNSTILE_SITE_KEY`
- `VITE_TURNSTILE_DEV_BYPASS`: solo para pruebas LAN coordinadas con el backend.
- `VITE_ENABLE_PWA_DEV`

Vite tiene proxy de `/api` hacia `http://127.0.0.1:8000`. `Caddyfile` sirve `dist` con HTTPS local y proxy `/api/*` a la API.

Comandos habituales frontend:

```powershell
cd D:\IngeArt\Front_Ingear
. .\scripts\bootstrap_frontend.ps1
npm run dev -- --host 127.0.0.1 --port 5182
npm run quality:ci
```

El frontend fija Node.js 24.22.0 y npm 11.19.1. El bootstrap selecciona el runtime para esa terminal e instala mediante `npm ci`; no modifica la instalacion global. `quality:ci` reproduce los controles sin secretos y genera un artefacto LAN para verificacion. Para construir las pruebas de oficina usar `npm run build:lan`. La cadena `npm run quality` exige configuracion productiva real, y el hook de Firebase exige ademas salud/version del backend antes de publicar. Cada subrepositorio incluye un workflow de GitHub Actions para instalaciones limpias.

## Integraciones externas

- PostgreSQL: persistencia principal.
- Gmail/Google service account: envio de cotizaciones por correo.
- Cloudflare Turnstile: CAPTCHA del login; la omision para pruebas LAN requiere
  `TURNSTILE_DEV_BYPASS=true`, `APP_ENV=development` y
  `VITE_TURNSTILE_DEV_BYPASS=true`.
- Proteccion de login: los limites por IP/usuario se guardan en PostgreSQL y
  solo se acepta `X-Forwarded-For` desde los CIDR de `TRUSTED_PROXY_CIDRS`.
- World Office: inventario por ODBC, controlado por `WORLD_OFFICE_ENABLED`.
- Caddy: despliegue/local HTTPS de la PWA y reverse proxy.

## Convenciones y cuidados

- No publiques secretos de `.env`, credenciales ni service accounts.
- No borres ni reviertas cambios locales existentes sin permiso.
- Evita tocar logs/builds salvo que el usuario lo pida: `dist/`, `dev-dist/`, `*.log`, `tsconfig.tsbuildinfo`, `tmp/`.
- Las migraciones se ejecutan con `python -m app.db.migrations` antes del despliegue. El arranque de la API solo verifica la base. Consultar `API_Ingear/docs/migrations_f11.md` para adopcion de instalaciones existentes, respaldos, roles y Cloud Run Jobs. No ejecutar `schema_updates.py` desde rutas HTTP o startup.
- Los documentos operativos usan la capa de almacenamiento de `API_Ingear/app/services/object_storage.py`. En Cloud Run es obligatorio `FILE_STORAGE_BACKEND=gcs`; consultar `API_Ingear/docs/storage_f12.md`. La carpeta `exports/` es solo para desarrollo/migracion local y no debe versionarse.
- La ruta productiva F13 usa Firebase Hosting hacia Cloud Run, cookie `__session` con Secure y API `/api/v1` del mismo origen. Consultar `API_Ingear/docs/production_f13.md` y `Front_Ingear/docs/production_f13.md`. La API publica `/health/live` y `/health/ready` con version/revision y rechaza configuraciones inseguras antes de consultar PostgreSQL.
- `Cotizacion.productos` y versiones guardan productos serializados; al cambiar su formato, revisa compatibilidad con cotizaciones antiguas, PDFs, versionado y modo offline.
- Cambios en productos pueden afectar cotizador, cache offline, permisos de valores, imagenes y World Office.
- Cambios en auth/permisos deben validarse en backend y frontend.
- Cambios de nombres/normalizacion pueden afectar busquedas, caches y deduplicacion.
- La app funciona como PWA; tras cambios grandes, revisa service worker/cache y comportamiento offline.

## Checklist rapido para un nuevo hilo

1. Leer este README.
2. Ejecutar `git status --short` en `D:\IngeArt`, `API_Ingear` y `Front_Ingear`.
3. Identificar si la tarea toca backend, frontend o ambos.
4. Leer archivos vecinos del modulo antes de editar.
5. Si toca permisos, comparar backend y frontend.
6. Si toca cotizador, revisar calculos, persistencia, PDF, versionado y offline.
7. Si toca productos, revisar cache, datos de cotizador, imagenes, inventario y permisos.
8. Si toca UI, levantar Vite y verificar en navegador.
9. Correr verificacion razonable antes de cerrar: compileall/build/typecheck segun aplique.

## Archivos de referencia por tipo de tarea

- Login/auth: `API_Ingear/app/api/v1/endpoints/auth.py`, `API_Ingear/app/core/security.py`, `Front_Ingear/src/auth/AuthContext.tsx`.
- Permisos/vistas: `API_Ingear/app/core/view_permissions.py`, `Front_Ingear/src/features/cotizador/rules.ts`, guards en `Front_Ingear/src/auth/Require*.tsx`.
- Cotizador: `Front_Ingear/src/features/cotizador/`, `Front_Ingear/src/api/cotizacionApi.ts`, `API_Ingear/app/api/v1/endpoints/cotizacion.py`.
- PDF/email: `Front_Ingear/src/lib/pdf/`, `Front_Ingear/src/features/cotizador/components/QuoteEmailModal.tsx`, `API_Ingear/app/services/gmail_service.py`.
- Productos: `Front_Ingear/src/features/productos/`, `Front_Ingear/src/api/productoApi.ts`, `API_Ingear/app/api/v1/endpoints/producto.py`.
- Oportunidades/proyectos/cuentas: `Front_Ingear/src/features/oportunidades/`, `src/features/proyectos/`, `src/features/cuentasCobro/`, y endpoints equivalentes en backend.
- Caches/offline: `Front_Ingear/src/lib/*Cache.ts`, `Front_Ingear/src/features/cotizador/offline/`.
- Config/despliegue: `Front_Ingear/vite.config.ts`, `Front_Ingear/Caddyfile`, `API_Ingear/app/core/config.py`.
