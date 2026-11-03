# Preparación de IngeArt para Google Cloud y Caddy

Actualización: 3 de noviembre de 2026. El usuario aplazó expresamente el
proyecto, dominio y configuración real de Google Cloud. Esta entrega prepara
el código y una instalación LAN. No publica recursos cloud ni sustituye
credenciales por valores inventados.

## Cambios del código

Se actualizaron y bloquearon las dependencias de ejecución y desarrollo.
La auditoría OSV incluye los pins de todas las plataformas del lock de Python;
CI falla ante avisos activos o una respuesta incompleta. npm se audita también
en CI, incluyendo herramientas de desarrollo. El fork local
`Front_Ingear/vendor/deepmerge` corrige GHSA-gcqx-w48m-w2h4, todavía sin versión
oficial corregida al revisar: conserva licencia y API, registra huellas y prueba
la contaminación de prototipos. No se declara ese fork como una corrección
publicada por el mantenedor original. Revisar su sustitución cuando exista una
versión corregida. `npm ci` reproduce el fork desde una dependencia local raíz.

Las solicitudes tienen un máximo global de 30 MiB, aplicado también a cuerpos
sin Content-Length. Los PDF binarios tienen límite de 25 MiB; imágenes de
producto, 8 MiB, ocho millones de píxeles y lado máximo de 8192. Las firmas PNG
tienen límites menores. Pillow selecciona solo los decodificadores permitidos
antes de cargar la imagen; rechaza animaciones y limita a dos decodificaciones
simultáneas. Las cargas y las escrituras de cotización ejecutan ORM y trabajo
bloqueante en hilos. Una prueba comprueba que salud responde mientras el
almacenamiento de una carga está esperando.

GCS comparte un presupuesto entre las operaciones de un objeto. Los tiempos
por intento y reintentos quedaron por debajo del límite de Firebase; el SDK
puede consumir un último intento además de su ventana de reintentos, por lo
que el presupuesto no debe confundirse con un límite duro del proceso. Los
nombres por contenido permiten repetir una carga incierta sin crear otro
objeto. Drive limita tamaño, número de reintentos y tiempo por solicitud.
Gmail tiene timeout de transporte y no reintenta automáticamente un envío;
ante resultado incierto se indica revisar Enviados. Esto evita reintentos
ciegos, pero no implementa una cola de entrega con garantía exactamente una vez.

El pool PostgreSQL permite cinco conexiones persistentes y tres adicionales
por proceso: máximo teórico de 24 para tres instancias web, más Jobs y
administración. Hay timeouts explícitos de conexión, adquisición, consulta,
bloqueo y transacción inactiva. Cloud Run fija concurrencia 8, CPU 1, memoria
1 GiB y máximo 3 instancias. Son valores iniciales; medir memoria con PDF e
imágenes reales y ajustar concurrencia, pool e instancia juntos antes de
prometer capacidad. No hay una certificación de usuarios simultáneos.

El frontend consulta el estado de productos aproximadamente cada 30 segundos,
con variación y retroceso hasta cinco minutos ante errores. Suspende las
consultas en pestañas ocultas y sin red, cancela la consulta activa y deja de
reintentar ante 401/403. El SSE anterior queda solo como compatibilidad y
termina a los 45 segundos; el frontend actualizado ya no lo utiliza.

La búsqueda online usa páginas y la búsqueda exacta por código/referencia se
resuelve en el servidor respetando permisos. Un catálogo de más de 5000
productos no se descarga automáticamente. En Ajustes → Este dispositivo se
puede solicitar una copia offline. Las páginas se guardan en staging y solo
un catálogo completo reemplaza atómicamente datos y cursor; un fallo conserva
la copia anterior. La búsqueda offline grande recorre bloques de 1000 filas
y conserva solo los mejores resultados, sin materializar todo el catálogo.

El perfil offline caduca a las ocho horas desde la última validación online;
no basta modificar el estado de conectividad para renovarlo. Los perfiles
antiguos sin fecha válida requieren autenticación. Cerrar sesión o cambiar
propietario invalida los trabajos en curso y borra cachés de consulta; las
conexiones IndexedDB cooperan con el cierre desde otras pestañas. Los borradores
pendientes, separados por propietario, se conservan. Un dispositivo desconectado
no puede conocer una revocación inmediata del servidor: proteger físicamente
el equipo sigue siendo necesario.

Firebase y Caddy incluyen CSP compatible con Turnstile, imágenes y PDF mediante
blob, restricción de enmarcado, nosniff, política de referencias y permisos.
Las rutas /api y /health se enrutan antes del fallback SPA. Se eliminaron las
deprecaciones propias de Pydantic Config y los eventos antiguos de FastAPI.

## Proxy y producción

