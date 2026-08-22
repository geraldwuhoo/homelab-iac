#!/usr/bin/env bash

set -euxo pipefail

s3="aws s3api --profile radosgw --endpoint-url=https://s3.wuhoo.xyz"

for dir in $(find . -maxdepth 1 -mindepth 1 -type d -printf '%f\n'); do
    $s3 create-bucket --bucket "$dir"
    $s3 put-bucket-policy --bucket "$dir" --policy "file://${dir}/policy.json"
    $s3 get-bucket-policy --bucket "$dir" --output text | jq
    $s3 put-bucket-lifecycle-configuration --bucket "$dir" --lifecycle-configuration "file://${dir}/lifecycle.json"
    $s3 get-bucket-lifecycle-configuration --bucket "$dir" | jq
done
