> Actualizacion de cierre 03/11/2026: seguir primero [la preparacion actual](docs/Preparacion_despliegue_2026-11-03.md).
> El proyecto, dominio, secretos y pruebas reales de Google Cloud se completaran despues por indicacion del usuario.
> El tier de instancia de esta guia es un ejemplo inicial sujeto a medicion; no equivale a capacidad ni SLA validados.

# Guia tecnica de despliegue en Google Cloud - IngeAr App

Fecha: 2026-11-03
Responsable operativo: Ingeniero de sistemas de IngeAr
Aplicacion: PWA React/Vite + API FastAPI + PostgreSQL
Base local verificada el 03/11/2026: PostgreSQL 18.1, 49 tablas, 375.125.695 bytes (358 MiB)

**Actualizacion F11 (28/09/2026):** antes de desplegar la API, preparar la base con
el Job de migraciones y separar el rol PostgreSQL de migraciones del rol web.
Seguir [la guia de migraciones F11](API_Ingear/docs/migrations_f11.md), que sustituye
cualquier inicializacion automatica al arrancar. En una copia importada ejecutar primero
`status`: si ya conserva el historial, no ejecutar `adopt`. Reservar `adopt` para
instalaciones sin historial con evidencia validada; en una base vacia usar `upgrade`. Programar tambien el Job de recordatorios.

**Actualizacion F12 (04/10/2026):** los PDF e imagenes operativas deben migrarse al
bucket privado antes de escalar Cloud Run. Seguir [la guia F12](API_Ingear/docs/storage_f12.md).
Produccion exige `FILE_STORAGE_BACKEND=gcs`; el despliegue se detiene si queda en
almacenamiento local. No borrar `exports` hasta terminar carga, verificacion y prueba
de recuperacion.

**Actualizacion F13 (04/10/2026):** la configuracion y publicacion deben seguir
[el control productivo del backend](API_Ingear/docs/production_f13.md) y
[el del frontend](Front_Ingear/docs/production_f13.md). Las secciones de despliegue
se actualizan para usar esos controles. Los nombres de recursos y los valores de
la medicion inicial son referencias historicas; confirmar los recursos reales.

## 1. Objetivo

Desplegar IngeAr App en Google Cloud usando la cuenta corporativa de IngeAr y separando responsabilidades:

- Los jefes o administradores conservan las credenciales de Google Workspace, facturacion y administracion superior.
- El ingeniero de sistemas recibe permisos IAM sobre el proyecto de Google Cloud para desplegar, operar y monitorear la aplicacion.
- La PWA se publica en Firebase Hosting.
- La API FastAPI se publica en Cloud Run.
- PostgreSQL se migra a Cloud SQL for PostgreSQL.
- Secretos, llaves y credenciales se guardan en Secret Manager.

## 2. Arquitectura recomendada

```text
Usuario
  |
  | HTTPS
  v
Firebase Hosting / dominio IngeAr
  |
  | /api/v1/** rewrite
  v
Cloud Run - ingear-api
  |
  | Cloud SQL Auth Proxy / socket /cloudsql
  v
Cloud SQL PostgreSQL - ingear_db

Cloud Run tambien consulta:
- Secret Manager: SECRET_KEY, DATABASE_URL, Turnstile, service account JSON si se mantiene el esquema actual.
- Google Workspace APIs: Gmail API y Drive API.
- Cloud Storage: archivos pesados, exportaciones o respaldos auxiliares.
```

Punto clave: el frontend tiene `VITE_API_BASE_URL=/api/v1`, por lo que conviene mantener mismo dominio y configurar Firebase Hosting para enrutar `/api/v1/**` hacia Cloud Run. Asi se evita CORS en produccion y se conserva una URL limpia para la PWA.

## 3. Lo que deben hacer tus jefes con Google Workspace

No deben entregarte su usuario ni contrasena. Deben hacer una configuracion administrativa puntual:

1. Entrar a Google Cloud Console con una cuenta administradora de Workspace.
2. Confirmar que exista la organizacion de Google Cloud asociada al dominio de IngeAr.
3. Crear o aprobar el proyecto `ingear-prod`.
4. Vincular una cuenta de facturacion.
5. Crear presupuesto y alertas.
6. Agregar tu correo corporativo como operador tecnico del proyecto.

Permisos practicos para implementacion inicial:

