#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
import tempfile
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
SHA_HEX_RE = re.compile(r"^[0-9a-f]{64}$")
FULL_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHORT_SHA_RE = re.compile(r"^[0-9a-f]{12}$")


def fail(message: str) -> "NoReturn":
    raise SystemExit(message)


def load_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path: str | Path, payload: Any) -> None:
    Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def shell_quote(value: str) -> str:
    if value == "":
        return "''"
    return shlex.quote(value)


def write_metadata_outputs(meta_env: dict[str, str], env_output: str | Path, json_output: str | Path) -> None:
    validate_flat_string_map(meta_env, "meta_env")
    lines = [f"{key}={shell_quote(value)}" for key, value in meta_env.items()]
    Path(env_output).write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_json(json_output, meta_env)


def validate_flat_string_map(obj: Any, label: str) -> dict[str, str]:
    if not isinstance(obj, dict):
        fail(f"{label} must be an object")
    out: dict[str, str] = {}
    for key, value in obj.items():
        if not isinstance(key, str) or not key:
            fail(f"{label} keys must be non-empty strings")
        if not isinstance(value, str):
            fail(f"{label}.{key} must be a string")
        out[key] = value
    return out


def ensure_non_empty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{label} must be a non-empty string")
    return value


def ensure_known_string(value: Any, label: str) -> str:
    value = ensure_non_empty_string(value, label)
    if value == "unknown":
        fail(f"{label} must not be 'unknown'")
    return value


def ensure_digest(value: Any, label: str) -> str:
    value = ensure_non_empty_string(value, label)
    if not DIGEST_RE.match(value):
        fail(f"{label} must be a sha256 digest")
    return value


def ensure_sha_hex(value: Any, label: str) -> str:
    value = ensure_non_empty_string(value, label)
    if not SHA_HEX_RE.match(value):
        fail(f"{label} must be a 64-char lowercase hex SHA256")
    return value


def ensure_short_sha(value: Any, label: str) -> str:
    value = ensure_known_string(value, label)
    if not SHORT_SHA_RE.match(value):
        fail(f"{label} must be a 12-char lowercase hex sha")
    return value


def ensure_full_sha(value: Any, label: str) -> str:
    value = ensure_non_empty_string(value, label)
    if not FULL_SHA_RE.match(value):
        fail(f"{label} must be a 40-char lowercase hex sha")
    return value


def ensure_positive_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or value <= 0:
        fail(f"{label} must be a positive integer")
    return value


def extract_digest_from_pinned_ref(ref: str, label: str) -> str:
    ensure_non_empty_string(ref, label)
    if "@" not in ref:
        fail(f"{label} must be a digest-pinned ref")
    digest = ref.rsplit("@", 1)[-1]
    return ensure_digest(digest, f"{label} digest")


def parse_channel_tags(value: str) -> list[str]:
    tags = [item for item in value.split() if item]
    if not tags:
        fail("channel tags must not be empty")
    return tags


def extract_tag_from_ref(artifact_repo: str, artifact_ref: str) -> str:
    prefix = f"{artifact_repo}:"
    if not artifact_ref.startswith(prefix):
        fail(f"artifact_ref {artifact_ref} does not start with {prefix}")
    return artifact_ref[len(prefix):]


def run(cmd: list[str], *, cwd: str | Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd is not None else None,
        check=check,
        text=True,
        capture_output=True,
    )


def oras_resolve(ref: str) -> str:
    completed = run(["oras", "resolve", ref], check=False)
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()


def oras_tag(pinned_ref: str, tag: str) -> None:
    run(["oras", "tag", pinned_ref, tag], check=True)


def oras_pull(ref: str, out_dir: str | Path) -> bool:
    completed = run(["oras", "pull", ref, "-o", str(out_dir)], check=False)
    return completed.returncode == 0


def oras_push_catalog(catalog_ref: str, catalog_artifact_type: str, catalog_dir: str | Path) -> None:
    run(
        [
            "oras",
            "push",
            catalog_ref,
            "--artifact-type",
            catalog_artifact_type,
            "catalog.tsv:text/tab-separated-values",
        ],
        cwd=catalog_dir,
        check=True,
    )


