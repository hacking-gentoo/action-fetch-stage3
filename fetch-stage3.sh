#!/usr/bin/env bash

#MIRROR="http://distfiles.gentoo.org/"
MIRROR="https://gentoo.osuosl.org/"
STAGE3_BASE="stage3-amd64-hardened-nomultilib-openrc"
ARCH="${ARCH:-amd64}"
ARCH_URL="${ARCH_URL:-${MIRROR}releases/${ARCH}/autobuilds/current-${STAGE3_BASE}/}"
DOWNLOAD_DIR="."

function die()
{
    echo "::error::$1"
	echo "------------------------------------------------------------------------------------------------------------------------"
    exit 1
}

# Return a Bash regex that should match for any given stage3_base
# Arguments:
# 1: stage3_base (i.e. stage3-amd64-hardened+nomultilib)
function get_stage3_archive_regex() 
{
    local stage3_base
    stage3_base="$1"
    echo "${stage3_base//+/\\+}-([0-9]{8})(T[0-9]{6}Z)?\\.tar\\.(bz2|xz)"
}

# Compare given local and remote stage3 date, returns 0 if remote is newer or 1 if not
#
# Arguments:
# 1: stage3_date_local
# 2: stage3_date_remote
function is_newer_stage3_date 
{
    local stage3_date_local stage3_date_remote
    # parsing ISO8601 with the date command is a bit tricky due to differences on macOS
    # as a workaround we just remove any possible non-numeric chars and compare as integers
    stage3_date_local="${1//[!0-9]/}"
    stage3_date_remote="${2//[!0-9]/}"
    if [[ "${stage3_date_local}" -lt "${stage3_date_remote}" ]]; then
        return 0
    else
        return 1
    fi
}

# Fetch latest stage3 archive name/type, returns exit signal 3 if no archive could be found
function fetch_stage3_archive_name() 
{
    local remote_files remote_line remote_date remote_file_type stage3_archive_regex
    
    readarray -t remote_files <<< "$(wget -qO- "${ARCH_URL}")"
    remote_date=0
    stage3_archive_regex="$(get_stage3_archive_regex "${STAGE3_BASE}")"
    for remote_line in "${remote_files[@]}"; do
        if [[ "${remote_line}" =~ ${stage3_archive_regex}\< ]]; then
            is_newer_stage3_date "${remote_date}" "${BASH_REMATCH[1]}${BASH_REMATCH[2]}" \
                && { remote_date="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; remote_file_type="${BASH_REMATCH[3]}"; }
        fi
    done
    [[ "${remote_date//[!0-9]/}" -eq 0 ]] && die "No archive found"
    echo "${STAGE3_BASE}-${remote_date}.tar.${remote_file_type}"
}

function sha_sum() 
{
    [[ -n "$(command -v sha512sum)" ]] && echo 'sha512sum' || echo 'shasum -a512'
}

# Download and verify stage3 tar ball
#
# Arguments:
# 1: stage3_file
function download_stage3() 
{
    [[ -d "${DOWNLOAD_DIR}" ]] || mkdir -p "${DOWNLOAD_DIR}"
    local stage3_file stage3_contents stage3_digests sha512_hashes sha512_check sha512_failed
    stage3_file="$1"
    stage3_contents="${stage3_file}.CONTENTS"
    stage3_digests="${stage3_file}.DIGESTS"
    if [[ "${ARCH_URL}" == *autobuilds*  ]]; then
        stage3_digests="${stage3_file}.DIGESTS.asc"
    fi

    for file in "${stage3_file}" "${stage3_contents}" "${stage3_digests}"; do
    	echo "Downloading ${ARCH_URL}${file}"
    	wget --no-verbose -O "${DOWNLOAD_DIR}/${file}" "${ARCH_URL}${file}" || die "Download of ${ARCH_URL}${file} failed"
    done

    # some experimental stage3 builds don't update the file names in the digest file, replace so sha512 check won't fail
    grep -q "${STAGE3_BASE}-2008\.0\.tar\.bz2" "${DOWNLOAD_DIR}/${stage3_digests}" \
        && sed -i "s/${STAGE3_BASE}-2008\.0\.tar\.bz2/${stage3_file}/g" "${DOWNLOAD_DIR}/${stage3_digests}"
    sha512_hashes="$(grep -A1 SHA512 "${DOWNLOAD_DIR}/${stage3_digests}" | grep -v '^--')"
    sha512_check="$(cd "${DOWNLOAD_DIR}/" && (echo "${sha512_hashes}" | $(sha_sum) -c))"
    sha512_failed="$(echo "${sha512_check}" | grep FAILED)"
    if [ -n "${sha512_failed}" ]; then
        die "${sha512_failed}"
    fi
}

cat << END
------------------------------------------------------------------------------------------------------------------------
                         _   _                    __     _       _               _                   ____  
                        | | (_)                  / _|   | |     | |             | |                 |___ \ 
               __ _  ___| |_ _  ___  _ __ ______| |_ ___| |_ ___| |__ ______ ___| |_ __ _  __ _  ___  __) |
              / _\` |/ __| __| |/ _ \| '_ \______|  _/ _ \ __/ __| '_ \______/ __| __/ _\` |/ _\` |/ _ \|__ < 
             | (_| | (__| |_| | (_) | | | |     | ||  __/ || (__| | | |     \__ \ || (_| | (_| |  __/___) |
              \__,_|\___|\__|_|\___/|_| |_|     |_| \___|\__\___|_| |_|     |___/\__\__,_|\__, |\___|____/ 
                                                                                           __/ |           
                                                                                          |___/            
             https://github.com/hacking-gentoo/action-fetch-stage3                     (c) 2019 Max Hacking 
------------------------------------------------------------------------------------------------------------------------
END

[[ -z "${GITHUB_WORKSPACE}" ]] && die "Must set GITHUB_WORKSPACE in env"
cd "${GITHUB_WORKSPACE}" || die "GITHUB_WORKSPACE does not exist"
echo -n "Determining archive name..."
stage3_archive_name=$(fetch_stage3_archive_name)
echo "${stage3_archive_name}"
echo "Downloading archive..."
download_stage3 "${stage3_archive_name}"

echo "------------------------------------------------------------------------------------------------------------------------"