- `roles/owner` temporal solo sobre el proyecto `ingear-prod`, o estos roles separados:
- `roles/run.admin`
- `roles/cloudsql.admin`
- `roles/artifactregistry.admin`
- `roles/secretmanager.admin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/iam.serviceAccountAdmin`
- `roles/iam.serviceAccountUser`
- `roles/firebase.admin`
- `roles/logging.viewer`
- `roles/monitoring.editor`

Permisos de facturacion:

- Si tus jefes no quieren darte acceso completo a facturacion, al menos deben crear el presupuesto y alertas ellos.
- Si quieren que tu lo administres, pedir rol de costos/budget sobre el proyecto o sobre la cuenta de facturacion segun politica interna.

## 4. Workspace, Gmail y Drive

El backend actual usa:

- Gmail API con scope `https://www.googleapis.com/auth/gmail.send`
- Google Drive API con scope `https://www.googleapis.com/auth/drive.readonly`
- Archivo configurado por `GOOGLE_SERVICE_ACCOUNT_FILE`

Accion requerida por administradores Workspace:

1. Crear o aprobar una service account para la app.
2. Habilitar Gmail API y Drive API en el proyecto.
3. Si la app enviara correos en nombre de usuarios de IngeAr, autorizar delegacion de dominio en Admin Console.
4. Autorizar estos scopes:
   - `https://www.googleapis.com/auth/gmail.send`
   - `https://www.googleapis.com/auth/drive.readonly`
5. Para Drive, compartir con la service account las carpetas o archivos que contienen imagenes/productos, si no se usa delegacion.

Ruta recomendada a corto plazo:

- Guardar el JSON de service account en Secret Manager.
- Montarlo como archivo en Cloud Run.
- Definir `GOOGLE_SERVICE_ACCOUNT_FILE=/secrets/google-service-account.json`.

Ruta recomendada a mediano plazo:

- Ajustar el codigo para soportar credenciales administradas de Google Cloud donde sea posible.
- Reducir o eliminar llaves JSON persistentes.

## 5. Preparacion local del ingeniero

Instalar:

- Google Cloud CLI
- Firebase CLI
- Node.js 24.22.0 y npm 11.19.1, fijados por el frontend
- CPython 3.14.8 y dependencias bloqueadas con hashes para pruebas locales
- PostgreSQL client tools: `pg_dump`, `psql`
- Git

Autenticacion:

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project ingear-prod
gcloud config set run/region us-central1
firebase login
```

Validar cuenta activa:

```powershell
gcloud auth list
gcloud config list
firebase projects:list
```

## 6. Variables de trabajo

```powershell
$env:PROJECT_ID="ingear-prod"
$env:REGION="us-central1"
$env:REPOSITORY="ingear-containers"
$env:API_SERVICE="ingear-api"
$env:SQL_INSTANCE="ingear-postgres"
$env:DB_NAME="ingear_db"
$env:DB_USER="ingear_app"
```

Usar `us-central1` para primera beta si se prioriza costo y disponibilidad de servicios. Evaluar `southamerica-east1` o `southamerica-west1` si la latencia para Colombia se vuelve prioritaria.

## 7. Habilitar APIs

```powershell
gcloud services enable run.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable firebase.googleapis.com
gcloud services enable firebasehosting.googleapis.com
gcloud services enable gmail.googleapis.com
gcloud services enable drive.googleapis.com
```

## 8. Crear Artifact Registry

```powershell
gcloud artifacts repositories create $env:REPOSITORY `
  --repository-format=docker `
  --location=$env:REGION `
  --description="Contenedores IngeAr App"
```

## 9. Crear Cloud SQL PostgreSQL

Para beta de 30 usuarios:

```powershell
gcloud sql instances create $env:SQL_INSTANCE `
  --database-version=POSTGRES_18 `
  --tier=db-custom-1-3840 `
  --region=$env:REGION `
  --storage-type=SSD `
  --storage-size=30 `
  --backup-start-time=03:00
```

Crear base y usuario:

```powershell
gcloud sql databases create $env:DB_NAME `
  --instance=$env:SQL_INSTANCE

gcloud sql users create $env:DB_USER `
  --instance=$env:SQL_INSTANCE `
  --password="PONER_PASSWORD_FUERTE_AQUI"