def validate_publish_record(record: Any, *, expected_role: str | None = None) -> dict[str, Any]:
    if not isinstance(record, dict):
        fail("artifact record must be an object")
    if record.get("schema") != 1:
        fail("artifact record schema must be 1")

    role = ensure_non_empty_string(record.get("artifact_role"), "artifact_role")
    if expected_role is not None and role != expected_role:
        fail(f"artifact_role must be {expected_role}, got {role}")

    ensure_known_string(record.get("artifact_kind"), "artifact_kind")
    ensure_known_string(record.get("artifact_type"), "artifact_type")
    artifact_repo = ensure_non_empty_string(record.get("artifact_repo"), "artifact_repo")
    artifact_ref = ensure_non_empty_string(record.get("artifact_ref"), "artifact_ref")
    artifact_pinned_ref = ensure_non_empty_string(record.get("artifact_pinned_ref"), "artifact_pinned_ref")
    artifact_digest = ensure_digest(record.get("artifact_digest"), "artifact_digest")
    payload_filename = ensure_non_empty_string(record.get("payload_filename"), "payload_filename")
    payload_sha256 = ensure_sha_hex(record.get("payload_sha256"), "payload_sha256")
    ensure_positive_int(record.get("payload_size_bytes"), "payload_size_bytes")
    control_fields = record.get("control_fields")
    if not isinstance(control_fields, dict):
        fail("control_fields must be an object")
    ensure_known_string(control_fields.get("version"), "control_fields.version")
    ensure_known_string(control_fields.get("variant"), "control_fields.variant")
    ensure_known_string(control_fields.get("target"), "control_fields.target")
    ensure_known_string(control_fields.get("sku"), "control_fields.sku")
    ensure_short_sha(control_fields.get("git_sha"), "control_fields.git_sha")
    if role == "os":
        ensure_digest(control_fields.get("platform_contract_digest"), "control_fields.platform_contract_digest")
        ensure_known_string(control_fields.get("k3s_version"), "control_fields.k3s_version")
    meta_env = validate_flat_string_map(record.get("meta_env"), "meta_env")

    if not artifact_ref.startswith(f"{artifact_repo}:"):
        fail("artifact_ref must be in the artifact_repo namespace")
    if not artifact_pinned_ref.startswith(f"{artifact_repo}@"):
        fail("artifact_pinned_ref must be in the artifact_repo namespace")
    if extract_digest_from_pinned_ref(artifact_pinned_ref, "artifact_pinned_ref") != artifact_digest:
        fail("artifact_pinned_ref digest does not match artifact_digest")
    if payload_filename == "":
        fail("payload_filename must not be empty")
    if payload_sha256.startswith("sha256:"):
        fail("payload_sha256 must not include the sha256: prefix")

    return record


def validate_candidate_provenance_object(payload: Any, *, expected_source_commit: str | None = None) -> dict[str, Any]:
    if not isinstance(payload, dict):
        fail("candidate provenance must be an object")
    if payload.get("schema") != 1:
        fail("candidate provenance schema must be 1")
    if payload.get("kind") != "candidate-provenance":
        fail("candidate provenance kind must be 'candidate-provenance'")

    source_repo = ensure_non_empty_string(payload.get("source_repo"), "source_repo")
    if not source_repo.startswith("https://github.com/"):
        fail("source_repo must be a GitHub https URL")
    source_commit = ensure_full_sha(payload.get("source_commit"), "source_commit")
    if expected_source_commit is not None and source_commit != expected_source_commit:
        fail(f"source_commit {source_commit} does not match expected {expected_source_commit}")

    ensure_non_empty_string(payload.get("candidate_workflow"), "candidate_workflow")
    ensure_non_empty_string(payload.get("candidate_run_id"), "candidate_run_id")
    ensure_non_empty_string(payload.get("candidate_run_attempt"), "candidate_run_attempt")

    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, dict):
        fail("artifacts must be an object")
    if "os" not in artifacts or "installer" not in artifacts:
        fail("candidate provenance must contain artifacts.os and artifacts.installer")

    os_record = validate_publish_record(artifacts["os"], expected_role="os")
    installer_record = validate_publish_record(artifacts["installer"], expected_role="installer")
    for field in ("version", "variant", "target", "sku", "git_sha"):
        os_value = os_record["control_fields"][field]
        installer_value = installer_record["control_fields"][field]
        if os_value != installer_value:
            fail(f"OS and installer control_fields.{field} differ: {os_value!r} != {installer_value!r}")
    if not source_commit.startswith(os_record["control_fields"]["git_sha"]):
        fail("source_commit does not begin with control_fields.git_sha")

    return payload


