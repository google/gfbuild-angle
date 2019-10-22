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

# build.yml provides: BACKEND
###### END EDIT ######

COMMIT_ID="$(cat "${WORK}/COMMIT_ID")"

ARTIFACT="${BUILD_REPO_NAME}"
ARTIFACT_VERSION="${COMMIT_ID}"
GROUP_DOTS="github.${BUILD_REPO_ORG}"
GROUP_SLASHES="github/${BUILD_REPO_ORG}"
TAG="${GROUP_SLASHES}/${ARTIFACT}/${ARTIFACT_VERSION}"

BUILD_REPO_SHA="${GITHUB_SHA}"
CLASSIFIER="${BUILD_PLATFORM}_${CONFIG}_${BACKEND}"
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
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  export PATH="${HOME}/depot_tools:${PATH}"
  ;;

"Darwin")
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  export PATH="${HOME}/depot_tools:${PATH}"
  ;;

"MINGW"*)
  # Needed for depot_tools on Windows.
  export DEPOT_TOOLS_WIN_TOOLCHAIN=0
  curl -fsSL -o depot_tools.zip https://storage.googleapis.com/chrome-infra/depot_tools.zip
  # For some reason, unzip says we will "overwrite" some files (e.g. ninja will overwrite ninja.exe). So we use 7z.
  7z x depot_tools.zip -odepot_tools

  # On Windows, we have to run gclient.bat at least once (with no arguments), which downloads python.bat (and other
  # tools) to depot_tools.
  # There are very weird issues with depot_tools on Windows if python, python27, ninja (and maybe others) are found
  # on your PATH; they can somehow end up getting used instead of the depot_tools versions.
  # To solve this, we remove elements from our PATH until these tools cannot be found.

  # We will restore the PATH later so we can use `zip`.
  OLD_PATH="${PATH}"

  # Removes elements from PATH until the given tools can no longer be found.
  NEW_PATH=$(python "${WORK}/remove_from_path.py" python python2 python27 python3 pip pip3 ninja cmake gcc)
  # Convert our path list (-p) to UNIX form (-u) since we are using bash.
  NEW_PATH_UNIX="$(cygpath -p -u "${NEW_PATH}")"
  export PATH="${NEW_PATH_UNIX}"

  gclient.bat

  export PATH="${HOME}/depot_tools:${PATH}"
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

popd

###### START EDIT ######
git clone "https://chromium.googlesource.com/${TARGET_REPO_ORG}/${TARGET_REPO_NAME}" "${TARGET_REPO_NAME}"
cd "${TARGET_REPO_NAME}"
git checkout "${COMMIT_ID}"

case "$(uname)" in
"Linux")
  python scripts/bootstrap.py
  gclient sync
  ;;

"Darwin")
  python scripts/bootstrap.py
  gclient sync
  ;;

"MINGW"*)
  python.bat scripts/bootstrap.py
  gclient.bat sync
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

###### END EDIT ######

###### BEGIN BUILD ######
IS_DEBUG="false"
if test "${CONFIG}" = "Debug"; then
  IS_DEBUG="true"
fi

GEN_ARGS="--args=is_debug=${IS_DEBUG} target_cpu=\"x64\" angle_enable_vulkan=true angle_enable_hlsl=true angle_enable_d3d9=false angle_enable_d3d11=false angle_enable_gl=false angle_enable_null=false angle_enable_metal=false angle_swiftshader=false"
TARGETS=(libEGL libGLESv2 libGLESv1_CM shader_translator)

case "$(uname)" in
"Linux")
  gn gen "out/${CONFIG}" "${GEN_ARGS}"
  autoninja -C "out/${CONFIG}" "${TARGETS[@]}"
  ;;

"Darwin")
  gn gen "out/${CONFIG}" "${GEN_ARGS}"
  autoninja -C "out/${CONFIG}" "${TARGETS[@]}"
  ;;

"MINGW"*)
  gn.bat gen "out/${CONFIG}" "${GEN_ARGS}"
  autoninja.bat -C "out/${CONFIG}" "${TARGETS[@]}"
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

###### END BUILD ######

###### START EDIT ######

# There are no install steps in the ANGLE build, so copy files manually.

ls "out/${CONFIG}/"

mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/lib"

cp "out/${CONFIG}/libEGL"* "${INSTALL_DIR}/lib/"
cp "out/${CONFIG}/libGLES"* "${INSTALL_DIR}/lib/"
cp "out/${CONFIG}/shader_translator"* "${INSTALL_DIR}/bin/"

# On Windows...
case "$(uname)" in
"Linux")
  ;;

"Darwin")
  ;;

"MINGW"*)
  # Remove .lib files.
  rm "${INSTALL_DIR}/lib/"*.lib
  # Restore PATH.
  export PATH="${OLD_PATH}"
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

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
