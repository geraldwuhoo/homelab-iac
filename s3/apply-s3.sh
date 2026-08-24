#!/usr/bin/env bash

set -euxo pipefail

s3="aws s3api --profile radosgw --endpoint-url=https://s3.wuhoo.xyz"

for dir in $(find . -maxdepth 1 -mindepth 1 -type d -printf '%f\n'); do
    $s3 create-bucket --bucket "$dir"
    [ -f ${dir}/policy.json ] && \
        $s3 put-bucket-policy --bucket "$dir" --policy "file://${dir}/policy.json"
    [ -f ${dir}/lifecycle.json ] && \
        $s3 put-bucket-lifecycle-configuration --bucket "$dir" --lifecycle-configuration "file://${dir}/lifecycle.json"
done