def build_candidate_provenance(
    source_repo_url: str,
    source_commit: str,
    candidate_workflow: str,
    candidate_run_id: str,
    candidate_run_attempt: str,
    os_record_path: str,
    installer_record_path: str,
    output_path: str,
) -> None:
    source_commit = ensure_full_sha(source_commit, "source_commit")
    ensure_non_empty_string(source_repo_url, "source_repo_url")
    ensure_non_empty_string(candidate_workflow, "candidate_workflow")
    ensure_non_empty_string(candidate_run_id, "candidate_run_id")
    ensure_non_empty_string(candidate_run_attempt, "candidate_run_attempt")

    os_record = validate_publish_record(load_json(os_record_path), expected_role="os")
    installer_record = validate_publish_record(load_json(installer_record_path), expected_role="installer")

    for field in ("version", "variant", "target", "sku", "git_sha"):
        os_value = os_record["control_fields"][field]
        installer_value = installer_record["control_fields"][field]
        if os_value != installer_value:
            fail(f"OS and installer control_fields.{field} differ: {os_value!r} != {installer_value!r}")
    if not source_commit.startswith(os_record["control_fields"]["git_sha"]):
        fail("source_commit does not begin with control_fields.git_sha")

    payload = {
        "schema": 1,
        "kind": "candidate-provenance",
        "source_repo": source_repo_url,
        "source_commit": source_commit,
        "candidate_workflow": candidate_workflow,
        "candidate_run_id": candidate_run_id,
        "candidate_run_attempt": candidate_run_attempt,
        "artifacts": {
            "os": os_record,
            "installer": installer_record,
        },
    }
    validate_candidate_provenance_object(payload)
    write_json(output_path, payload)


def build_catalog_header(sha_column: str) -> str:
    if sha_column not in {"img_sha256", "payload_sha256"}:
        fail("sha-column must be img_sha256 or payload_sha256")
    return "\t".join(
        [
            "channel",
            "tag",
            "created",
            "version",
            "variant",
            "target",
            "sku",
            "git_sha",
            "platform_contract_digest",
            "k3s_version",
            sha_column,
            "artifact_digest",
            "pinned_ref",
        ]
    )


def normalize_channel(channel_tag: str, target: str, channel_mode: str) -> str:
    if channel_mode == "target-qualified":
        return channel_tag
    if channel_mode == "short":
        prefix = f"{target}-"
        if channel_tag.startswith(prefix):
            return channel_tag[len(prefix):] or "custom"
        return channel_tag or "custom"
    fail("channel-mode must be target-qualified or short")


def find_catalog_file(catalog_dir: Path) -> Path:
    direct = catalog_dir / "catalog.tsv"
    if direct.is_file():
        return direct
    for candidate in catalog_dir.rglob("catalog.tsv"):
        return candidate
    return direct


