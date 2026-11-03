# IngeArt en red local

Esta entrega usa el mismo código preparado para Google Cloud. Su configuración
es exclusivamente LAN: Caddy con HTTPS interno, API en `127.0.0.1:8010`, cookies
Secure, documentos locales y CAPTCHA con bypass explícito para hosts privados.
El frontend LAN no pasa los controles de publicación en Firebase.

1. Ejecutar `Iniciar-IngeArt.ps1 -SoloVerificar` para comprobar dependencias,
   esquema existente y Caddy sin cambiar la base.
2. Ejecutar `INICIAR.cmd`. Abrir `https://192.168.1.152` desde la oficina.
3. En este servidor ejecutar `Confiar-Certificado.ps1` para el usuario actual.
   En otros equipos importar únicamente
   `caddy-data/caddy/pki/authorities/local/root.crt` en las autoridades raíz de
   confianza. Comprobar la huella con el administrador. Nunca distribuir `root.key`.
4. Ejecutar `DETENER.cmd` antes de apagar, mover o actualizar la entrega.

La base PostgreSQL 18 y World Office siguen siendo servicios externos a esta
carpeta. `backend/.env` contiene la conexión local; no se crea ni restaura una
base al iniciar. El arranque rechaza esquemas pendientes. Los archivos de
`backend/exports` son una copia inicial: los nuevos documentos generados por
esta entrega se guardan aquí. No alternar escrituras entre esta copia y otra
instalación sin volver a sincronizar los documentos.

No copiar esta carpeta a un repositorio ni a Firebase: contiene configuración,
credenciales, documentos y claves TLS privados. Para Google Cloud utilizar los
repositorios fuente y los controles productivos. El manifiesto `RELEASE.json`
identifica ambos commits y las huellas del código servido.

Solo se sirve el frontend; la configuración, credenciales, logs, base y
documentos quedan fuera de su raíz pública. Si cambia la IP, modificar los
sitios del `Caddyfile` y `PUBLIC_APP_ORIGIN` en `backend/.env`. No abrir esta
instalación a Internet. World Office está aplazado por decisión del usuario;
solo se habilitará con TLS validado. En Cloud se exige además ODBC 18.

`Caddyfile` y `backend/.env` son configuración editable por el operador; el
arranque valida su sintaxis y el esquema. Las huellas de `RELEASE.json`
protegen el código y los archivos del frontend, junto con el binario de Caddy.

El firewall de Windows debe permitir TCP 80 y 443 desde la subred local en el
perfil privado. `Habilitar-AccesoLAN.ps1` prepara esa regla y debe ejecutarse
como administrador en el servidor si el firewall bloquea el acceso. No se necesitan puertos de PostgreSQL ni 8010 abiertos a los
clientes. No se instalaron servicios ni tareas de inicio automático del sistema.

Los recordatorios se ejecutan por separado, desde `backend`, con
`.venv/Scripts/python.exe -m app.jobs.reminder_worker`; consultar `--help` antes
de programar una tarea de Windows. No ejecutar dos planificadores locales sin
comprobar el bloqueo compartido. La conservación de auditoría se configura con
`python -m app.scripts.maintain_operational_data` (solo informe por defecto).

Respaldar juntos PostgreSQL y `backend/exports`; conservar además la
configuración privada y las claves de Caddy en un respaldo protegido. Revisar
el procedimiento de recuperación en la documentación fuente.

World Office queda aplazado por decision expresa del usuario: la configuracion LAN mantiene TLS validado y la integracion deshabilitada hasta preparar el certificado y la conectividad del servidor SQL. La comprobacion del modo anterior fue solo diagnostica; no se conserva ese modo inseguro.
