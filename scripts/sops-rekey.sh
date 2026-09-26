#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "usage: $0 [-n] add|remove <age-recipient>[,<age-recipient>...] [path...]" >&2
    exit 1
}

dry_run=0
if [ "${1:-}" = "-n" ]; then
    dry_run=1
    shift
fi
[ $# -ge 2 ] || usage

action="$1"
keys="$2"
shift 2
case "$action" in
    add) flag="--add-age" ;;
    remove) flag="--rm-age" ;;
    *) usage ;;
esac

IFS=',' read -ra key_list <<< "$keys"
for key in "${key_list[@]}"; do
    [[ "$key" =~ ^age1[0-9a-z]{58}$ ]] || { echo "not an age recipient: $key" >&2; exit 1; }
done

cd "$(git rev-parse --show-toplevel)"

mapfile -t all_files < <(git grep -lE '(mac|sops_mac)"?[:=] ?"?ENC\[AES256_GCM' -- "${@:-.}")

targets=()
for file in "${all_files[@]}"; do
    mapfile -t recipients < <(grep -oE 'age1[0-9a-z]{58}' "$file" | sort -u)
    has_all=1
    has_any=0
    for key in "${key_list[@]}"; do
        if printf '%s\n' "${recipients[@]}" | grep -qxF "$key"; then
            has_any=1
        else
            has_all=0
        fi
    done
    if [ "$action" = add ] && [ $has_all -eq 0 ]; then
        targets+=("$file")
    elif [ "$action" = remove ] && [ $has_any -eq 1 ]; then
        remaining=$(printf '%s\n' "${recipients[@]}" | grep -vxF -f <(printf '%s\n' "${key_list[@]}") || true)
        if [ -z "$remaining" ]; then
            echo "refusing: $file would have no age recipients left" >&2
            exit 1
        fi
        targets+=("$file")
    fi
done

if [ ${#targets[@]} -eq 0 ]; then
    echo "nothing to do"
    exit 0
fi

printf '%s\n' "${targets[@]}"
echo "${#targets[@]} file(s) to $action $keys"
[ $dry_run -eq 1 ] && exit 0

failed=()
for file in "${targets[@]}"; do
    sops decrypt "$file" > /dev/null 2>&1 || failed+=("$file")
done
if [ ${#failed[@]} -gt 0 ]; then
    echo "cannot decrypt, nothing was changed:" >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi

for file in "${targets[@]}"; do
    echo "rekeying $file"
    sops rotate -i "$flag" "$keys" "$file"
done

for config in $(git ls-files '.sops.yaml' '**/.sops.yaml'); do
    for key in "${key_list[@]}"; do
        if [ "$action" = add ] && ! grep -qF "$key" "$config"; then
            echo "warning: $config does not list $key" >&2
        elif [ "$action" = remove ] && grep -qF "$key" "$config"; then
            echo "warning: $config still lists $key" >&2
        fi
    done
done