def update_catalog_from_record(
    artifact_record: dict[str, Any],
    *,
    artifact_repo: str,
    catalog_tag: str,
    catalog_artifact_type: str,
    channel_tag: str,
    channel_mode: str,
    sha_column: str,
    timestamp: str,
    immutable_tag_override: str | None = None,
) -> None:
    record = validate_publish_record(artifact_record, expected_role="os")
    if record["artifact_repo"] != artifact_repo:
        fail(f"artifact record repo {record['artifact_repo']} does not match {artifact_repo}")

    header = build_catalog_header(sha_column)
    immutable_tag = immutable_tag_override or extract_tag_from_ref(record["artifact_repo"], record["artifact_ref"])
    channel = normalize_channel(channel_tag, record["control_fields"]["target"], channel_mode)
    pinned_ref = record["artifact_pinned_ref"]
    immutable_digest = record["artifact_digest"]
    control = record["control_fields"]
    payload_sha256 = record["payload_sha256"]

    with tempfile.TemporaryDirectory(prefix="release-control-catalog-") as tmpdir:
        catalog_dir = Path(tmpdir)
        catalog_ref = f"{artifact_repo}:{catalog_tag}"
        if oras_pull(catalog_ref, catalog_dir):
            catalog_file = find_catalog_file(catalog_dir)
        else:
            catalog_file = catalog_dir / "catalog.tsv"

        existing_rows: list[str] = []
        if catalog_file.is_file():
            existing_rows = catalog_file.read_text(encoding="utf-8").splitlines()
        rows = [line for line in existing_rows[1:] if line]
        rows = [line for line in rows if not line.startswith(f"{channel}\t{immutable_tag}\t")]
        rows.append(
            "\t".join(
                [
                    channel,
                    immutable_tag,
                    timestamp,
                    control["version"],
                    control["variant"],
                    control["target"],
                    control["sku"],
                    control["git_sha"],
                    control.get("platform_contract_digest", ""),
                    control.get("k3s_version", ""),
                    payload_sha256,
                    immutable_digest,
                    pinned_ref,
                ]
            )
        )
        catalog_file.write_text("\n".join([header, *rows]) + "\n", encoding="utf-8")
        oras_push_catalog(catalog_ref, catalog_artifact_type, catalog_file.parent)


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ensure_expected_artifact(
    artifact: dict[str, Any],
    *,
    expected_repo: str,
    expected_kind: str,
    expected_type: str,
    expected_target: str,
    expected_variant: str,
    expected_sku: str,
) -> None:
    checks = [
        ("artifact_repo", artifact["artifact_repo"], expected_repo),
        ("artifact_kind", artifact["artifact_kind"], expected_kind),
        ("artifact_type", artifact["artifact_type"], expected_type),
        ("control_fields.target", artifact["control_fields"]["target"], expected_target),
        ("control_fields.variant", artifact["control_fields"]["variant"], expected_variant),
        ("control_fields.sku", artifact["control_fields"]["sku"], expected_sku),
    ]
    for label, actual, expected in checks:
        if actual != expected:
            fail(f"{label} mismatch: expected {expected!r}, got {actual!r}")


def write_promote_outputs(
    *,
    artifact: dict[str, Any],
    deploy_dir: Path,
    role_prefix: str,
    artifact_repo: str,
    immutable_tag: str,
    source_commit: str,
    source_repo: str,
    candidate_run_id: str,
    promotion_context: str,
    release_tag: str,
    channel_tags: list[str],
) -> None:
    deploy_dir.mkdir(parents=True, exist_ok=True)
    ref = f"{artifact_repo}:{immutable_tag}"
    pinned_ref = artifact["artifact_pinned_ref"]
    digest = artifact["artifact_digest"]
    source_ref = artifact["artifact_ref"]

    (deploy_dir / f"{role_prefix}-artifact.ref").write_text(f"{ref}\n", encoding="utf-8")
    (deploy_dir / f"{role_prefix}-artifact.pinned.ref").write_text(f"{pinned_ref}\n", encoding="utf-8")
    (deploy_dir / f"{role_prefix}-artifact.digest").write_text(f"{digest}\n", encoding="utf-8")
    (deploy_dir / f"{role_prefix}-artifact.promote.source.ref").write_text(f"{source_ref}\n", encoding="utf-8")
    write_metadata_outputs(
        validate_flat_string_map(artifact["meta_env"], "meta_env"),
        deploy_dir / f"{role_prefix}-artifact.meta.env",
        deploy_dir / f"{role_prefix}-artifact.meta.json",
    )
    promote_json = {
        "schema": 1,
        "artifact_role": artifact["artifact_role"],
        "promotion_context": promotion_context,
        "release_tag": release_tag,
        "source_repo": source_repo,
        "source_commit": source_commit,
        "candidate_run_id": candidate_run_id,
        "source_ref": source_ref,
        "artifact_pinned_ref": pinned_ref,
        "artifact_digest": digest,
        "target_immutable_tag": immutable_tag,
        "channel_tags": channel_tags,
        "promoted_at": now_utc(),
    }
    write_json(deploy_dir / f"{role_prefix}-artifact.promote.json", promote_json)


