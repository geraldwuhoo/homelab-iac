#!/usr/bin/env bash

# Mirrors GitLab object storage from the bundled MinIO chart to the onsite RGW,
# by running rclone as a Job inside the cluster. Runs in-cluster on purpose:
# `kubectl port-forward` drops the connection under rclone's concurrency.
#
# Usage:
#   ./sync-minio-to-rgw.sh                       # mirror the default bucket list
#   ./sync-minio-to-rgw.sh registry              # mirror a single bucket
#   MODE=check ./sync-minio-to-rgw.sh registry   # compare without writing
#   MODE=copy ./sync-minio-to-rgw.sh             # never delete on the destination
#   EXTRA_FLAGS='--dry-run' ./sync-minio-to-rgw.sh      # preview, write nothing
#
# EXTRA_FLAGS is appended to the rclone invocation. Do NOT use it to filter away
# BadDigest failures (--min-size 1 and friends). Those errors are the source
# telling you it is serving bytes that no longer match its own stored checksum;
# filtering them migrates a silently damaged copy and destroys the evidence.
# Every object rclone does copy has had its MD5 verified end to end, so a clean
# run is an integrity proof -- keep it that way and fix bad objects at the
# source: identify, delete, regenerate, then re-run.
#
# MinIO is the source of truth until the cutover, so MODE=sync (the default)
# makes RGW match it exactly, including deletes -- artifacts that expired out of
# MinIO after an earlier copy would otherwise linger in RGW unreferenced.
#
# Buckets whose MinIO side is empty are skipped rather than mirrored: the bucket
# names differ between the two systems (MinIO has gitlab-backups, RGW has
# gitlab-backup-storage holding the backup tarball), and an empty source would
# otherwise wipe the destination. MAX_DELETE aborts a run that would delete more
# than expected.

set -euo pipefail

MODE="${MODE:-sync}"
IMAGE="${IMAGE:-docker.io/rclone/rclone:1.75.1}"
NAMESPACE="${NAMESPACE:-gitlab}"
TRANSFERS="${TRANSFERS:-4}"
CHECKERS="${CHECKERS:-16}"
CHUNK_SIZE="${CHUNK_SIZE:-16M}"
UPLOAD_CONCURRENCY="${UPLOAD_CONCURRENCY:-4}"
EXTRA_FLAGS="${EXTRA_FLAGS:-}"
MAX_DELETE="${MAX_DELETE:-1000}"

BUCKETS=("$@")
if [ ${#BUCKETS[@]} -eq 0 ]; then
    # Every bucket the chart is configured to use that exists on both sides.
    # registry, gitlab-artifacts, gitlab-uploads, git-lfs and runner-cache hold
    # data today; the rest are empty on both sides and will be skipped.
    BUCKETS=(
        registry
        gitlab-artifacts
        gitlab-uploads
        git-lfs
        runner-cache
        gitlab-packages
        gitlab-pages
        gitlab-mr-diffs
        gitlab-terraform-state
        gitlab-ci-secure-files
        gitlab-dependency-proxy
    )
fi

case "$MODE" in
    copy|sync|check) ;;
    *) echo "MODE must be copy, sync or check" >&2; exit 1 ;;
esac

delete_flag=""
[ "$MODE" = "sync" ] && delete_flag="--max-delete ${MAX_DELETE}"

job="minio-to-rgw-${MODE}-$(date +%s)"

