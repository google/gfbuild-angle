#!/usr/bin/env bash

# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x
set -e
set -u

WORK="$(pwd)"

uname

case "$(uname)" in
"Linux")
  GH_RELEASE_TOOL_ARCH="linux_amd64"
  BUILD_PLATFORM="Linux_x64"
  ;;

"Darwin")
  GH_RELEASE_TOOL_ARCH="darwin_amd64"
  BUILD_PLATFORM="Mac_x64"
  brew install md5sha1sum
  ;;

"MINGW"*)
  GH_RELEASE_TOOL_ARCH="windows_amd64"
  BUILD_PLATFORM="Windows_x64"
  choco install zip
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

###### START EDIT ######
TARGET_REPO_ORG="angle"
TARGET_REPO_NAME="angle"
BUILD_REPO_ORG="google"
BUILD_REPO_NAME="gfbuild-angle"
###### END EDIT ######

COMMIT_ID="$(cat "${WORK}/COMMIT_ID")"

ARTIFACT="${BUILD_REPO_NAME}"
ARTIFACT_VERSION="${COMMIT_ID}"
GROUP_DOTS="github.${BUILD_REPO_ORG}"
GROUP_SLASHES="github/${BUILD_REPO_ORG}"
TAG="${GROUP_SLASHES}/${ARTIFACT}/${ARTIFACT_VERSION}"

BUILD_REPO_SHA="${GITHUB_SHA}"
CLASSIFIER="${BUILD_PLATFORM}_${CONFIG}"
POM_FILE="${BUILD_REPO_NAME}-${ARTIFACT_VERSION}.pom"
INSTALL_DIR="${ARTIFACT}-${ARTIFACT_VERSION}-${CLASSIFIER}"

GH_RELEASE_TOOL_USER="c4milo"
GH_RELEASE_TOOL_VERSION="v1.1.0"

mkdir -p "${HOME}/bin"

export PATH="${HOME}/bin:$PATH"

pushd "${HOME}/bin"

# Install github-release.
curl -fsSL -o github-release.tar.gz "https://github.com/${GH_RELEASE_TOOL_USER}/github-release/releases/download/${GH_RELEASE_TOOL_VERSION}/github-release_${GH_RELEASE_TOOL_VERSION}_${GH_RELEASE_TOOL_ARCH}.tar.gz"
tar xf github-release.tar.gz

ls

popd

# Install depot_tools.
pushd "${HOME}"

case "$(uname)" in
"Linux")
  ENABLE_VULKAN="true"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  ;;

"Darwin")
  ENABLE_VULKAN="false"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  ;;

"MINGW"*)
  ENABLE_VULKAN="true"
  # Needed for depot_tools on Windows.
  export DEPOT_TOOLS_WIN_TOOLCHAIN=0

  curl -fsSL -o depot_tools.zip https://storage.googleapis.com/chrome-infra/depot_tools.zip
  # For some reason, unzip says we will "overwrite" a file. So we use 7z.
  7z x depot_tools.zip -odepot_tools
  ls depot_tools

  NEW_PATH=$(python "${WORK}/remove_from_path.py" python python2 python27 python3 pip pip3 ninja Ninja cmake CMake gcc)
  NEW_PATH_UNIX="$(cygpath -u -p "${NEW_PATH}")"
  PATH="${NEW_PATH_UNIX}"
  export PATH

  gclient.bat
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

popd
export PATH="${HOME}/depot_tools:${PATH}"

###### START EDIT ######
git clone "https://chromium.googlesource.com/${TARGET_REPO_ORG}/${TARGET_REPO_NAME}" "${TARGET_REPO_NAME}"
cd "${TARGET_REPO_NAME}"
git checkout "${COMMIT_ID}"

python.exe scripts/bootstrap.py
gclient.bat sync

###### END EDIT ######

###### BEGIN BUILD ######
IS_DEBUG="false"
if test "${CONFIG}" = "Debug"; then
  IS_DEBUG="true"
fi

gn.bat gen "out/${CONFIG}" "--args=is_debug=${IS_DEBUG} target_cpu=\"x64\" angle_enable_vulkan=${ENABLE_VULKAN} angle_enable_metal=false"
command -v ninja || true
command -v ninja.exe || true
command -v ninja.bat || true