def promote_common_checks(
    provenance: dict[str, Any],
    *,
    artifact_key: str,
    expected_repo: str,
    expected_kind: str,
    expected_type: str,
    expected_target: str,
    expected_variant: str,
    expected_sku: str,
) -> dict[str, Any]:
    artifact = deepcopy(provenance["artifacts"][artifact_key])
    validate_publish_record(artifact, expected_role=artifact_key if artifact_key == "os" else "installer")
    ensure_expected_artifact(
        artifact,
        expected_repo=expected_repo,
        expected_kind=expected_kind,
        expected_type=expected_type,
        expected_target=expected_target,
        expected_variant=expected_variant,
        expected_sku=expected_sku,
    )
    return artifact


def ensure_immutable_tag_available(artifact_repo: str, immutable_tag: str, expected_digest: str) -> None:
    existing = oras_resolve(f"{artifact_repo}:{immutable_tag}")
    if existing and existing != expected_digest:
        fail(
            f"Target immutable tag {artifact_repo}:{immutable_tag} already points to {existing}, "
            f"not {expected_digest}"
        )


def promote_os_from_provenance(
    provenance: dict[str, Any],
    *,
    release_tag: str,
    promotion_context: str,
    artifact_repo: str,
    expected_artifact_kind: str,
    expected_artifact_type: str,
    expected_target: str,
    expected_variant: str,
    expected_sku: str,
    immutable_tag: str,
    channel_tags: list[str],
    catalog_tag: str,
    catalog_artifact_type: str,
    channel_mode: str,
    sha_column: str,
    deploy_dir: Path,
) -> None:
    artifact = promote_common_checks(
        provenance,
        artifact_key="os",
        expected_repo=artifact_repo,
        expected_kind=expected_artifact_kind,
        expected_type=expected_artifact_type,
        expected_target=expected_target,
        expected_variant=expected_variant,
        expected_sku=expected_sku,
    )
    ensure_immutable_tag_available(artifact_repo, immutable_tag, artifact["artifact_digest"])

    pinned_ref = artifact["artifact_pinned_ref"]
    oras_tag(pinned_ref, immutable_tag)
    for channel_tag in channel_tags:
        oras_tag(pinned_ref, channel_tag)
        update_catalog_from_record(
            artifact,
            artifact_repo=artifact_repo,
            catalog_tag=catalog_tag,
            catalog_artifact_type=catalog_artifact_type,
            channel_tag=channel_tag,
            channel_mode=channel_mode,
            sha_column=sha_column,
            timestamp=now_utc(),
            immutable_tag_override=immutable_tag,
        )

    write_promote_outputs(
        artifact=artifact,
        deploy_dir=deploy_dir,
        role_prefix="os",
        artifact_repo=artifact_repo,
        immutable_tag=immutable_tag,
        source_commit=provenance["source_commit"],
        source_repo=provenance["source_repo"],
        candidate_run_id=provenance["candidate_run_id"],
        promotion_context=promotion_context,
        release_tag=release_tag,
        channel_tags=channel_tags,
    )


