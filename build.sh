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

help | head

uname

case "$(uname)" in
"Linux")
  BUILD_PLATFORM="Linux_x64"
  PYTHON="python3"
  ;;

"Darwin")
  BUILD_PLATFORM="Mac_x64"
  PYTHON="python3"
  brew install md5sha1sum
  ;;

"MINGW"*|"MSYS_NT"*)
  BUILD_PLATFORM="Windows_x64"
  PYTHON="python"
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
ANGLE_INSTALL_DIR="${ARTIFACT}-${ARTIFACT_VERSION}-${CLASSIFIER}"
TRANSLATOR_INSTALL_DIR="${ARTIFACT}-${ARTIFACT_VERSION}-${CLASSIFIER}_Translator"

mkdir -p "${HOME}/bin"

export PATH="${HOME}/bin:$PATH"

pushd "${HOME}/bin"

# Install github-release-retry.
"${PYTHON}" -m pip install --user 'github-release-retry==1.*'

ls

popd

# Install depot_tools.
pushd "${HOME}"

case "$(uname)" in
"Linux")

  df -h
  sudo apt clean
  # shellcheck disable=SC2046
  docker rmi -f $(docker image ls -aq)
  sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/hostedtoolcache/boost /opt/ghc
  df -h

  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  export PATH="${HOME}/depot_tools:${PATH}"
  ;;

"Darwin")
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  export PATH="${HOME}/depot_tools:${PATH}"
  ;;

"MINGW"*|"MSYS_NT"*)
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

  export PATH="${HOME}/depot_tools:${PATH}"

  gclient.bat

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

# Manually create the .gclient file instead of executing scripts/bootstrap.py
# because, on Linux and Mac, the bootstrap .gclient file pulls in a huge number
# of Android dependencies that we don't need.
cat << END >.gclient
solutions = [
  { "name"        : '.',
    "url"         : 'https://chromium.googlesource.com/angle/angle.git',
    "deps_file"   : 'DEPS',
    "managed"     : False,
    "custom_deps" : {
    },
    "custom_vars": {},
  },
]
END

case "$(uname)" in
"Linux")
#  python3 scripts/bootstrap.py

  # Remove large, unneeded dependencies from the DEPS file.
  python3 ../remove_some_deps.py

  gclient sync
  ;;

"Darwin")
#  python3 scripts/bootstrap.py

  # Remove large, unneeded dependencies from the DEPS file.
  python3 ../remove_some_deps.py

  gclient sync
  ;;

"MINGW"*|"MSYS_NT"*)
#  python3.bat scripts/bootstrap.py

  # Remove large, unneeded dependencies from the DEPS file.
  python3.bat ../remove_some_deps.py

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

GEN_ARGS="--args=target_cpu=\"x64\" is_debug=${IS_DEBUG} is_component_build=false"
TARGETS=(angle angle_shader_translator)

case "$(uname)" in
"Linux")
  gn gen "out/${CONFIG}" "${GEN_ARGS}"
  cat "out/${CONFIG}/args.gn"
  autoninja -C "out/${CONFIG}" "${TARGETS[@]}"
  ;;

"Darwin")
  gn gen "out/${CONFIG}" "${GEN_ARGS}"
  cat "out/${CONFIG}/args.gn"
  autoninja -C "out/${CONFIG}" "${TARGETS[@]}"
  ;;

"MINGW"*|"MSYS_NT"*)
  gn.bat gen "out/${CONFIG}" "${GEN_ARGS}"
  cat "out/${CONFIG}/args.gn"
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

mkdir -p "${TRANSLATOR_INSTALL_DIR}/bin"

mkdir -p "${ANGLE_INSTALL_DIR}/lib"

# Copy ANGLE files.
case "$(uname)" in
"Linux")

  cp -r  \
    "out/${CONFIG}/"*.so \
    "out/${CONFIG}/vk_swiftshader_icd.json" \
    "out/${CONFIG}/angledata" \
    "${ANGLE_INSTALL_DIR}/lib/"

  ;;

"Darwin")

  cp -r  \
    "out/${CONFIG}/"*.dylib \
    "out/${CONFIG}/vk_swiftshader_icd.json" \
    "out/${CONFIG}/angledata" \
    "${ANGLE_INSTALL_DIR}/lib/"

  ;;

"MINGW"*|"MSYS_NT"*)

  cp -r  \
    "out/${CONFIG}/"*.dll \
    "out/${CONFIG}/"*.dll.* \
    "out/${CONFIG}/vk_swiftshader_icd.json" \
    "out/${CONFIG}/angledata" \
    "${ANGLE_INSTALL_DIR}/lib/"
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac


# Copy shader translator binary.
cp -r "out/${CONFIG}/angle_shader_translator"* "${TRANSLATOR_INSTALL_DIR}/bin/"

# On Windows...
case "$(uname)" in
"Linux")
  ;;

"Darwin")
  ;;

"MINGW"*|"MSYS_NT"*)
#  # Remove .lib files.
#  rm "${ANGLE_INSTALL_DIR}/lib/"*.lib
  # Restore PATH.
  export PATH="${OLD_PATH}"
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