autoninja.bat -C "out/${CONFIG}" libEGL libGLESv2 libGLESv1_CM shader_translator || true

echo ...

ninja.exe -C "out/${CONFIG}" libEGL libGLESv2 libGLESv1_CM shader_translator || true

###### END BUILD ######

###### START EDIT ######

# There are no install steps in the ANGLE build, so copy files manually.

mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/lib"

cp "out/${CONFIG}/libEGL"* "${INSTALL_DIR}/lib/"
cp "out/${CONFIG}/libGLES"* "${INSTALL_DIR}/lib/"
cp "out/${CONFIG}/shader_translator"* "${INSTALL_DIR}/bin/"

for f in "${INSTALL_DIR}/bin/"* "${INSTALL_DIR}/lib/"*; do
  echo "${BUILD_REPO_SHA}">"${f}.build-version"
  cp "${WORK}/COMMIT_ID" "${f}.version"
done

###### END EDIT ######

GRAPHICSFUZZ_COMMIT_SHA="b82cf495af1dea454218a332b88d2d309657594d"
OPEN_SOURCE_LICENSES_URL="https://github.com/google/gfbuild-graphicsfuzz/releases/download/github/google/gfbuild-graphicsfuzz/${GRAPHICSFUZZ_COMMIT_SHA}/OPEN_SOURCE_LICENSES.TXT"

# Add licenses file.
curl -fsSL -o OPEN_SOURCE_LICENSES.TXT "${OPEN_SOURCE_LICENSES_URL}"
cp OPEN_SOURCE_LICENSES.TXT "${INSTALL_DIR}/"

# zip file.
pushd "${INSTALL_DIR}"
zip -r "../${INSTALL_DIR}.zip" ./*
popd

sha1sum "${INSTALL_DIR}.zip" >"${INSTALL_DIR}.zip.sha1"

# POM file.
sed -e "s/@GROUP@/${GROUP_DOTS}/g" -e "s/@ARTIFACT@/${ARTIFACT}/g" -e "s/@VERSION@/${ARTIFACT_VERSION}/g" "../fake_pom.xml" >"${POM_FILE}"

sha1sum "${POM_FILE}" >"${POM_FILE}.sha1"

DESCRIPTION="$(echo -e "Automated build for ${TARGET_REPO_NAME} version ${COMMIT_ID}.\n$(git log --graph -n 3 --abbrev-commit --pretty='format:%h - %s <%an>')")"

# Only release from master branch commits.
# shellcheck disable=SC2153
if test "${GITHUB_REF}" != "refs/heads/master"; then
  exit 0
fi

# We do not use the GITHUB_TOKEN provided by GitHub Actions.
# We cannot set enviroment variables or secrets that start with GITHUB_ in .yml files,
# but the github-release tool requires GITHUB_TOKEN, so we set it here.
export GITHUB_TOKEN="${GH_TOKEN}"

github-release \
  "${BUILD_REPO_ORG}/${BUILD_REPO_NAME}" \
  "${TAG}" \
  "${BUILD_REPO_SHA}" \
  "${DESCRIPTION}" \
  "${INSTALL_DIR}.zip"

github-release \
  "${BUILD_REPO_ORG}/${BUILD_REPO_NAME}" \
  "${TAG}" \
  "${BUILD_REPO_SHA}" \
  "${DESCRIPTION}" \
  "${INSTALL_DIR}.zip.sha1"

# Don't fail if pom cannot be uploaded, as it might already be there.

github-release \
  "${BUILD_REPO_ORG}/${BUILD_REPO_NAME}" \
  "${TAG}" \
  "${BUILD_REPO_SHA}" \
  "${DESCRIPTION}" \
  "${POM_FILE}" || true

github-release \
  "${BUILD_REPO_ORG}/${BUILD_REPO_NAME}" \
  "${TAG}" \
  "${BUILD_REPO_SHA}" \
  "${DESCRIPTION}" \
  "${POM_FILE}.sha1" || true

# Don't fail if OPEN_SOURCE_LICENSES.TXT cannot be uploaded, as it might already be there.

github-release \
  "${BUILD_REPO_ORG}/${BUILD_REPO_NAME}" \
  "${TAG}" \
  "${BUILD_REPO_SHA}" \
  "${DESCRIPTION}" \
  "OPEN_SOURCE_LICENSES.TXT" || true
