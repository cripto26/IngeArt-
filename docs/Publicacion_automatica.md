# Publicación automática de IngeArt

Un push a `produccion` del repositorio principal `cripto26/IngeArt-` publica la combinación seleccionada de API y frontend. El repositorio principal guarda los dos identificadores de commit. GitHub Actions obtiene esas versiones, ejecuta las pruebas, activa la API verificada y publica la web en Firebase Hosting con esa revisión.

La publicación manual del 26 de noviembre se construyó desde una copia aislada de los cambios de la API y desde el frontend local. Los cambios de trabajo siguen en los repositorios originales. Guárdalos en sus propios commits antes de publicarlos mediante este flujo.

## Despliegue en la red local

Caddy continúa sirviendo `D:\IngeArt\Front_Ingear\dist-lan` y envía las solicitudes de API al backend local en `127.0.0.1:8000`. GitHub Actions compila `dist` en su propio equipo y publica esos archivos en Firebase. Para incorporar cambios a la instalación de la oficina, compila en modo LAN con `npm.cmd run build:lan` desde `D:\IngeArt\Front_Ingear`. Puedes arrancar Caddy con el mismo comando:

```powershell
& 'C:\Users\dante\Downloads\caddy_windows_amd64.exe' run --config D:\IngeArt\Front_Ingear\Caddyfile
```

## Conectar GitHub y Google Cloud una vez

1. En GitHub, crea un [token de acceso detallado](https://github.com/settings/personal-access-tokens/new) con acceso a `cripto26/Ingear_API` y `cripto26/Front_Ingear`, permiso **Contents: Read-only** y una fecha de vencimiento. Guárdalo como secreto de Actions `INGEAR_SOURCE_READ_TOKEN` en [la configuración del repositorio principal](https://github.com/cripto26/IngeArt-/settings/secrets/actions). El acceso entre repositorios privados requiere ese token. [Documentación de GitHub Checkout](https://github.com/actions/checkout#checkout-multiple-repos-private)
2. En [las variables de Actions](https://github.com/cripto26/IngeArt-/settings/variables/actions), crea `INGEAR_TURNSTILE_SITE_KEY` con la **Site key pública** del widget actual de Firebase. La clave privada de Turnstile ya está en Secret Manager.
3. Obtén los ID numéricos del repositorio principal y su propietario. Con GitHub CLI autenticada en una cuenta con acceso, este comando muestra primero el ID del repositorio y después el del propietario. [Documentación de la API de repositorios](https://docs.github.com/en/rest/repos/repos#get-a-repository)

   ```bash
   gh api repos/cripto26/IngeArt- --jq '[.id, .owner.id] | @tsv'
   ```

4. Sube `scripts/configurar_publicacion_cloud.sh` a Cloud Shell. Ejecuta este comando con los dos números del paso anterior y una cuenta que pueda configurar IAM en el proyecto. El script crea las cuentas de construcción y publicación y concede acceso al proveedor de identidad de la rama `produccion`. [Federación de identidad para GitHub Actions](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)

   ```bash
   bash ~/configurar_publicacion_cloud.sh ID_REPOSITORIO ID_PROPIETARIO
   ```

5. Copia en una [variable de Actions](https://github.com/cripto26/IngeArt-/settings/variables/actions) llamada `INGEAR_WIF_PROVIDER` la ruta que imprime el script. GitHub Actions usa credenciales temporales para Cloud Build, Cloud Run y Firebase Hosting. [Autenticación de Firebase CLI en CI](https://firebase.google.com/docs/cli#use-the-cli-with-ci-systems)

## Guardar y publicar los cambios

1. Guarda un commit en `API_Ingear` y otro en `Front_Ingear` cuando cambien ambos. En VS Code, selecciona los archivos de código que quieras publicar. Deja fuera `.env`, `.firebase/` y los archivos generados.
2. Haz push de los repositorios de código que modificaste. Desde el directorio principal, en PowerShell:

   ```powershell
   git -C API_Ingear push -u origin HEAD
   git -C Front_Ingear push -u origin HEAD
   ```

3. Registra en el repositorio principal qué versiones se publican. En el primer despliegue incluye el flujo y sus scripts. Revisa el contenido preparado con `git diff --cached --stat` antes de guardar el commit:

   ```powershell
   git add -- API_Ingear Front_Ingear .github/workflows/publicar.yml scripts/publicar_cloud.sh scripts/configurar_publicacion_cloud.sh docs/Publicacion_automatica.md
   git diff --cached --stat
   git commit -m "Preparar publicación de IngeArt"
   git push origin HEAD:refs/heads/produccion
   ```

   En las siguientes publicaciones basta con añadir los punteros `API_Ingear` y `Front_Ingear` antes de hacer el commit y el push a `produccion`. Si Git rechaza el push por diferencias de historial, revisa y sincroniza esa rama antes de reintentar.

4. Abre [GitHub Actions](https://github.com/cripto26/IngeArt-/actions) y busca **Publicar IngeArt**. El resultado exitoso comprueba la revisión que responde en [Firebase Hosting](https://stalwart-edge-513717-s4.web.app/health/ready). Luego prueba el ingreso y los cambios de interfaz en el navegador.

Cuando cambia solo el frontend, el flujo reutiliza la API activa si coincide con el commit seleccionado y es la última revisión lista. Si cambia la API, Cloud Build construye la imagen, Cloud Run crea una revisión con 0 % de tráfico y el flujo comprueba su salud antes de activarla. Firebase enlaza su publicación a esa revisión. El resumen de Actions conserva el reparto anterior de tráfico para facilitar una reversión. [Revisiones de Cloud Run fijadas desde Firebase](https://firebase.google.com/docs/hosting/cloud-run#direct-hosting-requests-to-your-containerized-app)

Si un cambio necesita migraciones en Cloud SQL, aplica el procedimiento de migración antes de activar la nueva revisión. El flujo comprueba que la base esté lista al iniciar la API.
