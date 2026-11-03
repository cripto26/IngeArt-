"""Render reviewable Cloud Monitoring policies without contacting Google Cloud.

Metrics verified against the official service metric descriptors on 2026-11-03.
Creating channels, testing notification delivery and backup/PITR monitoring are
separate acceptance steps once the project exists.
"""
import argparse
import json
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--instance", required=True)
    parser.add_argument("--service", default="ingear-api")
    parser.add_argument("--region", default="us-central1")
    parser.add_argument("--max-connections", type=int, required=True)
    parser.add_argument("--channel", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9-]{4,61}[a-z0-9]", args.project): parser.error("ID de proyecto invalido.")
    if args.max_connections < 1: parser.error("Indicar el max_connections real de la base.")
    if any(not re.fullmatch(r"[a-z][a-z0-9-]{0,62}", value) for value in (args.instance, args.service, args.region)):
        parser.error("Nombre de recurso invalido.")
    if any(not re.fullmatch(r"projects/" + re.escape(args.project) + r"/notificationChannels/[0-9]+", channel) for channel in args.channel):
        parser.error("Los canales deben pertenecer al proyecto indicado.")
    run = f'resource.type="cloud_run_revision" AND resource.labels.service_name="{args.service}" AND resource.labels.location="{args.region}"'
    sql = f'resource.type="cloudsql_database" AND resource.labels.database_id="{args.project}:{args.instance}"'
    definitions = [
        ("api-5xx", run + ' AND metric.labels.response_code_class="5xx"', "run.googleapis.com/request_count", 5, "ALIGN_SUM", "REDUCE_SUM", "60s"),
        ("api-latency-p95-ms", run, "run.googleapis.com/request_latencies", 2000, "ALIGN_PERCENTILE_95", "REDUCE_MAX", "300s"),
        ("api-memory-p95", run, "run.googleapis.com/container/memory/utilizations", .85, "ALIGN_PERCENTILE_95", "REDUCE_MAX", "300s"),
        ("sql-connections", sql, "cloudsql.googleapis.com/database/postgresql/num_backends", args.max_connections * .8, "ALIGN_MAX", "REDUCE_SUM", "300s"),
        ("sql-disk", sql, "cloudsql.googleapis.com/database/disk/utilization", .8, "ALIGN_MAX", "REDUCE_MAX", "300s"),
    ]
    args.output.mkdir(parents=True, exist_ok=True)
    for name, resource, metric, threshold, aligner, reducer, duration in definitions:
        path = args.output / (name + ".json")
        if path.exists(): parser.error("El archivo ya existe; conservar la revision anterior y usar otra carpeta.")
        policy = {"displayName": "IngeArt " + name, "combiner": "OR", "enabled": True,
            "notificationChannels": args.channel, "userLabels": {"ingear_component": name},
            "alertStrategy": {"autoClose": "86400s"}, "conditions": [{"displayName": name,
                "conditionThreshold": {"filter": resource + f' AND metric.type="{metric}"',
                    "comparison": "COMPARISON_GT", "thresholdValue": threshold, "duration": duration,
                    "trigger": {"count": 1}, "aggregations": [{"alignmentPeriod": "60s",
                        "perSeriesAligner": aligner, "crossSeriesReducer": reducer}]}}],
            "documentation": {"mimeType": "text/markdown", "content":
                "Revisar la revision desplegada, logs por request_id, conexiones y almacenamiento. "
                "Los datos pueden tardar varios minutos en aparecer. Probar recepcion en el canal real antes de habilitar produccion."}}
        path.write_text(json.dumps(policy, indent=2), encoding="utf-8")
    print("Cinco politicas generadas para revision. No se publicaron recursos.")


if __name__ == "__main__": main()