def promote_installer_from_provenance(
    provenance: dict[str, Any],
    *,
    release_tag: str,
    promotion_context: str,
    artifact_repo: str,
    expected_artifact_kind: str,
    expected_artifact_type: str,
    expected_target: str,
    expected_variant: str,
    expected_sku: str,
    immutable_tag: str,
    channel_tags: list[str],
    deploy_dir: Path,
) -> None:
    artifact = promote_common_checks(
        provenance,
        artifact_key="installer",
        expected_repo=artifact_repo,
        expected_kind=expected_artifact_kind,
        expected_type=expected_artifact_type,
        expected_target=expected_target,
        expected_variant=expected_variant,
        expected_sku=expected_sku,
    )
    ensure_immutable_tag_available(artifact_repo, immutable_tag, artifact["artifact_digest"])

    pinned_ref = artifact["artifact_pinned_ref"]
    oras_tag(pinned_ref, immutable_tag)
    for channel_tag in channel_tags:
        oras_tag(pinned_ref, channel_tag)

    write_promote_outputs(
        artifact=artifact,
        deploy_dir=deploy_dir,
        role_prefix="installer",
        artifact_repo=artifact_repo,
        immutable_tag=immutable_tag,
        source_commit=provenance["source_commit"],
        source_repo=provenance["source_repo"],
        candidate_run_id=provenance["candidate_run_id"],
        promotion_context=promotion_context,
        release_tag=release_tag,
        channel_tags=channel_tags,
    )


def cmd_write_metadata(args: argparse.Namespace) -> int:
    meta_env = validate_flat_string_map(load_json(args.input_json), "input-json")
    write_metadata_outputs(meta_env, args.env_output, args.json_output)
    return 0


def cmd_build_candidate_provenance(args: argparse.Namespace) -> int:
    build_candidate_provenance(
        args.source_repo_url,
        args.source_commit,
        args.candidate_workflow,
        args.candidate_run_id,
        args.candidate_run_attempt,
        args.os_record,
        args.installer_record,
        args.output,
    )
    return 0


def cmd_validate_candidate_provenance(args: argparse.Namespace) -> int:
    validate_candidate_provenance_object(load_json(args.input), expected_source_commit=args.expected_source_commit)
    return 0


def cmd_update_catalog(args: argparse.Namespace) -> int:
    update_catalog_from_record(
        load_json(args.artifact_record),
        artifact_repo=args.artifact_repo,
        catalog_tag=args.catalog_tag,
        catalog_artifact_type=args.catalog_artifact_type,
        channel_tag=args.channel_tag,
        channel_mode=args.channel_mode,
        sha_column=args.sha_column,
        timestamp=args.timestamp,
    )
    return 0


def load_validated_provenance(path: str, expected_source_commit: str | None = None) -> dict[str, Any]:
    return validate_candidate_provenance_object(load_json(path), expected_source_commit=expected_source_commit)


def cmd_promote_os(args: argparse.Namespace) -> int:
    provenance = load_validated_provenance(args.provenance)
    promote_os_from_provenance(
        provenance,
        release_tag=args.release_tag,
        promotion_context=args.promotion_context,
        artifact_repo=args.artifact_repo,
        expected_artifact_kind=args.expected_artifact_kind,
        expected_artifact_type=args.expected_artifact_type,
        expected_target=args.expected_target,
        expected_variant=args.expected_variant,
        expected_sku=args.expected_sku,
        immutable_tag=args.immutable_tag,
        channel_tags=parse_channel_tags(args.channel_tags),
        catalog_tag=args.catalog_tag,
        catalog_artifact_type=args.catalog_artifact_type,
        channel_mode=args.channel_mode,
        sha_column=args.sha_column,
        deploy_dir=Path(args.deploy_dir),
    )
    return 0