```

Recomendaciones:

- Mantener 30 GB iniciales aunque la BD local mida 28.85 MB; el margen cubre indices, auditoria, crecimiento y backups.
- Crear alerta al 80% de almacenamiento.
- No guardar PDFs, imagenes o exportaciones grandes en PostgreSQL. Usar Cloud Storage.

## 10. Migrar la base local a Cloud SQL

Exportar desde la base local:

```powershell
pg_dump `
  --host=localhost `
  --port=5432 `
  --username=postgres `
  --dbname=ingear_db `
  --format=plain `
  --no-owner `
  --file=ingear_db.sql
```

Crear bucket temporal:

```powershell
gsutil mb -l $env:REGION "gs://$env:PROJECT_ID-db-imports"
gsutil cp .\ingear_db.sql "gs://$env:PROJECT_ID-db-imports/ingear_db.sql"
```

Importar:

```powershell
gcloud sql import sql $env:SQL_INSTANCE `
  "gs://$env:PROJECT_ID-db-imports/ingear_db.sql" `
  --database=$env:DB_NAME
```

Validar tablas despues de importar:

```powershell
gcloud sql connect $env:SQL_INSTANCE --user=$env:DB_USER --database=$env:DB_NAME
```

Dentro de `psql`:

```sql
select count(*) from pg_tables where schemaname = 'public';
select pg_size_pretty(pg_database_size(current_database()));
```

Comparar todos los conteos con el manifiesto de la exportacion consistente. La revision del 03/11/2026 tuvo 49 tablas; no fijar ese numero para futuras versiones. Comprobar historial, claves foraneas y estado de migraciones.

## 11. Secret Manager

Crear secretos:

```powershell
gcloud secrets create ingear-secret-key --replication-policy=automatic
gcloud secrets create ingear-database-url --replication-policy=automatic
gcloud secrets create ingear-google-service-account-json --replication-policy=automatic
gcloud secrets create ingear-turnstile-secret-key --replication-policy=automatic
```

Agregar versiones:

```powershell
# Ejemplo para SECRET_KEY
Set-Content -NoNewline -Path .\secret-key.txt -Value "VALOR_SEGURO_GENERADO"
gcloud secrets versions add ingear-secret-key --data-file=.\secret-key.txt
Remove-Item .\secret-key.txt
```

`DATABASE_URL` recomendado para Cloud Run + Cloud SQL socket:

```text
postgresql+pg8000://ingear_app:PASSWORD_URL_ENCODED@/ingear_db?unix_sock=/cloudsql/PROJECT_ID:REGION:ingear-postgres/.s.PGSQL.5432
```

Ejemplo:

```powershell
Set-Content -NoNewline -Path .\database-url.txt -Value "postgresql+pg8000://ingear_app:REEMPLAZAR@/ingear_db?unix_sock=/cloudsql/ingear-prod:us-central1:ingear-postgres/.s.PGSQL.5432"
gcloud secrets versions add ingear-database-url --data-file=.\database-url.txt
Remove-Item .\database-url.txt
```

Para el JSON de Google Workspace:

```powershell
gcloud secrets versions add ingear-google-service-account-json `
  --data-file="D:\IngeArt\API_Ingear\credentials\service-account.json"
```

Luego eliminar copias locales que no deban quedar en el equipo.

## 12. Service accounts para runtime

Crear service account de Cloud Run:

```powershell
gcloud iam service-accounts create ingear-api-run `
  --display-name="IngeAr API Cloud Run runtime"
```

Permisos:

```powershell
gcloud projects add-iam-policy-binding $env:PROJECT_ID `
  --member="serviceAccount:ingear-api-run@$env:PROJECT_ID.iam.gserviceaccount.com" `
  --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding $env:PROJECT_ID `
  --member="serviceAccount:ingear-api-run@$env:PROJECT_ID.iam.gserviceaccount.com" `
  --role="roles/secretmanager.secretAccessor"
```

Para Cloud Storage usar los permisos del bucket privado definidos en F12:
creacion y lectura para la API, identidad separada para migracion. Aplicar
`API_Ingear/scripts/configure_cloud_storage_f12.ps1` al bucket dedicado.

## 13. Preparar backend para contenedor

Usar [Dockerfile](API_Ingear/Dockerfile) y [.dockerignore](API_Ingear/.dockerignore)
del proyecto. La imagen contiene el codigo y las dependencias, usa un usuario sin
privilegios y deja las migraciones para el Job F11. Uvicorn conserva la direccion
del peer para que el control de proxies F09 valide las cabeceras.

