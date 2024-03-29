#!/bin/bash

set -e

# Use GitHub mirrors in hopes that they're faster
ATF_REPO=${ATF_REPO:-https://github.com/ARM-software/arm-trusted-firmware.git}
UBOOT_REPO=${UBOOT_REPO:-https://github.com/u-boot/u-boot.git}

# NOTE: check that ./github/workflows/* work if you change these variables!
CUR_DIR="$(pwd)"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
DL_DIR="${DL_DIR:-dl}"
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
  # Just in case we used download earlier and now we want git:
  # If "${dir}" exists but "${dir}/.git" doesn't then rm "${dir}".
  if [ -d "${dir}" ] && [ ! -d "${dir}/.git" ]; then
    echo "Clean existing dir \""${dir}"\" for Git"
    rm -rf "${dir}"
  fi
  if [ ! -d "${dir}" ]; then
    echo "Cloning ${pkg} version ${version}"
    git clone --depth 1 --branch "${version}" "${repo}" "${dir}"  || return 1
    cd "${dir}"
  else
    echo "Fetching ${pkg} version ${version}"
    cd "${dir}"
    git reset --hard HEAD || return 1
    git clean -dfxq || return 1
    git fetch --depth 1 origin tag "${version}" || return 1
    git checkout "${version}" || return 1
  fi
  echo "${pkg} now at $(git log --pretty=oneline --decorate=short)"
  git status
}

dl-pkg() {
  local pkg="${1}"
  local version="${2}"
  local file="${3}"
  local url="${4}"
  local fullpath="${SCRIPT_DIR}/${DL_DIR}/${file}"
  if [ -f "${fullpath}" ]; then
    echo "${pkg} ${version} already downloaded to ${DL_DIR}/${file}"
    return 0
  fi
  echo "${pkg} ${version} downloading to ${DL_DIR}/${file}"
  mkdir -p "$(dirname "${fullpath}")"
  (set -x; curl -o "${fullpath}" "${url}") || return 1
}

unpack-pkg() {
  local pkg="${1}"
  local version="${2}"
  local file="${3}"
  local where="${4}"
  local fullpath="${SCRIPT_DIR}/${DL_DIR}/${file}"
  if [ ! -f "${fullpath}" ]; then
    echo "${pkg} ${version} file not found: ${DL_DIR}/${file}"
    return 1
  fi
  echo "${pkg} ${version} unpacking source from ${DL_DIR}/${file}"
  (set -x; tar xf "${fullpath}" --strip-components=1 -C "${where}") || return 1
}

# Apply patches (expects we're in currect dir)
patch-pkg() {
  local pkg="${1}"
  shift
  local patches=("${@}")
  for p in "${patches[@]}"; do
    echo "Applying patch ${p} ..."
    patch -p1 < "${SCRIPT_DIR}/${p}" || return 1
  done  
}

# Build ATF and U-Boot (expects variables set before being called)
build() {
  echo -e "\n========================================\n"
  echo "Building target ${TARGET}:"
  echo "  ATF_VERSION: ${ATF_VERSION}"
  echo "  ATF_PLATFORM: ${ATF_PLATFORM}"
  echo "  ATF_CROSS_COMPILE: ${ATF_CROSS_COMPILE}"
  echo "  ATF_MAKE: ${ATF_MAKE}"
  echo "  ATF_PATCHES:"
  for i in "${ATF_PATCHES[@]}"; do
    echo "    $i"
  done
  echo "  UBOOT_VERSION: ${UBOOT_VERSION}"
  echo "  UBOOT_CONFIG: ${UBOOT_CONFIG}"
  echo "  UBOOT_CROSS_COMPILE: ${UBOOT_CROSS_COMPILE}"
  echo "  UBOOT_BL: ${UBOOT_BL}"
  echo "  UBOOT_BIN_GLOB: ${UBOOT_BIN_GLOB}"
  echo "  UBOOT_MAKE_CONFIG: ${UBOOT_MAKE_CONFIG}"
  echo "  UBOOT_MAKE_BIN: ${UBOOT_MAKE_BIN}"
  if [ ! -z "${UBOOT_MKIMAGE}" ]; then
    echo "  UBOOT_MKIMAGE: ${UBOOT_MKIMAGE}"
  fi
  echo "  UBOOT_PATCHES:"
  for i in "${UBOOT_PATCHES[@]}"; do
    echo "    $i"
  done
  echo -e "\n========================================\n"

  # Check UBOOT_BL
  if [ "${UBOOT_BL}" != "BL31" ] && [ "${UBOOT_BL}" != "BL32" ]; then
    echo "Unsupported UBOOT_BL: ${UBOOT_BL}"
    return 1
  fi

  # Check UBOOT_BIN_GLOB
  if [ -z "${UBOOT_BIN_GLOB}" ]; then
    echo "Empty UBOOT_BIN_GLOB: Nothing to do!"
    return 1
  fi

  # Build ATF
  cd "${CUR_DIR}/${BUILD_DIR}"
  git-update ATF "${ATF_REPO}" "${ATF_VERSION}" "${ATF_DIR}" || return 1
  patch-pkg ATF "${ATF_PATCHES[@]}" || return 1
  echo "Building ATF ..."
  echo "$(eval "echo + ${ATF_MAKE}")"
  eval "${ATF_MAKE}" || return 1
  BL31="$(pwd)/build/${ATF_PLATFORM}/release/bl31/bl31.elf"
  BL32="$(pwd)/build/${ATF_PLATFORM}/release/bl32/bl32.elf"
  if [ ! -f "${!UBOOT_BL}" ]; then
    echo "ATF ERROR, ${UBOOT_BL} file not found: ${!UBOOT_BL}"
    return 1
  fi

  # Build U-Boot
  cd "${CUR_DIR}/${BUILD_DIR}"
  if "${UBOOT_USE_GIT}" > /dev/null 2>&1; then
    git-update U-Boot "${UBOOT_REPO}" "${UBOOT_VERSION}" "${UBOOT_DIR}" || return 1
  else
    dl-pkg "U-Boot" "${UBOOT_VERSION}" "u-boot-${UBOOT_VERSION/v/}.tar.bz2" \
      "https://ftp.denx.de/pub/u-boot/u-boot-${UBOOT_VERSION/v/}.tar.bz2" || return 1
    # Ensure clean source
    rm -rf "${UBOOT_DIR}"
    mkdir -p "${UBOOT_DIR}" || return 1
    unpack-pkg "U-Boot" "${UBOOT_VERSION}" "u-boot-${UBOOT_VERSION/v/}.tar.bz2" "${UBOOT_DIR}" || return 1
    cd "${UBOOT_DIR}" || return 1
  fi
  patch-pkg U-Boot "${UBOOT_PATCHES[@]}" || return 1
  echo "Building U-Boot ..."
  echo "$(eval "echo + ${UBOOT_MAKE_CONFIG}")"
  eval "${UBOOT_MAKE_CONFIG}" || return 1
  # Copy .config too to make it easier to inspect in retrospect
  cp .config "${BIN_TARGET}/"
  echo "$(eval "echo + ${UBOOT_MAKE_BIN}")"
  eval "${UBOOT_MAKE_BIN}" || return 1
  if [ ! -z "${UBOOT_MKIMAGE}" ]; then
    echo "$(eval "echo + ${UBOOT_MKIMAGE}")"
    eval "${UBOOT_MKIMAGE}" || return 1
  fi
  eval "cp ${UBOOT_BIN_GLOB} "${BIN_TARGET}/"" || return 1
}

# Prep build dir
mkdir -p "${CUR_DIR}/${BUILD_DIR}"

# Clean status, release note and comment every time
rm -rf "${STATUS_FILE}" "${REL_NOTE}" "${COMMENT_FILE}"

# Release header. Print default ATF and U-Boot versions if found (should be found).
echo -e "Default ATF and U-Boot versions (platforms/boards use these unless otherwise noted):\n" >> ${REL_NOTE}
. board/config
DEFAULT_ATF_VERSION="${ATF_VERSION}"
DEFAULT_UBOOT_VERSION="${UBOOT_VERSION}"
if [ ! -z "${ATF_VERSION}" ]; then
  echo "- ATF: \`${ATF_VERSION}\`" >> ${REL_NOTE}
fi
if [ ! -z "${UBOOT_VERSION}" ]; then
  echo "- U-Boot: \`${UBOOT_VERSION}\`" >> ${REL_NOTE}
fi
echo -e "\nBoards included:\n" >> ${REL_NOTE}

# Current platform (for release note)
CUR_PLATFORM=""

# Failure counter
FAILS=0

# Loop over all found platforms configs (depth of 1 dir, this keeps
# platforms in nice order).
# Then loop over all found board configs (min depth of 2 dirs in platform).
# NOTE: Don't use spaces in dir/file names (or fix this yourself :P).
#       And use board/_platform_/_board_ dir structure.
for dplat in $(find board -mindepth 1 -maxdepth 1 -type d | sort); do
  cd "${SCRIPT_DIR}"
  for conf in $(find "${dplat}" -mindepth 2 -type f -name config | sort); do
    unset ATF_VERSION
    unset ATF_PLATFORM
    unset ATF_CROSS_COMPILE
    unset ATF_MAKE
    unset UBOOT_VERSION
    unset UBOOT_CONFIG
    unset UBOOT_CROSS_COMPILE
    unset UBOOT_BL
    unset UBOOT_BIN_GLOB
    unset UBOOT_MAKE_CONFIG
    unset UBOOT_MAKE_BIN
    unset UBOOT_MKIMAGE
    unset PLAT_ATF_VERSION
    unset PLAT_UBOOT_VERSION
    unset PLAT_NOTE_EXTRA
    unset BOARD_NOTE_EXTRA
    UBOOT_USE_GIT=false
    ATF_PATCHES=()
    UBOOT_PATCHES=()
    I=0

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
      I=$((I + 1))
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
      if [ "${I}" -eq 2 ]; then
        # platform level
        PLAT_ATF_VERSION="${ATF_VERSION}"
        PLAT_UBOOT_VERSION="${UBOOT_VERSION}"
        if [ -f "${confd}/rel-note-extra.md" ]; then
          PLAT_NOTE_EXTRA="$(cat "${confd}/rel-note-extra.md")"
        fi
      fi
      if [ "${I}" -eq 3 ]; then
        if [ -f "${confd}/rel-note-extra.md" ]; then
          BOARD_NOTE_EXTRA="$(cat "${confd}/rel-note-extra.md")"
        fi
      fi
    done

    # Prep binaries dir
    cd "${CUR_DIR}/${BUILD_DIR}"
    BIN_TARGET="$(pwd)/${BINARIES_DIR}/${TARGET}"
    mkdir -p "${BIN_TARGET}"

    # Build and keep going even if board's build fails
    if build; then
      echo "${TARGET}: build success"
      echo "- ✔️ \`${TARGET}\`: build success 🛠️" >> "${STATUS_FILE}"
    else
      echo "${TARGET}: build failure"
      echo "- 🛑 \`${TARGET}\`: build failure 💩" >> "${STATUS_FILE}"
      FAILS=$((FAILS + 1))
    fi

    # Release note content
    if [ "${CUR_PLATFORM}" != "${TARGET_PLATFORM}" ]; then
      CUR_PLATFORM="${TARGET_PLATFORM}"
      echo "- platform \`${CUR_PLATFORM}\`" >> ${REL_NOTE}
      if [ "${PLAT_ATF_VERSION}" != "${DEFAULT_ATF_VERSION}" ]; then
        echo "  - ATF version: \`${PLAT_ATF_VERSION}\`" >> ${REL_NOTE}
      fi
      if [ "${PLAT_UBOOT_VERSION}" != "${DEFAULT_UBOOT_VERSION}" ]; then
        echo "  - ATF version: \`${PLAT_UBOOT_VERSION}\`" >> ${REL_NOTE}
      fi
      if [ ! -z "${PLAT_NOTE_EXTRA}" ]; then
        echo "${PLAT_NOTE_EXTRA}" >> ${REL_NOTE}
      fi
      echo "  - board(s):" >> ${REL_NOTE}
    fi
    echo "    - \`${TARGET_BOARD}\`" >> ${REL_NOTE}
    if [ "${ATF_VERSION}" != "${PLAT_ATF_VERSION}" ]; then
      echo "      - ATF version: \`${ATF_VERSION}\`" >> ${REL_NOTE}
    fi
    if [ "${UBOOT_VERSION}" != "${PLAT_UBOOT_VERSION}" ]; then
      echo "      - U-Boot version: \`${UBOOT_VERSION}\`" >> ${REL_NOTE}
    fi
    if [ ! -z "${BOARD_NOTE_EXTRA}" ]; then
      echo "${BOARD_NOTE_EXTRA}" >> ${REL_NOTE}
    fi
  done
done

# If doing a release, pack binaries and print release note on build log.
# (pr builds are archived to zip by pull request workflow.)
if [ ! -z "${RELEASE_VERSION}" ]; then
  echo -e "\n**sha256sums:**\n\n\`\`\`" >> ${REL_NOTE}
  cd "${CUR_DIR}/${BUILD_DIR}"
  # Pack by platform name
  for p in $(find "${BINARIES_DIR}" -mindepth 1 -maxdepth 1 -type d | sort); do
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
  echo -e "\n# Release note "preview":\n" >> "${COMMENT_FILE}"
  cat "${REL_NOTE}" >> "${COMMENT_FILE}"
fi
