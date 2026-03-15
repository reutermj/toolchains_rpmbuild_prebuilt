#!/bin/bash
set -euox pipefail

DATE=$(grep -o 'version = "[^"]*"' MODULE.bazel | cut -d '"' -f 2 | head -n 1)
SRC_TAR="toolchains_rpmbuild_prebuilt-$DATE.tar.gz"
gh release create "$DATE" \
  $SRC_TAR \
  --title "$DATE" \
  --notes "### Installation
\`\`\`python
bazel_dep(name = \"toolchains_rpmbuild_prebuilt\", version = \"$DATE\")

prebuilt_rpmbuild_toolchain = use_repo_rule(
    \"@toolchains_rpmbuild_prebuilt//:defs.bzl\",
    \"prebuilt_rpmbuild_toolchain\",
)
prebuilt_rpmbuild_toolchain(name = \"rpmbuild\")
register_toolchains(\"@rpmbuild\")
\`\`\`"