Ejecutar el preflight completo de F13 antes de construir. El control exige
PostgreSQL temporal y rechaza pruebas fallidas u omitidas.

Preparar los entornos fijados siguiendo los README de ambos repositorios y la
guia `API_Ingear/docs/reproducibility_f15.md`. Antes de publicar juntos backend y
frontend, comprobar sus contratos desde `D:\IngeArt\API_Ingear`:

```powershell
.\.venv\Scripts\python.exe scripts/check_permission_contract.py --frontend-contract ..\Front_Ingear\contracts\view_permissions.v2.json
```

La copia frontend debe ser exactamente la revision que se publicara. Ejecutar
tambien `npm run quality:ci` con Node/npm fijados; esta comprobacion sin secretos
no sustituye los controles productivos de F13 ni produce un artefacto publicable.

## 14. Construir imagen backend

```powershell
cd D:\IngeArt\API_Ingear

$env:IMAGE="$env:REGION-docker.pkg.dev/$env:PROJECT_ID/$env:REPOSITORY/ingear-api:$(git rev-parse --short HEAD)"

$BackendCommit = git rev-parse HEAD
gcloud builds submit --config cloudbuild.production.yaml `
  --substitutions="_APP_VERSION=$BackendCommit,_IMAGE=$env:IMAGE" .
```

## 14.1. Preparar los recordatorios independientes

Antes de promover la API, seguir
[el procedimiento F16](API_Ingear/docs/reminders_f16.md) para configurar un
Cloud Run Job de recordatorios, su Cloud Scheduler y los canales de alerta.
El proceso web no ejecuta recordatorios, tampoco en desarrollo. En las pruebas
LAN se utiliza `API_Ingear/run-reminders.bat` en una terminal independiente.

El Job debe usar el mismo digest de imagen y `APP_VERSION` que la API, una
identidad limitada para Cloud SQL y otra identidad para invocarlo. Preparar los
JSON de configuracion y referencias de secretos de F16, revisar el plan de
`scripts/deploy_reminders_f16.py` y aplicar la configuracion con `--apply`.
Despues ejecutar el Job una vez con `gcloud run jobs execute --wait`, comprobar
el resultado, la metrica y los canales, y utilizar `--verify-only` para verificar
la configuracion activa. Esa primera ejecucion genera recordatorios reales y
debe hacerse sobre la base y version preparadas para la publicacion.

La promocion F13 verifica que existan el Job y la programacion activos, sus
alertas y un resultado reciente de la version declarada. Si falta esa evidencia,
no se envia trafico a la nueva revision. Una revision sin promover puede
prepararse antes para comprobar su salud. Los recursos de Google Cloud requieren
`gcloud`, autenticacion y permisos reales; los tests locales no los crean.

## 15. Desplegar Cloud Run

Completar los JSON de configuracion y referencias de secretos de F13. Ejecutar
primero el Job de migraciones F11 y la verificacion de documentos F12. Usar el
digest de la imagen construida y una base temporal separada para las pruebas:

```powershell
$env:F13_TEST_DATABASE_URL = $DisposablePostgresUrl
& .\.venv\Scripts\python.exe scripts/deploy_cloud_run_f13.py `
  --project $env:PROJECT_ID --image-digest $ImageDigest `
  --service-account $ApiServiceAccount --cloudsql-instance $CloudSqlConnection `
  --runtime-config tmp/production.runtime.json `
  --secret-bindings tmp/production.secrets.json --apply --promote
```

El script exige configuracion segura, commit confirmado, cadena completa de
pruebas, probes HTTP y verificacion de version/revision antes de promover trafico.
Para revisar solo el plan, omitir `--apply --promote`. Configurar Firebase y las
claves Turnstile antes de habilitar usuarios.

## 16. Ajustar Firebase Hosting para enrutar API

Usar el [firebase.json del proyecto](Front_Ingear/firebase.json), que incluye las
reglas `/api` y `/health` hacia `ingear-api/us-central1` antes del fallback SPA,
la revision fijada con `pinTag` y el hook obligatorio `deploy:check`. El validador
rechaza publicar si esas reglas faltan. Firebase requiere cookie `__session` para
renovar la sesion mediante este proxy.

## 17. Desplegar frontend PWA

```powershell
cd D:\IngeArt\Front_Ingear

