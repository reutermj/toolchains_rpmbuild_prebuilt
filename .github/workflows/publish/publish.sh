#!/bin/bash
set -euox pipefail

DATE=$(grep -o 'version = "[^"]*"' MODULE.bazel | cut -d '"' -f 2 | head -n 1)
SRC_TAR="toolchains_rpmbuild_prebuilt-$DATE.tar.gz"
gh release create "$DATE" \
  $SRC_TAR \
  --title "$DATE" \
  --notes "### Installation
\`\`\`
bazel_dep(name = \"toolchains_rpmbuild_prebuilt\", version = \"$DATE\")
register_toolchains(\"@toolchains_rpmbuild_prebuilt\")
\`\`\`"