# --size-only: every bucket here is immutable, content-addressed or write-once,
# and multipart ETags are not comparable MD5s across implementations.
# --s3-no-check-bucket: the RGW bucket policies grant object access only, not
# CreateBucket, so rclone must not try to create the destination bucket.
#
# --exclude '**/_uploads/**': registry upload staging (5.5k objects of abandoned
# in-progress pushes). Nothing references it, the registry purges it itself
# (uploadpurging, 168h), and a handful of those objects are corrupt -- zero
# length while still advertising their original ETag, which RGW rejects as
# BadDigest. Skipping the prefix drops that dead weight from every pass.
#
# No --fast-list: it enumerates both sides completely before transferring
# anything, which on MinIO's RBD-backed store means minutes of apparent
# inactivity on the 34k-object registry bucket. Listing incrementally starts
# moving data immediately.
#
# Peak upload buffer is transfers * upload-concurrency * chunk-size, so the
# defaults below hold ~256Mi in flight against the container's 4Gi limit.
# Raise them together with the limit, never alone.
read -r -d '' script <<EOF || true
set -u
failed=""
for bucket in ${BUCKETS[*]}; do
    if [ -z "\$(rclone lsf --max-depth 1 "minio:\$bucket" | head -n 1)" ]; then
        echo "=== \$bucket: source empty, skipping ==="
        continue
    fi
    echo "=== \$bucket: ${MODE} ==="
    if rclone ${MODE} "minio:\$bucket" "rgw:\$bucket" ${delete_flag} ${EXTRA_FLAGS} \\
        --size-only \\
        --exclude "**/_uploads/**" \\
        --s3-no-check-bucket \\
        --transfers ${TRANSFERS} \\
        --checkers ${CHECKERS} \\
        --s3-upload-concurrency ${UPLOAD_CONCURRENCY} \\
        --s3-chunk-size ${CHUNK_SIZE} \\
        --retries 5 \\
        --retries-sleep 10s \\
        --low-level-retries 20 \\
        --stats 30s \\
        --log-level INFO ; then
        echo "=== \$bucket: ok ==="
    else
        echo "=== \$bucket: FAILED (errors above) ==="
        failed="\$failed \$bucket"
    fi
done
if [ -n "\$failed" ]; then
    echo "=== finished, buckets with errors:\$failed ==="
    exit 1
fi
echo "=== done, all buckets clean ==="
EOF

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job}
  namespace: ${NAMESPACE}
spec:
  # rclone already retries each object 5 times internally, so job-level retries
  # mostly re-list the whole source for nothing. One retry covers a transient
  # node or pod failure without looping over permanently corrupt objects.
  backoffLimit: 1
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: rclone
        image: ${IMAGE}
        command: ["/bin/sh", "-c"]
        args:
        - |
${script:+$(printf '%s\n' "$script" | sed 's/^/          /')}
        env:
        - name: RCLONE_CONFIG_MINIO_TYPE
          value: s3
        - name: RCLONE_CONFIG_MINIO_PROVIDER
          value: Minio
        - name: RCLONE_CONFIG_MINIO_ENDPOINT
          value: http://gitlab-minio-svc.${NAMESPACE}.svc.cluster.local:9000
        - name: RCLONE_CONFIG_MINIO_REGION
          value: us-east-1
        - name: RCLONE_CONFIG_MINIO_FORCE_PATH_STYLE
          value: "true"
        - name: RCLONE_CONFIG_MINIO_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: gitlab-minio-secret
              key: accesskey
        - name: RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: gitlab-minio-secret
              key: secretkey
        - name: RCLONE_CONFIG_RGW_TYPE
          value: s3
        - name: RCLONE_CONFIG_RGW_PROVIDER
          value: Ceph
        - name: RCLONE_CONFIG_RGW_ENDPOINT
          value: https://s3.wuhoo.xyz
        - name: RCLONE_CONFIG_RGW_REGION
          value: default
        - name: RCLONE_CONFIG_RGW_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: gitlab-secret
              key: AWS_ACCESS_KEY_ID
        - name: RCLONE_CONFIG_RGW_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: gitlab-secret
              key: AWS_SECRET_ACCESS_KEY
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            memory: 4Gi
EOF

echo "Job ${job} created; following logs (safe to ctrl-c, the job keeps running)"
kubectl wait --for=condition=ready pod -l "job-name=${job}" -n "${NAMESPACE}" --timeout=120s || true
kubectl logs -f -n "${NAMESPACE}" "job/${job}"
