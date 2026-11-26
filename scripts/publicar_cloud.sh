#!/usr/bin/env bash
set -euo pipefail

project=stalwart-edge-513717-s4
region=us-central1
service=ingear-api
origin=https://ingear-api-911259663890.us-central1.run.app
version="${INGEAR_API_VERSION:?Falta la revisión de API seleccionada}"
dest=(--project="$project" --region="$region")
registry="${region}-docker.pkg.dev/${project}/ingear/ingear-api"
image="${registry}:minimal-${version}-ci-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"

[[ "$version" =~ ^[a-f0-9]{40}$ && "$(git -C API_Ingear rev-parse HEAD)" == "$version" ]]
: "${GITHUB_OUTPUT:?Falta la salida de GitHub Actions}"
: "${GITHUB_STEP_SUMMARY:?Falta el resumen de GitHub Actions}"

check_api() {
  (
    cd Front_Ingear
    F13_API_CHECK_ORIGIN="$1" F13_EXPECTED_API_VERSION="$version" \
      F13_EXPECTED_API_REVISION="$2" npm run production:api
  )
}

printf 'Tráfico anterior de Cloud Run:\n'
status_before=$(gcloud run services describe "$service" "${dest[@]}" --format='json(status)')
previous_traffic=$(jq -c '[.status.traffic[] | select((.percent // 0) > 0) | {revisionName, percent}]' <<< "$status_before")
printf '%s\n' "$previous_traffic"
printf 'Tráfico previo de Cloud Run: `%s`\n\n' "$previous_traffic" >> "$GITHUB_STEP_SUMMARY"
latest=$(jq -er '.status.latestReadyRevisionName' <<< "$status_before")

# Reuse the API for a frontend-only publication when Firebase will pin that same ready revision.
if jq -e --arg r "$latest" '
  .status.traffic | map(select((.percent // 0) > 0)) | length == 1
  and .[0].revisionName == $r and .[0].percent == 100
' <<< "$status_before" >/dev/null && check_api "$origin" "$latest"; then
  revision="$latest"
else
  # An existing tag may come from a manual release or a successful build followed by a retry.
  # Build again from the selected commit and deploy by the digest returned by that build.
  build_id=$(
    cd API_Ingear
    gcloud builds submit . "${dest[@]}" --async \
      --config=cloudbuild.minimal.yaml --ignore-file=.gcloudignore \
      --gcs-source-staging-dir="gs://${project}-ingear-build-source/source" \
      --service-account="projects/${project}/serviceAccounts/ingear-ci-build@${project}.iam.gserviceaccount.com" \
      --substitutions="_APP_VERSION=${version},_IMAGE=${image}" \
      --machine-type=e2-standard-2 --timeout=30m --format='value(id)'
  )
  [[ "$build_id" =~ ^[a-f0-9-]{36}$ ]]
  printf 'Cloud Build: %s\n' "$build_id"
  deadline=$((SECONDS + 1920))
  while true; do
    build=$(gcloud builds describe "$build_id" "${dest[@]}" --format='json(status,results.images)')
    result=$(jq -er '.status' <<< "$build")
    case "$result" in
      SUCCESS) break ;;
      PENDING|QUEUED|WORKING) ;;
      *) printf 'Cloud Build %s terminó en %s\n' "$build_id" "$result" >&2; exit 1 ;;
    esac
    if ((SECONDS >= deadline)); then
      printf 'Cloud Build %s superó el tiempo de espera.\n' "$build_id" >&2
      exit 1
    fi
    sleep 10
  done
  digest=$(jq -er --arg i "$image" '.results.images[] | select(.name == $i) | .digest' <<< "$build")
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]

  suffix="ci-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
  revision="${service}-${suffix}"
  gcloud run deploy "$service" "${dest[@]}" --image="${registry}@${digest}" \
    --update-env-vars="APP_VERSION=${version}" --revision-suffix="$suffix" \
    --no-traffic --tag="$suffix" --quiet

  candidate=$(gcloud run services describe "$service" "${dest[@]}" --format='json(status)')
  candidate_origin=$(jq -er --arg r "$revision" --arg t "$suffix" '
    select(.status.latestReadyRevisionName == $r)
    | .status.traffic[] | select(.revisionName == $r and .tag == $t and (.percent // 0) == 0)
    | .url
  ' <<< "$candidate")
  check_api "$candidate_origin" "$revision"
  gcloud run services update-traffic "$service" "${dest[@]}" --to-revisions="${revision}=100" --quiet
fi

status_after=$(gcloud run services describe "$service" "${dest[@]}" --format='json(status)')
jq -e --arg r "$revision" '
  .status.latestReadyRevisionName == $r
  and ([.status.traffic[] | select(.revisionName == $r) | (.percent // 0)] | add) == 100
' <<< "$status_after" >/dev/null
check_api "$origin" "$revision"
printf 'origen=%s\nrevision=%s\n' "$origin" "$revision" >> "$GITHUB_OUTPUT"
printf 'API disponible: `%s` en `%s`\n\n' "$version" "$revision" >> "$GITHUB_STEP_SUMMARY"
