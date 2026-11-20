#!/bin/sh
# Compute the next vX.Y.Z (patch bump of the latest tag, v1.0.0 if none) and
# write the files the github-release resource's put step reads.
set -eu

cd repo
sha="$(cat .git/ref 2>/dev/null || git rev-parse HEAD)"
latest="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)"

if [ -z "${latest}" ]; then
  next="v1.0.0"
else
  IFS=. read -r major minor patch <<EOF
${latest#v}
EOF
  next="v${major}.${minor}.$((patch + 1))"
fi

echo "Latest tag: ${latest:-none} -> next release: ${next} at ${sha}"

cd ..
echo "${next}" > release/name
echo "${next}" > release/tag
echo "${sha}" > release/commitish
printf 'Snowflake release %s\n\nCommit: %s\nPassed DEV (scripts + DCM). Deploys to UAT automatically; PROD after sign-off.\n' \
  "${next}" "${sha}" > release/body
