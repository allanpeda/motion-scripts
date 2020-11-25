#!/bin/sh

# Script to carefully upload new files
# to cloud storage using rclone
# Tested with MS onedrive
# Allan Peda
# allan.peda@wishramholdings.com
# Nov 22, 2020
#
# Typical usage: Run this three or four times per
# MMIN_NEWER interval (typically 60 minutes), eg
# run every 15 or 20 minutes. This ensures that
# recent files are copied to cloud storage.
# Files which are open (under than MMIN_OLDER)
# are not copied.

# See also:
# https://rclone.org/
# https://motion-project.github.io/
# https://google.github.io/styleguide/shellguide.html
# flock trick by Randall Schwartz (original link gone)
# https://linuxaria.com/howto/linux-shell-introduction-to-flock
exec 200< "$0"
if ! flock -n 200; then
    echo "Multiple instances of script $0 prohibited."
    exit 1
fi

# local directory
declare -r  VIDEO_DIR='/cctv/data/motion'
# 1gb = 10^9, 1TB = 10^12
declare -ri DISK_LIMIT=$(dc -e '10 11 ^ 8 * p')
declare -r  CLOUD_STORE='onedrive:CCTV/799LEH'
# See rclone for time format
declare -r  CLOUD_EXPIRY='14d'
# file mtime less than MMIN_NEWER more than MMIN_OLDER
# used for local selection, and remote file listing
declare -ri MMIN_NEWER='60'
# MMIN_OLDER used locally to avoid copying open files
declare -ri MMIN_OLDER='2'

date "+=== START %F %T ==="
# deleting old videos if we are above the usage limit
# only run if we are over the limit
if (( $(du --bytes -xs ${VIDEO_DIR} | awk '{print $1}') > ${DISK_LIMIT} ))
then
    echo "Disk at or over high water mark of $DISK_LIMIT bytes."
    declare -i space_taken=0
    for f in $(ls -1t "${VIDEO_DIR}/*.m??")
    do
	declare -i file_size=$(stat --printf="%s" "${f}")
	space_taken=$((space_taken+file_size))
	if (( "$space_taken" > "$DISK_LIMIT" ))
	then
	    echo "Removing file: ${f}"
            rm -f "${f}"
	    space_taken=$((space_taken-file_size))
	fi
    done
fi

# So we don't waste bandwith re-uploading
declare -A UPLOADED_ASSOC_ARR=()
# Save list of uploaded files (don't need path)
while IFS= read -r uf
do
    sf=${uf##*/}
    UPLOADED_ASSOC_ARR[$sf]=1
done < <(rclone ls --max-age "${MMIN_NEWER}m" "${CLOUD_STORE}")

# upload new files to cloud
declare -i copy_count=0
# lf = long filename, sf = short filename
for lf in $(find "${VIDEO_DIR}" -name 'CAM*.m??' -type f \
		 -mmin -${MMIN_NEWER} -and -mmin +${MMIN_OLDER})
do
    sf=${lf##*/}
    # skip if this file was already uploaded
    if [[ ${UPLOADED_ASSOC_ARR[$sf]:-0} == 1 ]]
    then
	echo "  Skipping ${sf} (already uploaded)"
	continue
    fi
    if lsof "${lf}" >/dev/null
    then
	echo "  Skipping open file: ${sf}"
	continue
    fi
    echo "  $sf"
    case ${sf:0:5} in
	CAM01)
	    rclone copy "$lf" "${CLOUD_STORE}/southwest_corner"
	    ;;
	
	CAM02)
	    rclone copy "$lf" "${CLOUD_STORE}/garage_side_entrance"
	    ;;

	CAM03)
	    rclone copy "$lf" "${CLOUD_STORE}/fhd_parking_area"
	    ;;

        CAM04)
            rclone copy "$lf" "${CLOUD_STORE}/fhd_lobby"
            ;;

	*)
	    echo "Unexpected file prefix encountered." >&2
	    ;;
    esac
    if [[ $? -eq 0 ]]
    then
       ((copy_count++))
    fi	   
done

# delete old files from cloud
for path in "${CLOUD_STORE}/southwest_corner" \
    "${CLOUD_STORE}/garage_side_entrance" \
    "${CLOUD_STORE}/fhd_parking_area"
do
    echo "  deleting old files under ${path##*/}"
    rclone delete --min-age ${CLOUD_EXPIRY} "${path}"
done

if [[ $copy_count = 0 ]]
then
    echo "No files copied."
elif [[ $copy_count = 1 ]]
then
     echo "Copied $copy_count file."
else
    echo "Copied $copy_count files."
fi

date "+=== END %F %T ==="