def cmd_promote_installer(args: argparse.Namespace) -> int:
    provenance = load_validated_provenance(args.provenance)
    promote_installer_from_provenance(
        provenance,
        release_tag=args.release_tag,
        promotion_context=args.promotion_context,
        artifact_repo=args.artifact_repo,
        expected_artifact_kind=args.expected_artifact_kind,
        expected_artifact_type=args.expected_artifact_type,
        expected_target=args.expected_target,
        expected_variant=args.expected_variant,
        expected_sku=args.expected_sku,
        immutable_tag=args.immutable_tag,
        channel_tags=parse_channel_tags(args.channel_tags),
        deploy_dir=Path(args.deploy_dir),
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Shared release-control helpers for downstream image repos.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    write_metadata_parser = subparsers.add_parser("write-metadata")
    write_metadata_parser.add_argument("--input-json", required=True)
    write_metadata_parser.add_argument("--env-output", required=True)
    write_metadata_parser.add_argument("--json-output", required=True)
    write_metadata_parser.set_defaults(func=cmd_write_metadata)

    build_candidate_parser = subparsers.add_parser("build-candidate-provenance")
    build_candidate_parser.add_argument("--source-repo-url", required=True)
    build_candidate_parser.add_argument("--source-commit", required=True)
    build_candidate_parser.add_argument("--candidate-workflow", required=True)
    build_candidate_parser.add_argument("--candidate-run-id", required=True)
    build_candidate_parser.add_argument("--candidate-run-attempt", required=True)
    build_candidate_parser.add_argument("--os-record", required=True)
    build_candidate_parser.add_argument("--installer-record", required=True)
    build_candidate_parser.add_argument("--output", required=True)
    build_candidate_parser.set_defaults(func=cmd_build_candidate_provenance)

    validate_candidate_parser = subparsers.add_parser("validate-candidate-provenance")
    validate_candidate_parser.add_argument("--input", required=True)
    validate_candidate_parser.add_argument("--expected-source-commit")
    validate_candidate_parser.set_defaults(func=cmd_validate_candidate_provenance)

    update_catalog_parser = subparsers.add_parser("update-catalog")
    update_catalog_parser.add_argument("--artifact-record", required=True)
    update_catalog_parser.add_argument("--artifact-repo", required=True)
    update_catalog_parser.add_argument("--catalog-tag", required=True)
    update_catalog_parser.add_argument("--catalog-artifact-type", required=True)
    update_catalog_parser.add_argument("--channel-tag", required=True)
    update_catalog_parser.add_argument("--channel-mode", required=True)
    update_catalog_parser.add_argument("--sha-column", required=True)
    update_catalog_parser.add_argument("--timestamp", required=True)
    update_catalog_parser.set_defaults(func=cmd_update_catalog)

    promote_os_parser = subparsers.add_parser("promote-os")
    promote_os_parser.add_argument("--provenance", required=True)
    promote_os_parser.add_argument("--release-tag", required=True)
    promote_os_parser.add_argument("--promotion-context", required=True)
    promote_os_parser.add_argument("--artifact-repo", required=True)
    promote_os_parser.add_argument("--expected-artifact-kind", required=True)
    promote_os_parser.add_argument("--expected-artifact-type", required=True)
    promote_os_parser.add_argument("--expected-target", required=True)
    promote_os_parser.add_argument("--expected-variant", required=True)
    promote_os_parser.add_argument("--expected-sku", required=True)
    promote_os_parser.add_argument("--immutable-tag", required=True)
    promote_os_parser.add_argument("--channel-tags", required=True)
    promote_os_parser.add_argument("--catalog-tag", required=True)
    promote_os_parser.add_argument("--catalog-artifact-type", required=True)
    promote_os_parser.add_argument("--channel-mode", required=True)
    promote_os_parser.add_argument("--sha-column", required=True)
    promote_os_parser.add_argument("--deploy-dir", required=True)
    promote_os_parser.set_defaults(func=cmd_promote_os)

    promote_installer_parser = subparsers.add_parser("promote-installer")
    promote_installer_parser.add_argument("--provenance", required=True)
    promote_installer_parser.add_argument("--release-tag", required=True)
    promote_installer_parser.add_argument("--promotion-context", required=True)
    promote_installer_parser.add_argument("--artifact-repo", required=True)
    promote_installer_parser.add_argument("--expected-artifact-kind", required=True)
    promote_installer_parser.add_argument("--expected-artifact-type", required=True)
    promote_installer_parser.add_argument("--expected-target", required=True)
    promote_installer_parser.add_argument("--expected-variant", required=True)
    promote_installer_parser.add_argument("--expected-sku", required=True)
    promote_installer_parser.add_argument("--immutable-tag", required=True)
    promote_installer_parser.add_argument("--channel-tags", required=True)
    promote_installer_parser.add_argument("--deploy-dir", required=True)
    promote_installer_parser.set_defaults(func=cmd_promote_installer)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
