#!/usr/bin/env bash
set -euo pipefail

project=stalwart-edge-513717-s4
project_number=911259663890
region=us-central1
repository=cripto26/IngeArt-
pool=ingear-github
provider=produccion

if [[ $# != 2 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ ]]; then
  echo 'Uso: bash configurar_publicacion_cloud.sh ID_REPOSITORIO ID_PROPIETARIO' >&2
  exit 2
fi
repository_id=$1
owner_id=$2

gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  --project="$project"

deploy="ingear-ci-deploy@${project}.iam.gserviceaccount.com"
build="ingear-ci-build@${project}.iam.gserviceaccount.com"
runtime="ingear-api@${project}.iam.gserviceaccount.com"
deploy_member="serviceAccount:$deploy"
build_member="serviceAccount:$build"

for name in ingear-ci-deploy ingear-ci-build; do
  if ! gcloud iam service-accounts describe "${name}@${project}.iam.gserviceaccount.com" \
    --project="$project" --format=none >/dev/null 2>&1; then
    gcloud iam service-accounts create "$name" --project="$project" --display-name="$name"
  fi
done

if ! gcloud iam workload-identity-pools describe "$pool" --project="$project" --location=global \
  --format=none >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$pool" --project="$project" --location=global \
    --display-name="GitHub Actions IngeArt"
fi

issuer=https://token.actions.githubusercontent.com
workflow="${repository}/.github/workflows/publicar.yml@refs/heads/produccion"
mapping='google.subject=assertion.sub,attribute.repository_id=assertion.repository_id'
condition="assertion.repository_id == '${repository_id}' && assertion.repository_owner_id == '${owner_id}' && assertion.ref == 'refs/heads/produccion' && assertion.workflow_ref == '${workflow}'"
if existing=$(gcloud iam workload-identity-pools providers describe "$provider" --workload-identity-pool="$pool" \
  --project="$project" --location=global --format=json 2>/dev/null); then
  jq -e --arg c "$condition" --arg i "$issuer" '
    .state == "ACTIVE" and (.disabled // false) == false and .oidc.issuerUri == $i
    and .attributeCondition == $c and .attributeMapping["attribute.repository_id"] == "assertion.repository_id"
  ' <<< "$existing" >/dev/null || {
    echo 'El proveedor existente tiene otra configuración. Revisa su condición antes de continuar.' >&2
    exit 1
  }
else
  gcloud iam workload-identity-pools providers create-oidc "$provider" \
    --workload-identity-pool="$pool" --project="$project" --location=global \
    --display-name="Publicación de IngeArt" --issuer-uri="$issuer" \
    --attribute-mapping="$mapping" --attribute-condition="$condition"
fi

principal="principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${pool}/attribute.repository_id/${repository_id}"
gcloud iam service-accounts add-iam-policy-binding "$deploy" --project="$project" \
  --member="$principal" --role=roles/iam.workloadIdentityUser --condition=None --format=none

for role in roles/cloudbuild.builds.editor roles/firebasehosting.admin \
  roles/serviceusage.apiKeysViewer roles/serviceusage.serviceUsageConsumer; do
  gcloud projects add-iam-policy-binding "$project" --member="$deploy_member" \
    --role="$role" --condition=None --format=none
done
gcloud projects add-iam-policy-binding "$project" --member="$build_member" \
  --role=roles/logging.logWriter --condition=None --format=none

for identity in "$build" "$runtime"; do
  gcloud iam service-accounts add-iam-policy-binding "$identity" --project="$project" \
    --member="$deploy_member" --role=roles/iam.serviceAccountUser --condition=None --format=none
done
gcloud run services add-iam-policy-binding ingear-api --project="$project" --region="$region" \
  --member="$deploy_member" --role=roles/run.developer --condition=None --format=none
gcloud artifacts repositories add-iam-policy-binding ingear --project="$project" --location="$region" \
  --member="$deploy_member" --role=roles/artifactregistry.reader --condition=None --format=none
gcloud artifacts repositories add-iam-policy-binding ingear --project="$project" --location="$region" \
  --member="$build_member" --role=roles/artifactregistry.writer --condition=None --format=none

bucket="gs://${project}-ingear-build-source"
for role in roles/storage.bucketViewer roles/storage.objectUser; do
  gcloud storage buckets add-iam-policy-binding "$bucket" --project="$project" \
    --member="$deploy_member" --role="$role" --condition=None --format=none
done
gcloud storage buckets add-iam-policy-binding "$bucket" --project="$project" \
  --member="$build_member" --role=roles/storage.objectViewer --condition=None --format=none

printf '\nVariable de GitHub INGEAR_WIF_PROVIDER:\nprojects/%s/locations/global/workloadIdentityPools/%s/providers/%s\n' \
  "$project_number" "$pool" "$provider"
