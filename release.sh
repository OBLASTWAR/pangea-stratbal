#!/usr/bin/env bash
# release.sh -- publish a Fish Map Script release on GitHub.
#
#   ./release.sh 1.1                  new version v1.1
#   ./release.sh 1.1 --notes "..."    with custom release notes
#   ./release.sh 1.1 --dry-run        build + check the zip, change nothing
#   ./release.sh --rebuild 1.0        re-publish an existing version from HEAD
#                                     (moves the tag, replaces the zip; refuses
#                                     unless the files are identical to the
#                                     zip already published)
#
# What players get, and what kek-mod's installer relies on:
#   * FishMapScript-v<version>.zip, the release's ONLY asset (installers
#     take the first asset whatever its name), holding a single folder
#     "Fish Map Script/" with the .lua files and the .modinfo -- unzipped
#     straight into Assets/Maps. The folder name must stay exactly that:
#     every kek-mod installer ever shipped checks for "Fish Map Script" to
#     decide whether the map is installed, so a versioned folder name would
#     get old installers adding a second copy next to the first. The
#     version shows in the zip's name (and the .modinfo's) instead.
#   * The installer reads the installed version off the .modinfo's file name
#     ("VFishMapScriptv1.1.modinfo" -> v1.1) and compares it with the
#     release tag, so the two MUST match or players see UPDATE forever. A new
#     version therefore renames the .modinfo (git mv) and commits that first.
#   * Files ship with CRLF line endings (the repo stores LF). That reproduces
#     the copy the community already has byte for byte.
#   * Zip paths use "/" (the original v1.0 zip used "\", a Windows
#     PowerShell quirk some tools can't read).
#
# Needs git, gh (signed in) and python3.

set -euo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

REBUILD=0; DRY=0; NOTES=""; VER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rebuild) REBUILD=1 ;;
        --dry-run) DRY=1 ;;
        --notes) shift; NOTES="${1:?--notes needs text}" ;;
        -h|--help) usage ;;
        -*) echo "Unknown option $1" >&2; usage ;;
        *) [ -z "$VER" ] || usage; VER="$1" ;;
    esac
    shift
done
[ -n "$VER" ] || usage
VER="${VER#v}"; VER="${VER#V}"
[[ "$VER" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Version must look like 1.1 (got '$VER')." >&2; exit 1; }
TAG="v$VER"
REPO="OBLASTWAR/pangea-stratbal"
BRANCH="master"
ASSET="FishMapScript-v$VER.zip"
MODINFO_NEW="VFishMapScriptv$VER.modinfo"
FOLDER="Fish Map Script"

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo "==> $*"; }

for c in git gh python3; do command -v "$c" >/dev/null || die "$c not found."; done
[ "$(git branch --show-current)" = "$BRANCH" ] || die "Not on $BRANCH."
[ -z "$(git status --porcelain)" ] || die "Working tree isn't clean -- commit or stash first."
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BRANCH")" ] \
    || die "$BRANCH isn't in sync with origin/$BRANCH -- pull/push first."

MODINFO_CUR="$(git ls-files 'VFishMapScriptv*.modinfo')"
[ "$(echo "$MODINFO_CUR" | grep -c .)" = 1 ] || die "Expected exactly one VFishMapScriptv*.modinfo, found: $MODINFO_CUR"

TAG_EXISTS=0
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 && TAG_EXISTS=1
if [ "$REBUILD" = 1 ]; then
    [ "$TAG_EXISTS" = 1 ] || die "$TAG isn't published -- drop --rebuild to release it as a new version."
    [ "$MODINFO_CUR" = "$MODINFO_NEW" ] \
        || die "HEAD has $MODINFO_CUR, not $MODINFO_NEW -- it isn't $TAG's content."
else
    [ "$TAG_EXISTS" = 0 ] || die "$TAG already exists -- pick a new version, or --rebuild $VER."
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Package: CRLF, "/" paths, one "Fish Map Script/" folder ──────────────────
# Takes the .lua/.modinfo files from git (not the working tree), so nothing
# untracked can slip in. With --refresh-md5, also rewrites the md5="..."
# entries in the .modinfo to match the CRLF bytes being shipped (done for
# new versions only -- a rebuild must reproduce the old files exactly).
cat > "$WORK/pack.py" <<'PY'
import hashlib, re, subprocess, sys, zipfile
out, refresh, folder = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
names = [n for n in subprocess.check_output(["git", "ls-files"], text=True).splitlines()
         if n.lower().endswith((".lua", ".modinfo")) and "/" not in n]
def crlf(b):
    return b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