for f in "${ANGLE_INSTALL_DIR}/lib/"*; do
  echo "${BUILD_REPO_SHA}">"${f}.build-version"
  cp "${WORK}/COMMIT_ID" "${f}.version"
done

for f in "${TRANSLATOR_INSTALL_DIR}/bin/"*; do
  echo "${BUILD_REPO_SHA}">"${f}.build-version"
  cp "${WORK}/COMMIT_ID" "${f}.version"
done


###### END EDIT ######

GRAPHICSFUZZ_COMMIT_SHA="b82cf495af1dea454218a332b88d2d309657594d"
OPEN_SOURCE_LICENSES_URL="https://github.com/google/gfbuild-graphicsfuzz/releases/download/github/google/gfbuild-graphicsfuzz/${GRAPHICSFUZZ_COMMIT_SHA}/OPEN_SOURCE_LICENSES.TXT"

# Add licenses file.
curl -fsSL -o OPEN_SOURCE_LICENSES.TXT "${OPEN_SOURCE_LICENSES_URL}"
cp OPEN_SOURCE_LICENSES.TXT "${ANGLE_INSTALL_DIR}/"
cp OPEN_SOURCE_LICENSES.TXT "${TRANSLATOR_INSTALL_DIR}/"

# zip file.
pushd "${ANGLE_INSTALL_DIR}"
zip -r "../${ANGLE_INSTALL_DIR}.zip" ./*
popd

pushd "${TRANSLATOR_INSTALL_DIR}"
zip -r "../${TRANSLATOR_INSTALL_DIR}.zip" ./*
popd

# sha1 files.
sha1sum "${ANGLE_INSTALL_DIR}.zip" | cut -f 1 -d " " >"${ANGLE_INSTALL_DIR}.zip.sha1"

sha1sum "${TRANSLATOR_INSTALL_DIR}.zip" | cut -f 1 -d " " >"${TRANSLATOR_INSTALL_DIR}.zip.sha1"

# POM file.
sed -e "s/@GROUP@/${GROUP_DOTS}/g" -e "s/@ARTIFACT@/${ARTIFACT}/g" -e "s/@VERSION@/${ARTIFACT_VERSION}/g" "../fake_pom.xml" >"${POM_FILE}"

sha1sum "${POM_FILE}" | cut -f 1 -d " " >"${POM_FILE}.sha1"

DESCRIPTION="$(echo -e "Automated build for ${TARGET_REPO_NAME} version ${COMMIT_ID}.\n$(git log --graph -n 3 --abbrev-commit --pretty='format:%h - %s <%an>')")"

# Only release from master branch commits.
# shellcheck disable=SC2153
if test "${GITHUB_REF}" != "refs/heads/master"; then
  exit 0
fi

# We do not use the GITHUB_TOKEN provided by GitHub Actions.
# We cannot set environment variables or secrets that start with GITHUB_ in .yml files,
# but the github-release-retry tool requires GITHUB_TOKEN, so we set it here.
export GITHUB_TOKEN="${GH_TOKEN}"

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "${BUILD_REPO_ORG}" \
  --repo "${BUILD_REPO_NAME}" \
  --tag_name "${TAG}" \
  --target_commitish "${BUILD_REPO_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${ANGLE_INSTALL_DIR}.zip"

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "${BUILD_REPO_ORG}" \
  --repo "${BUILD_REPO_NAME}" \
  --tag_name "${TAG}" \
  --target_commitish "${BUILD_REPO_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${ANGLE_INSTALL_DIR}.zip.sha1"

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "${BUILD_REPO_ORG}" \
  --repo "${BUILD_REPO_NAME}" \
  --tag_name "${TAG}" \
  --target_commitish "${BUILD_REPO_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${TRANSLATOR_INSTALL_DIR}.zip"

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "${BUILD_REPO_ORG}" \
  --repo "${BUILD_REPO_NAME}" \
  --tag_name "${TAG}" \
  --target_commitish "${BUILD_REPO_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${TRANSLATOR_INSTALL_DIR}.zip.sha1"

# Don't fail if pom cannot be uploaded, as it might already be there.

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "${BUILD_REPO_ORG}" \
  --repo "${BUILD_REPO_NAME}" \
  --tag_name "${TAG}" \
  --target_commitish "${BUILD_REPO_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${POM_FILE}" || true

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "${BUILD_REPO_ORG}" \
  --repo "${BUILD_REPO_NAME}" \
  --tag_name "${TAG}" \
  --target_commitish "${BUILD_REPO_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${POM_FILE}.sha1" || true

# Don't fail if OPEN_SOURCE_LICENSES.TXT cannot be uploaded, as it might already be there.

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "${BUILD_REPO_ORG}" \
  --repo "${BUILD_REPO_NAME}" \
  --tag_name "${TAG}" \
  --target_commitish "${BUILD_REPO_SHA}" \
  --body_string "${DESCRIPTION}" \
  "OPEN_SOURCE_LICENSES.TXT" || true