firebase use $env:PROJECT_ID
$env:F13_API_CHECK_ORIGIN = $VerifiedApiHttpsOrigin
$env:F13_EXPECTED_API_VERSION = $BackendCommit
$env:F13_EXPECTED_API_REVISION = $VerifiedCloudRunRevision
npm.cmd run deploy
```

La variable de produccion actual es correcta para mismo dominio:

```text
VITE_API_BASE_URL=/api/v1
VITE_AUTH_MODE=api
VITE_DEPLOYMENT_TARGET=production
VITE_TURNSTILE_DEV_BYPASS=false
VITE_TURNSTILE_SITE_KEY=<clave publica real autorizada para el dominio>
```

## 18. Dominio empresarial

Opciones:

1. `app.ingear.com.co` para PWA.
2. `api.ingear.com.co` solo si se decide exponer API separada.

Recomendado:

- Usar solo `app.ingear.com.co`.
- Enrutar `/api/v1/**` a Cloud Run con Firebase Hosting.
- Evitar CORS en produccion.

Tus jefes o quien administre DNS deben agregar los registros que Firebase indique al conectar dominio personalizado.

## 19. World Office

Actualmente el backend tiene variables `WORLD_OFFICE_*`.

Para produccion inicial en Google Cloud:

```text
WORLD_OFFICE_ENABLED=false
```

Si luego se requiere integracion directa con World Office:

- No abrir SQL Server de oficina a internet.
- Crear una VPN o un agente interno de sincronizacion.
- Evaluar Cloud VPN, un worker local o una tarea programada que sincronice datos hacia Cloud SQL.

## 20. Checklist antes de abrir a usuarios

Backend:

- Cloud Run responde `/`.
- Cloud Run puede conectar a Cloud SQL.
- Logs sin errores de startup.
- Secretos cargados desde Secret Manager.
- Gmail envia correo de prueba desde una cuenta autorizada.
- Drive lee imagenes/productos desde carpeta autorizada.

Base de datos:

- Conteos de todas las tablas coincidentes con la exportacion y migraciones verificadas.
- Conteo de registros validado en tablas principales.
- Backup automatico activo.
- Prueba de restauracion documentada.
- Usuario `ingear_app` sin permisos excesivos.

Frontend:

- `npm.cmd run quality` aprobado.
- `dist` generado.
- `manifest.webmanifest` disponible.
- `sw.js` disponible.
- Login funciona.
- Cotizaciones funcionan.
- Modo offline PWA probado.
- `/api/v1/**` responde API y no `index.html`.

Seguridad:

- `REFRESH_COOKIE_SECURE=true`.
- `SECRET_KEY` fuerte.
- CORS no abre dominios innecesarios.
- No hay `.env` ni credenciales en repositorio.
- Presupuesto y alertas activos.
- Max instances configurado en Cloud Run.

## 21. Comandos de monitoreo y rollback

Ver logs:

```powershell
gcloud run services logs read ingear-api --region=$env:REGION --limit=100
```

Ver revisiones:

```powershell
gcloud run revisions list --service=ingear-api --region=$env:REGION
```

Rollback Cloud Run:

```powershell
gcloud run services update-traffic ingear-api `
  --region=$env:REGION `
  --to-revisions=REVISION_ANTERIOR=100
```

Rollback Firebase Hosting:

- Entrar a Firebase Console.
- Hosting.
- Releases.
- Seleccionar version anterior.
- Roll back.

## 22. Entregables que debes pedir a jefes

Pedir formalmente:

1. Proyecto Google Cloud `ingear-prod` bajo la organizacion de IngeAr.
2. Facturacion vinculada.
3. Tu usuario corporativo con permisos IAM sobre ese proyecto.
4. Autorizacion de Gmail API y Drive API.
5. Delegacion de dominio para scopes Gmail/Drive si se enviaran correos en nombre de usuarios.
6. Aprobacion de dominio `app.ingear.com.co`.
7. Presupuesto mensual y alertas.
8. Responsable administrativo para aprobar cambios de facturacion y permisos.

Texto sugerido:

```text
Solicito acceso tecnico al proyecto Google Cloud ingear-prod para desplegar la PWA IngeAr.
No requiero credenciales de administrador de Workspace. Solicito que se me asignen permisos IAM
limitados al proyecto, que se vincule facturacion, se autoricen los scopes de Gmail/Drive requeridos
y se configure presupuesto con alertas. Las credenciales administrativas permanecen bajo custodia
de gerencia/administracion.
```

## 23. Fuentes oficiales consultadas

- Cloud Run deploy: https://cloud.google.com/run/docs/deploying
- Cloud Run + Cloud SQL PostgreSQL: https://cloud.google.com/sql/docs/postgres/connect-run
- Firebase Hosting: https://firebase.google.com/docs/hosting
- Google Cloud resource hierarchy y Workspace: https://cloud.google.com/resource-manager/docs/cloud-platform-resource-hierarchy
- Secret Manager: https://cloud.google.com/secret-manager/docs/creating-and-accessing-secrets
- Budgets and alerts: https://cloud.google.com/billing/docs/how-to/budgets

## 24. Auditoria completa en dos capas

La auditoria de IngeAr conserva el significado empresarial de cada cambio:
empleado, entidad, registro, valores anteriores y posteriores, solicitud y
traza. La segunda capa debe ejecutarse en Cloud SQL con pgAudit para registrar
las instrucciones SQL aunque sean enviadas por un administrador, un script u
otro servicio que no pase por la API.

### 24.1 Preparar las banderas sin perder la configuracion existente

El script incluido consulta y conserva las banderas actuales. Sin `-Apply`
solo muestra la operacion propuesta:

```powershell
cd D:\IngeArt\API_Ingear

.\scripts\configure_cloud_sql_pgaudit.ps1 `
  -ProjectId $env:PROJECT_ID `
  -Instance $env:SQL_INSTANCE
```

Revisar la salida y ejecutar durante una ventana de mantenimiento, porque
activar `cloudsql.enable_pgaudit` reinicia la instancia:

```powershell
.\scripts\configure_cloud_sql_pgaudit.ps1 `
  -ProjectId $env:PROJECT_ID `
  -Instance $env:SQL_INSTANCE `
  -Apply
```

El perfil registra `write`, `ddl` y `role`. Mantiene desactivado el registro de
parametros y activa el enmascaramiento de literales para evitar que claves,
datos personales o secretos aparezcan en Cloud Logging.

### 24.2 Crear la extension en la base

Conectar como un usuario miembro de `cloudsqlsuperuser` y ejecutar:

```powershell
psql $env:DATABASE_URL -f .\scripts\enable_cloud_sql_pgaudit.sql
```

Cloud SQL requiere crear la extension mediante SQL; no se crea al activar las
banderas de la instancia.

### 24.3 Habilitar Data Access audit logs

En Google Cloud Console:

1. Abrir `IAM y administracion > Registros de auditoria`.
2. Seleccionar `Cloud SQL Admin API`.
3. Habilitar `Lectura de datos` y `Escritura de datos` para los miembros que
   deban auditarse.
4. Guardar la politica.

Los eventos pgAudit apareceran como Data Access audit logs en Cloud Logging.
Consulta inicial para Logs Explorer:

```text
resource.type="cloudsql_database"
log_id("cloudaudit.googleapis.com/data_access")
```

### 24.4 Prueba de cierre

Desde una conexion administrativa diferente a Cloud Run:

```sql
BEGIN;
UPDATE oportunidad
SET observaciones = observaciones
WHERE id = ID_DE_PRUEBA;
ROLLBACK;
```

Después ejecutar una modificación real controlada y comprobar que:

1. La operación hecha desde IngeAr aparece en el apartado Auditoría de la app.
2. La instrucción SQL aparece en Cloud Logging mediante pgAudit.
3. Una modificación directa realizada fuera de IngeAr aparece en pgAudit aunque
   no produzca un evento empresarial de la aplicación.

### 24.5 Operacion y almacenamiento

- Activar el aumento automatico de almacenamiento de Cloud SQL.
- Crear una alerta sobre `database/disk/utilization`.
- Revisar el volumen de logs durante la beta antes de ampliar las clases
  auditadas.
- Definir retencion y acceso al bucket de logs según la politica de IngeAr.
- No usar `pgaudit.log=all` inicialmente: tambien registraria lecturas y puede
  aumentar considerablemente el volumen.

Fuente oficial: https://docs.cloud.google.com/sql/docs/postgres/pg-audit