data = {n: crlf(open(n, "rb").read()) for n in names}
if refresh:
    for n in names:
        if n.lower().endswith(".modinfo"):
            def fix(m):
                f = m.group(3)
                if f not in data:
                    sys.exit("modinfo lists %s, which isn't in the repo" % f)
                return m.group(1) + hashlib.md5(data[f]).hexdigest() + m.group(2) + f
            text = data[n].decode("utf-8-sig")
            text = re.sub(r'(md5=")[0-9a-fA-F]*("[^>]*>)([^<]+)', fix, text)
            data[n] = b"\xef\xbb\xbf" + text.encode("utf-8")
            open(n, "wb").write(data[n].replace(b"\r\n", b"\n"))  # repo copy stays LF
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for n in sorted(names, key=str.lower):
        z.writestr(zipfile.ZipInfo(folder + "/" + n, (2026, 1, 1, 0, 0, 0)), data[n], zipfile.ZIP_DEFLATED)
print("\n".join("    %8d  %s/%s" % (len(data[n]), folder, n) for n in sorted(names, key=str.lower)))
PY

# Compares the files inside two zips by file name and contents, ignoring
# "\" vs "/" separators.
cat > "$WORK/same.py" <<'PY'
import sys, zipfile
def files(p):
    with zipfile.ZipFile(p) as z:
        return {i.filename.replace("\\", "/"): z.read(i) for i in z.infolist() if not i.is_dir()}
a, b = files(sys.argv[1]), files(sys.argv[2])
bad = sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))
for n in bad:
    print("    differs: " + n)
sys.exit(1 if bad else 0)
PY

if [ "$REBUILD" = 1 ]; then
    step "Building $ASSET for $TAG from HEAD ($(git rev-parse --short HEAD))"
    python3 -I "$WORK/pack.py" "$WORK/$ASSET" 0 "$FOLDER"
    step "Comparing with the zip published on $TAG"
    OLD_ASSETS="$(gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name')"
    [ "$(echo "$OLD_ASSETS" | grep -c .)" = 1 ] || die "$TAG should have exactly one asset, has: $OLD_ASSETS"
    gh release download "$TAG" -R "$REPO" -p "$OLD_ASSETS" -O "$WORK/published.zip"
    python3 -I "$WORK/same.py" "$WORK/$ASSET" "$WORK/published.zip" \
        || die "HEAD's files differ from $TAG's published zip. Release them as a new version instead."
    echo "    identical."
    if [ "$DRY" = 1 ]; then step "Dry run -- stopping here."; exit 0; fi
    step "Moving tag $TAG to HEAD"
    git tag -f -a "$TAG" -m "$TAG" HEAD
    git push -f origin "refs/tags/$TAG"
    step "Replacing $OLD_ASSETS with $ASSET on the $TAG release"
    gh release upload "$TAG" "$WORK/$ASSET" -R "$REPO" --clobber
    # Installers take the first asset, so never leave two -- both are the
    # same files anyway, so the moment with two is harmless.
    [ "$OLD_ASSETS" = "$ASSET" ] || gh release delete-asset "$TAG" "$OLD_ASSETS" -R "$REPO" -y
    step "Done: https://github.com/$REPO/releases/tag/$TAG"
    exit 0
fi

# ── New version ──────────────────────────────────────────────────────────────
if [ "$DRY" = 1 ]; then
    step "Dry run: building $ASSET as it is now (no rename/md5 refresh)"
    python3 -I "$WORK/pack.py" "$WORK/$ASSET" 0 "$FOLDER"
    step "Dry run -- stopping here."
    exit 0
fi

if [ "$MODINFO_CUR" != "$MODINFO_NEW" ]; then
    step "Renaming $MODINFO_CUR -> $MODINFO_NEW"
    git mv "$MODINFO_CUR" "$MODINFO_NEW"
fi
step "Building $ASSET (refreshing the .modinfo md5s)"
python3 -I "$WORK/pack.py" "$WORK/$ASSET" 1 "$FOLDER"
git add -A -- '*.modinfo'
if ! git diff --cached --quiet; then
    step "Committing"
    git commit -q -m "Release $TAG"
fi
step "Tagging $TAG and pushing"
git tag -a "$TAG" -m "$TAG"
git push -q origin "$BRANCH" "refs/tags/$TAG"
step "Publishing the release"
[ -n "$NOTES" ] || NOTES="Fish Map Script $TAG. Unzip into Sid Meier's Civilization V/Assets/Maps/, or let kek-mod's installer do it."
gh release create "$TAG" "$WORK/$ASSET" -R "$REPO" --title "$TAG" --notes "$NOTES"
step "Done: https://github.com/$REPO/releases/tag/$TAG"