Caddy usa exclusivamente la confianza en loopback. Uvicorn no procesa por su
cuenta los encabezados de proxy. Cloud Run tiene un modo separado, activado
solo con K_SERVICE, que acepta únicamente el último salto de X-Forwarded-For.
Detrás de Firebase ese salto identifica el borde de CDN, no al empleado.
El límite independiente por cuenta se mantiene entre direcciones y la clave
del borde incluye la cuenta para evitar bloquear empleados ajenos. No se
envía la dirección del CDN como remoteip de Turnstile.

Debe probarse la cadena real al crear preproducción, incluyendo encabezados
falsificados. No cambiar a confianza universal ni saltar un número arbitrario
de proxies. Referencias: [ejemplo oficial de confianza en un salto](https://github.com/GoogleCloudPlatform/nodejs-docs-samples/pull/3586)
y [contrato de Cloud Run](https://docs.cloud.google.com/run/docs/container-contract).

Producción exige CAPTCHA activo y sin bypass, cookie __session Secure, origen
HTTPS exacto, bucket privado y rol web sin DDL. Los ejemplos mantienen
placeholders y fallan mientras no existan recursos reales. La LAN tiene un
build y configuración separados que no pueden pasar la publicación productiva.

La imagen fija Python por digest, instala Microsoft ODBC 18 y verifica su
presencia. El repositorio oficial de Debian 12 y la versión fijada se
comprobaron. World Office productivo requiere cifrado, certificado validado,
red privada y driver `ODBC Driver 18 for SQL Server`. Instalar el controlador
no abre la ruta hacia la oficina. La cuenta web no debe obtener permisos de
administrador de infraestructura. [Instalación oficial de ODBC](https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server).

CI ahora construye y escanea la imagen Linux con Trivy; también importa las
bibliotecas nativas y comprueba ODBC. Docker no está disponible en esta estación:
esa ejecución de CI y su resultado deben obtenerse antes de publicar. La
verificación de registros realizada aquí acredita las entradas de construcción,
no que la imagen ya haya sido ejecutada o aprobada. gcloud y Firebase CLI tienen
versiones fijadas y comprobación previa al despliegue. Actualizar esos pins con
una revisión explícita cuando corresponda.

## Recuperación y mantenimiento

La base empresarial se usó en modo de solo lectura. Se exportó un snapshot
consistente con PostgreSQL 18 y se restauró en otra base del servidor
desechable, puerto 55443. Se compararon los conteos de todas las tablas,
validación de claves foráneas y los cinco checksums de migración. La evidencia
sanitizada está en `entregables/preparacion_despliegue_2026-11-03/restore-rehearsal.json`.
El dump contiene información empresarial y permanece bajo `API_Ingear/tmp`,
excluido de Git y de las entregas cloud y LAN.

No ejecutar adopt sobre una copia que ya conserva historial. Primero status;
upgrade aplica solo revisiones pendientes con los respaldos y ensayos exigidos.
La versión mayor de destino debe ser PostgreSQL 18. Los conteos son una
fotografía del respaldo, no constantes de aceptación para todas las versiones.

Se preservan los archivos históricos de migración y sus checksums. Un guard
en CI fija los modelos y servicios que consume la línea base v0001: cambios
futuros en esos archivos detienen la publicación hasta congelar un bootstrap
estable. No regenerar el manifiesto para silenciar el error. Conservar la
imagen original de migración por digest y añadir revisiones nuevas; el guard
mitiga el acoplamiento histórico, no convierte v0001 en SQL autónomo.

El comando `python -m app.scripts.maintain_operational_data` informa candidatos
sin borrar. Con `--apply` archiva auditoría antigua en lotes comprimidos,
verifica lectura y SHA-256 y después elimina únicamente las filas bloqueadas
del lote. Si falla la lectura no las elimina. La política inicial es 365 días,
configurable con mínimo de 90; no se ejecutó purga sobre la base empresarial.
Limpia sesiones expiradas hace más de siete días y estados de login inactivos.
`--compact-feeds` rota epochs y limpia feeds en una misma transacción bajo
bloqueo compartido con escritores; los clientes antiguos reconstruyen snapshot.
Programarlo como Job de mantenimiento separado, con identidad y permisos
específicos, cuando se prepare Cloud. No ejecutar borrado SQL directo del feed.

Antes de abrir producción configurar explícitamente respaldos automáticos,
PITR, retención de objetos y recuperación. Propuesta inicial para validar con
operaciones: RPO 15 minutos y RTO 4 horas, PITR de 7 días y respaldos diarios de
30 días. El ensayo local no acredita esos objetivos en Cloud SQL ni la
recuperación de GCS. Restaurar en una instancia nueva, comprobar hashes y
conteos y probar una revisión anterior contra el esquema vigente antes del
primer corte. [PITR de Cloud SQL](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/pitr).

## Pendientes al crear el proyecto

1. Definir proyecto, facturación, región, dominio y presupuesto. Crear bucket
   privado, Cloud SQL 18 y Artifact Registry. Habilitar Secret Manager e IAM
   mínimo para cuentas separadas de web, migración, recordatorios y mantenimiento.
2. Crear claves Turnstile para el dominio. Completar runtime y bindings con
   versiones numéricas de secretos, sin copiar el .env LAN. Pasar preflight.
3. Ejecutar CI Linux y escaneo; construir y conservar digest y versión de
   Hosting. Preparar revisión sin tráfico con el script existente. No promover
   una etiqueta latest ni un checkout con cambios.
4. Importar una copia consistente y comprobar status. Subir documentos con la
   herramienta de migración, leerlos nuevamente con hashes y cambiar de revisión
   para comprobar persistencia. Conservar originales durante la aceptación.
5. Ejecutar `python -m app.scripts.verify_integrations --storage`, luego las
   opciones --gmail-sender, --drive-file-id y --world-office según integración.
   El chequeo Gmail obtiene autorización delegada sin enviar correo: el envío
   real requiere un destinatario de prueba autorizado y confirmación del operador.
6. Ensayar login, permisos, cookie, PDF, firma, fotos, sesión offline y cambios
   de cuenta desde el dominio Firebase. Validar proxy y medir catálogo, latencia
   y memoria con el volumen actual y un dispositivo móvil de oficina.
7. Crear Jobs y Scheduler; comprobar última ejecución exitosa y fallo inducido
   de recordatorios. Configurar alertas con canal real y probar recepción.
8. Habilitar tráfico después de revisar evidencias y procedimiento de reversión.
   Revertir API/Hosting no revierte datos. Una recuperación de base requiere
   evitar nuevas escrituras durante el cambio de conexión.

Alertas iniciales: 5xx sostenidos, latencia p95, memoria >85%, conexiones de base
>80% del presupuesto, disco de base >80%, respaldo/PITR no disponible y Job
fallido o sin ejecución exitosa reciente. Los filtros deben limitarse al
servicio/instancia real. Asignar un responsable que pueda reducir tráfico,
consultar logs por request_id, revisar conexiones y escalar el incidente;
documentar canal y tiempo de atención. La preparación F16 ya contiene las
alertas específicas de recordatorios. No se declara que exista un canal o que
la recepción esté probada mientras el proyecto permanezca aplazado.

## Entrega LAN

`D:\Ingear-caddy- local` contiene frontend compilado, backend del mismo commit,
Python exacto, entorno runtime nuevo y Caddy fijado. Incluye configuración y
documentos locales privados, fuera de la raíz pública. No contiene Git,
node_modules, pruebas, históricos de informes ni entornos de desarrollo.
Consultar LEEME.md, iniciar con INICIAR.cmd y confiar únicamente en root.crt
en los equipos clientes. La dirección inicial es https://192.168.1.152.
Se reutiliza la base local existente; el empaquetado no la altera.

Evitar escrituras alternadas entre la instalación antigua y la nueva: sus
carpetas de documentos son independientes. Respaldar base y exports juntos.
La puesta en servicio de otros equipos requiere comprobar firewall de perfil
privado, certificado, acceso con cuenta autorizada y funciones de oficina.

World Office queda aplazado por decision expresa del usuario: la configuracion LAN mantiene TLS validado y la integracion deshabilitada hasta preparar el certificado y la conectividad del servidor SQL. La comprobacion del modo anterior fue solo diagnostica; no se conserva ese modo inseguro.

Las cinco políticas de API y base se generan sin publicar recursos con
`python scripts/render_monitoring_policies.py --project ID --instance INSTANCIA --max-connections VALOR_REAL --channel projects/ID/notificationChannels/NUMERO --output tmp/alertas`.
El directorio debe ser nuevo y los identificadores reales. Después revisar y
crear las políticas con `gcloud monitoring policies create --project ID --policy-from-file ARCHIVO.json`.
No usar los ejemplos de evidencia como recursos reales. Confirmar los descriptores
al crearlas: [métricas Cloud Run](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z#run)
y [métricas Cloud SQL](https://docs.cloud.google.com/monitoring/api/metrics_gcp_c#cloudsql).
Las alertas de respaldo/PITR y recepción real siguen dentro de la aceptación del
proyecto aplazado; estas plantillas no acreditan que ya haya monitorización activa.

## Exclusión de documentos en archivos públicos

La comprobación final detectó cuatro PDF en `public/IMAGENES`, entre ellos un
documento comercial. El build ahora prepara una carpeta pública aparte:
los recursos de interfaz se permiten mediante `scripts/public-asset-policy.json`
y el catálogo admite solo imágenes con extensión y cabecera de raster reconocidas.
Se regeneran las rutas del manifiesto a partir de los archivos admitidos. Los
PDF y archivos arbitrarios, incluso un PDF renombrado como JPG, quedan fuera de
`dist`; los originales se conservan. Esta política se aplica a LAN y producción,
y tiene una prueba con documento comercial, secreto local y extensión falsa.
Los recursos raster del catálogo que están fuera de Git se incluyen como
activos públicos identificados en el archivo de fuentes, sin incluir documentos.
