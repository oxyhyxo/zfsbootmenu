#!/bin/bash
# vim: softtabstop=2 shiftwidth=2 expandtab

cleanup() {
  if [ -n "${zfs_diff_PID}" ]; then
    kill "${zfs_diff_PID}"
    wait "${zfs_diff_PID}"
    unset zfs_diff_PID
  fi

  if [ -n "${mnt}" ]; then
    umount "${mnt}"
    unset mnt
  fi

  trap - INT TERM QUIT EXIT
  exit
}

# shellcheck disable=SC1091
[ -r /lib/zfsbootmenu-lib.sh ] && source /lib/zfsbootmenu-lib.sh

snapshot="${1}"
if [ -z "${snapshot}" ]; then
  zerror "snapshot is undefined"
  exit 130
fi

# if a second parameter was passed in and it's a snapshot, compare
# creation dates and make sure diff_target is newer than snapshot
if [ -n "${2}" ] ; then
  sd="$( zfs get -H -p -o value creation "${snapshot}" )"
  td="$( zfs get -H -p -o value creation "${2}" )"
  if [ "${sd}" -lt "${td}" ] ; then
    diff_target="${2}"
  else
    diff_target="${snapshot}"
    snapshot="${2}"
  fi
else
  diff_target="${snapshot%%@*}"
fi

zdebug "snapshot: ${snapshot}"
zdebug "diff target: ${diff_target}"

pool="${snapshot%%/*}"
zdebug "pool: ${pool}"

if ! set_rw_pool "${pool}"; then
  zerror "unable to set ${pool} read/write"
  exit 1
fi

base_fs="${snapshot%%@*}"
zdebug "base filesystem: ${base_fs}"

CLEAR_SCREEN=1 load_key "${base_fs}"

unset mnt
unset zfs_diff_PID

trap cleanup INT TERM QUIT EXIT

if ! mnt="$( mount_zfs "${base_fs}" )" ; then
  zerror "unable to mount ${base_fs}"
  exit 1
fi

zdebug "executing: zfs diff -F -H ${snapshot} ${diff_target}"
coproc zfs_diff ( zfs diff -F -H "${snapshot}" "${diff_target}" )

# Bash won't use an FD referenced in a variable on the left side of a pipe
exec 3>&"${zfs_diff[0]}"

# shellcheck disable=SC2154
line_one="$( center_string "---${snapshot}" )"
left_pad="${line_one//---${snapshot}/}"
line_one="$( colorize red "${line_one}" )"
line_two="${left_pad}$( colorize green "+++${diff_target}" )"

sed "s,${mnt},," <&3 | HELP_SECTION=diff-viewer ${FUZZYSEL} --prompt "> " \
  --preview="echo -e '${line_one}\n${line_two}'" --no-sort \
  --preview-window="up:${PREVIEW_HEIGHT}"
