#!/usr/bin/env bash
# Copy the Tabard addon into the game's AddOns folder (fork-only tool).
#
# Usage: tools/deploy.sh [--yes] [TARGET]
#   TARGET defaults to $TABARD_ADDONS_DIR, then to the default game folder below.
#   TARGET must resolve to a folder named "Tabard" that is not a symlink and does
#   not contain or sit inside this repository. An existing target is backed up to
#   <Interface>/TabardBackups/Tabard-<YYYYmmdd-HHMMSS>/ before anything changes.
#   The new copy is built in a staging folder and swapped in only when complete.
#   Without --yes, a target lacking the .tabard-fork marker needs a "y" answer.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEFAULT_TARGET="/mnt/n/World of Warcraft/_forever_/Interface/AddOns/Tabard"
MARKER=".tabard-fork"

die() {
    echo "deploy.sh: error: $*" >&2
    exit 1
}

usage() {
    echo "Usage: $0 [--yes] [TARGET]" >&2
    echo "TARGET defaults to \$TABARD_ADDONS_DIR, then to: $DEFAULT_TARGET" >&2
}

command -v realpath >/dev/null 2>&1 || die "realpath is required but not installed"

assume_yes=0
have_target_arg=0
target_arg=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y)
            assume_yes=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            usage
            die "unknown option: $1"
            ;;
        *)
            [ "$have_target_arg" -eq 0 ] || { usage; die "only one TARGET may be given"; }
            have_target_arg=1
            target_arg="$1"
            ;;
    esac
    shift
done

# Target resolution: argument, then environment, then default.
if [ "$have_target_arg" -eq 1 ]; then
    target="$target_arg"
elif [ -n "${TABARD_ADDONS_DIR:-}" ]; then
    target="$TABARD_ADDONS_DIR"
else
    target="$DEFAULT_TARGET"
fi

# Guards. Everything after this point works on the resolved path only.
[ -n "$target" ] || die "target is empty"
case "$target" in
    /*) ;;
    *) target="$PWD/$target" ;;
esac
[ ! -L "$target" ] || die "refusing: target is a symbolic link ($target); pass the real folder"
target="$(realpath -m -- "$target")"
[ "$target" != "/" ] || die "refusing: target resolves to /"
[ "$(basename "$target")" = "Tabard" ] || die "refusing: target must be a folder named Tabard (resolved to '$target')"
if [ -e "$target" ] && [ ! -d "$target" ]; then
    die "target exists and is not a folder: $target"
fi
repo_real="$(realpath -e -- "$REPO_ROOT")"
case "$repo_real/" in
    "$target/"*) die "refusing: target would contain or equal the repository ($repo_real)" ;;
esac
case "$target/" in
    "$repo_real/"*) die "refusing: target is inside the repository ($repo_real)" ;;
esac

# Files and folders to ship. Nothing else from the repo is copied.
shopt -s nullglob
sources=()
for f in "$REPO_ROOT"/*.lua "$REPO_ROOT"/*.toc; do
    sources+=("$(basename "$f")")
done
[ -f "$REPO_ROOT/Tabard.toc" ] || die "missing from repo: Tabard.toc"
for f in Bindings.xml logo.tga LICENSE Libs; do
    [ -e "$REPO_ROOT/$f" ] || die "missing from repo: $f"
    sources+=("$f")
done

exists=0
if [ -d "$target" ]; then
    exists=1
fi

# Ask before replacing an install this script did not make, unless --yes.
if [ "$exists" -eq 1 ] && [ ! -f "$target/$MARKER" ] && [ "$assume_yes" -eq 0 ]; then
    printf 'Replace the Tabard in %s? [y/N] ' "$target"
    answer=""
    read -r answer || true
    case "$answer" in
        y|Y|yes|YES) ;;
        *)
            echo "Cancelled. Nothing was changed."
            exit 1
            ;;
    esac
fi

parent="$(dirname "$target")"
stamp="$(date +%Y%m%d-%H%M%S)"
staging=""
old_aside=""
backup=""

# On failure: put the previous folder back if it was moved aside, drop the
# staging folder, and say where the backup is. The target is only touched
# after the staging copy is complete, so a failed copy leaves it unchanged.
cleanup() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        if [ -n "$old_aside" ] && [ -e "$old_aside" ] && [ ! -e "$target" ]; then
            mv -- "$old_aside" "$target" || echo "deploy.sh: could not restore $target from $old_aside" >&2
        fi
        if [ -n "$staging" ] && [ -e "$staging" ]; then
            rm -rf -- "$staging"
        fi
        if [ -n "$backup" ]; then
            echo "deploy.sh: failed (status $rc). The previous folder is backed up at: $backup" >&2
        fi
    fi
    exit "$rc"
}
trap cleanup EXIT

# Back up the existing folder first.
if [ "$exists" -eq 1 ]; then
    backups_dir="$(dirname "$parent")/TabardBackups"
    backup_path="$backups_dir/Tabard-$stamp"
    n=2
    while [ -e "$backup_path" ]; do
        backup_path="$backups_dir/Tabard-$stamp-$n"
        n=$((n + 1))
    done
    mkdir -p "$backup_path"
    cp -a "$target/." "$backup_path/"
    backup="$backup_path"
    echo "Backed up existing folder to: $backup"
fi

# Build the new copy beside the target, then check it is complete.
mkdir -p "$parent"
staging="$(mktemp -d "$parent/.Tabard.staging-$stamp-XXXXXX")"
chmod 755 "$staging"
for s in "${sources[@]}"; do
    cp -R -- "$REPO_ROOT/$s" "$staging/$s"
done
printf 'Installed from %s at %s\n' "$REPO_ROOT" "$(date '+%Y-%m-%d %H:%M:%S')" > "$staging/$MARKER"
[ -f "$staging/Tabard.toc" ] || die "staging copy is incomplete (no Tabard.toc)"

# Entries in the old folder that are no longer part of the addon.
removed=()
if [ "$exists" -eq 1 ]; then
    while IFS= read -r -d '' entry; do
        name="$(basename "$entry")"
        [ "$name" = "$MARKER" ] && continue
        keep=0
        for s in "${sources[@]}"; do
            if [ "$s" = "$name" ]; then
                keep=1
                break
            fi
        done
        if [ "$keep" -eq 0 ]; then
            removed+=("$name")
        fi
    done < <(find "$target" -mindepth 1 -maxdepth 1 -print0)

    # Move the old folder aside (it is already backed up), then swap in the new one.
    old_aside="$(mktemp -u "$parent/.Tabard.old-XXXXXX")"
    mv -- "$target" "$old_aside"
fi
mv -- "$staging" "$target"
staging=""
if [ -n "$old_aside" ]; then
    rm -rf -- "$old_aside"
    old_aside=""
fi

echo "Copied ${#sources[@]} items to: $target"
if [ "${#removed[@]}" -gt 0 ]; then
    echo "Removed stale entries: ${removed[*]}"
fi
echo "Done."
