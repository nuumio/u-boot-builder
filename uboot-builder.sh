#!/bin/bash

set -e

# Use GitHub mirrors in hopes that they're faster
ATF_REPO=${ATF_REPO:-https://github.com/ARM-software/arm-trusted-firmware.git}
UBOOT_REPO=${UBOOT_REPO:-https://github.com/u-boot/u-boot.git}

# NOTE: check that ./github/workflows/* work if you change these variables!
CUR_DIR="$(pwd)"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BUILD_DIR="${BUILD_DIR:-build}"
ATF_DIR="${ATF_DIR:-atf}"
UBOOT_DIR="${UBOOT_DIR:-uboot}"
BINARIES_DIR="${BINARIES_DIR:-binaries}"
REL_NOTE="${CUR_DIR}/${BUILD_DIR}/release.md"
STATUS_FILE="${CUR_DIR}/${BUILD_DIR}/status.md"
COMMENT_FILE="${CUR_DIR}/${BUILD_DIR}/comment.md"

# Get back to where we started at exit
cleanup() {
  cd "${CUR_DIR}"
}
trap cleanup EXIT

# Clone or fetch given version
git-update() {
  local pkg="${1}"
  local repo="${2}"
  local version="${3}"
  local dir="${4}"
  if [ ! -d "${dir}" ]; then
    echo "Cloning ${pkg} version ${version}"
    git clone --depth 1 --branch "${version}" "${repo}" "${dir}"
    cd "${dir}"
  else
    echo "Fetching ${pkg} version ${version}"
    cd "${dir}"
    git reset --hard HEAD
    git clean -dfxq
    git fetch --depth 1 origin tag "${version}"
    git checkout "${version}"
  fi
  echo "${pkg} now at $(git log --pretty=oneline --decorate=short)"
  git status
}

# Apply patches (expects we're in currect dir)
patch-pkg() {
  local pkg="${1}"
  shift
  local patches=("${@}")
  for p in "${patches[@]}"; do
    echo "Applying patch ${p} ..."
    patch -p1 < "${SCRIPT_DIR}/${p}"
  done  
}

# Build ATF and U-Boot (expects variables set before being called)
build() {
  echo "Building target ${TARGET}:"
  echo "  ATF_VERSION: ${ATF_VERSION}"
  echo "  ATF_PLATFORM: ${ATF_PLATFORM}"
  echo "  ATF_CROSS_COMPILE: ${ATF_CROSS_COMPILE}"
  echo "  ATF_PATCHES:"
  for i in "${ATF_PATCHES[@]}"; do
    echo "    $i"
  done
  echo "  UBOOT_VERSION: ${UBOOT_VERSION}"
  echo "  UBOOT_CONFIG: ${UBOOT_CONFIG}"
  echo "  UBOOT_CROSS_COMPILE: ${UBOOT_CROSS_COMPILE}"
  echo "  UBOOT_PATCHES:"
  for i in "${UBOOT_PATCHES[@]}"; do
    echo "    $i"
  done

  # Build ATF
  cd "${CUR_DIR}/${BUILD_DIR}"
  git-update ATF "${ATF_REPO}" "${ATF_VERSION}" "${ATF_DIR}"
  patch-pkg ATF "${ATF_PATCHES[@]}"
  echo "Building ATF ..."
  make "PLAT=${ATF_PLATFORM}" "CROSS_COMPILE=${ATF_CROSS_COMPILE}"
  BL31="$(pwd)/build/${ATF_PLATFORM}/release/bl31/bl31.elf"
  if [ ! -f "${BL31}" ]; then
    echo "ATF ERROR, BL31 file not found: ${BL31}"
    exit 1
  fi

  # Build U-Boot
  cd "${CUR_DIR}/${BUILD_DIR}"
  git-update U-Boot "${UBOOT_REPO}" "${UBOOT_VERSION}" "${UBOOT_DIR}"
  patch-pkg U-Boot "${UBOOT_PATCHES[@]}"
  echo "Building U-Boot ..."
  make "BL31=${BL31}" "CROSS_COMPILE=${UBOOT_CROSS_COMPILE}" "${UBOOT_CONFIG}"
  make "BL31=${BL31}" "CROSS_COMPILE=${UBOOT_CROSS_COMPILE}" all -j$(nproc)
  cp [iu]*.{img,bin,itb} "${BIN_TARGET}/"
}

# Prep build dir
mkdir -p "${CUR_DIR}/${BUILD_DIR}"

# Release header
if [ ! -z "${RELEASE_VERSION}" ]; then
  echo -e "Boards included:\n" >> ${REL_NOTE}
fi

# Current platform (for release note)
CUR_PLATFORM=""

# Failure counter
FAILS=0

# Loop over all found board configs (min depth of 3 dirs),
# NOTE: Don't use spaces in dir/file names (or fix this yourself :P).
#       And use board/_platform_/_board_ dir structure.
for conf in $(find board -mindepth 3 -type f -name config | sort); do
  unset ATF_VERSION
  unset ATF_PLATFORM
  unset ATF_CROSS_COMPILE
  unset UBOOT_VERSION
  unset UBOOT_CONFIG
  unset UBOOT_CROSS_COMPILE
  ATF_PATCHES=()
  UBOOT_PATCHES=()

  # Figure out target from config file path
  cd "${SCRIPT_DIR}"
  d="$(dirname "$conf")"
  target_path="${d//board\//}"
  TARGET_BOARD="$(basename "${target_path}")"
  TARGET_PLATFORM="$(basename $(dirname "${target_path}"))"
  TARGET="${TARGET_PLATFORM}/${TARGET_BOARD}"

  # Find configs and patches from board dir to leaf
  split="${d//\// }"
  confd="."
  for s in ${split}; do
    confd="${confd}/${s}"
    if [ -f "${confd}/config" ]; then
      . "${confd}/config"
    fi
    if [ -d "${confd}/atf-patches" ]; then
      for p in $(find "${confd}/atf-patches" -type f -name "*.patch" | sort); do
        ATF_PATCHES+=("${p:2}")
      done
    fi
    if [ -d "${confd}/uboot-patches" ]; then
      for p in $(find "${confd}/uboot-patches" -type f -name "*.patch" | sort); do
        UBOOT_PATCHES+=("${p:2}")
      done
    fi
  done

  # Prep binaries dir
  cd "${CUR_DIR}/${BUILD_DIR}"
  BIN_TARGET="$(pwd)/${BINARIES_DIR}/${TARGET}"
  mkdir -p "${BIN_TARGET}"

  # Build and keep going even if board's build fails
  if build; then
    echo "- ✔️ \`${TARGET}\`: build success 🛠️" >> "${STATUS_FILE}"
  else
    echo "- 🛑 \`${TARGET}\`: build failure 💩" >> "${STATUS_FILE}"
    FAILS=$((FAILS + 1))
  fi

  # Release note content
  if [ ! -z "${RELEASE_VERSION}" ]; then
    if [ "${CUR_PLATFORM}" != "${TARGET_PLATFORM}" ]; then
      CUR_PLATFORM="${TARGET_PLATFORM}"
      echo "- \`${CUR_PLATFORM}\`" >> ${REL_NOTE}
    fi
    echo "  - \`${TARGET_BOARD}\`" >> ${REL_NOTE}
    echo "    - ATF version: \`${ATF_VERSION}\`" >> ${REL_NOTE}
    echo "    - U-Boot version: \`${UBOOT_VERSION}\`" >> ${REL_NOTE}
  fi
done

# If doing a release, pack binaries and print release note on build log.
# (pr builds are archived to zip by pull request workflow.)
if [ ! -z "${RELEASE_VERSION}" ]; then
  echo -e "\n**sha256sums:**\n\n\`\`\`" >> ${REL_NOTE}
  cd "${CUR_DIR}/${BUILD_DIR}"
  # Pack by platform name
  for p in $(find "${BINARIES_DIR}" -mindepth 1 -maxdepth 1 -type d); do
    PLATFORM="$(basename "${p}")"
    PKG="u-boot-${PLATFORM}-${RELEASE_VERSION}.tar.gz"
    tar czf "${PKG}" -C "${BINARIES_DIR}" "${PLATFORM}"
    SHA256="$(sha256sum "${PKG}")"
    echo "${SHA256}" >> ${REL_NOTE}
    echo "${SHA256}" > "${PKG}.sha256"
  done
  echo "\`\`\`" >> ${REL_NOTE}

  echo "Release note '${REL_NOTE}':"
  cat "${REL_NOTE}"
fi

if [ "${FAILS}" -gt 0 ]; then
  echo -e "# BUILD FAILED 😭\n" >> "${COMMENT_FILE}"
  cat "${STATUS_FILE}" >> "${COMMENT_FILE}"
  exit 1
else
  echo -e "# BUILD SUCCESS 🥳\n" >> "${COMMENT_FILE}"
  cat "${STATUS_FILE}" >> "${COMMENT_FILE}"
fi
