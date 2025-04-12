### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Melt Kernel by Pzqqt
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install

## boot shell variables
block=boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

split_boot # skip ramdisk unpack

########## FLASH BOOT & VENDOR_DLKM START ##########
KEYCODE_UP=42
KEYCODE_DOWN=41

extract_erofs() {
	local img_file=$1
	local out_dir=$2

	${bin}/extract.erofs -i "$img_file" -x -T8 -o "$out_dir" &> /dev/null
}

mkfs_erofs() {
	local work_dir=$1
	local out_file=$2
	local partition_name

	partition_name=$(basename "$work_dir")

	${bin}/mkfs.erofs \
		--mount-point "/${partition_name}" \
		--fs-config-file "${work_dir}/../config/${partition_name}_fs_config" \
		--file-contexts  "${work_dir}/../config/${partition_name}_file_contexts" \
		-z lz4hc \
		"$out_file" "$work_dir"
}

is_mounted() { mount | grep -q " $1 "; }

sha1() { ${bin}/magiskboot sha1 "$1"; }

get_keycheck_result() {
	# Default behavior:
	# - press Vol+: return true (0)
	# - press Vol-: return false (1)

	local rc_1 rc_2

	while true; do
		# The first execution responds to the button press event,
		# the second execution responds to the button release event.
		${bin}/keycheck; rc_1=$?
		${bin}/keycheck; rc_2=$?
		[ "$rc_1" == "$rc_2" ] || continue
		case "$rc_2" in
			"$KEYCODE_UP") return 0;;
			"$KEYCODE_DOWN") return 1;;
		esac
	done
}

. ${home}/langs/en.lang
ui_print "# 请选择语言 Please select language"
ui_print "#"
ui_print "# 音量键+ = 中文"
ui_print "# Vol Down = English"
ui_print "#"
if get_keycheck_result; then
	ui_print "- 你选择了中文"
	. ${home}/langs/cn.lang
else
	ui_print "- You chooes English"
fi

keycode_select() {
	local r_keycode

	ui_print " "
	while [ $# != 0 ]; do
		ui_print "# $1"
		shift
	done
	ui_print "#"
	ui_print "# $_LANG_KEYCHECK_PROMPT_1"
	ui_print "# $_LANG_KEYCHECK_PROMPT_2"
	get_keycheck_result
	r_keycode=$?
	ui_print "#"
	if [ "$r_keycode" -eq "0" ]; then
		ui_print "- $_LANG_KEYCHECK_RESULT_YES"
	else
		ui_print "- $_LANG_KEYCHECK_RESULT_NO"
	fi
	ui_print " "
	return $r_keycode
}

get_size() {
	local _path=$1
	local _size

	if [ -d "$_path" ]; then
		du -bs $_path | awk '{print $1}'
		return
	fi
	if [ -b "$_path" ]; then
		_size=$(blockdev --getsize64 $_path) && {
			echo $_size
			return
		}
	fi
	wc -c < $_path
}

bytes_to_mb() {
	echo $1 | awk '{printf "%.1fM", $1 / 1024 / 1024}'
}

check_super_device_size() {
	# Check super device size
	local block_device_size block_device_size_lp

	block_device_size=$(get_size /dev/block/by-name/super) || \
		abort "! $_LANG_FAILED_TO_GET_SUPER_SIZE_BLKDEV"
	block_device_size_lp=$(${bin}/lpdump 2>/dev/null | grep -m1 -E 'Size: [[:digit:]]+ bytes$' | awk '{print $2}') || \
		abort "! $_LANG_FAILED_TO_GET_SUPER_SIZE_LPDUMP"
	ui_print "- ${_LANG_SUPER_SIZE}:"
	ui_print "  - ${_LANG_SUPER_SIZE_BLKDEV}: $block_device_size"
	ui_print "  - ${_LANG_SUPER_SIZE_LPDUMP}: $block_device_size_lp"
	[ "$block_device_size" == "9663676416" ] && [ "$block_device_size_lp" == "9663676416" ] || \
		abort "! $_LANG_SUPER_SIZE_MISMATCH"
}

# copy_gpu_pwrlevels_conf <orig dtb file> <new dtb file>
copy_gpu_pwrlevels_conf() {
	local orig_dtb=$1
	local new_dtb=$2
	local KGSL_NODE="/soc/qcom,kgsl-3d0@3d00000"
	local PWRLEVELS_NODE="${KGSL_NODE}/qcom,gpu-pwrlevels"
	local node reg gpu_freq bus_freq bus_min bus_max level cx_level acd_level initial_pwrlevel

	# Clear the gpu frequency and voltage configuration of new_dtb
	for node in $(${bin}/fdtget "$new_dtb" "$PWRLEVELS_NODE" -l); do
		${bin}/fdtput "$new_dtb" -r "/soc/qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels/${node}"
	done

	for node in $(${bin}/fdtget "$orig_dtb" /soc/qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels -l | sort -r); do
		# Read
		      reg=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "reg" -tu)
		 gpu_freq=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,gpu-freq" -tu)
		 bus_freq=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-freq" -tu)
		  bus_min=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-min" -tu)
		  bus_max=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-max" -tu)
		    level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,level" -tu)
		 cx_level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,cx-level" -tu)
		acd_level=$(${bin}/fdtget "$orig_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,acd-level" -tx)

		# Write
		${bin}/fdtput "$new_dtb" -c "${PWRLEVELS_NODE}/${node}"
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,cx-level"  "$cx_level" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,acd-level" "$acd_level" -tx
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-max"   "$bus_max" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-min"   "$bus_min" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,bus-freq"  "$bus_freq" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,level"     "$level" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "qcom,gpu-freq"  "$gpu_freq" -tu
		${bin}/fdtput "$new_dtb" "${PWRLEVELS_NODE}/${node}" "reg" "$reg" -tu
	done

	initial_pwrlevel=$(${bin}/fdtget "$orig_dtb" "$KGSL_NODE" "qcom,initial-pwrlevel" -tu)
	${bin}/fdtput "$new_dtb" "$KGSL_NODE" "qcom,initial-pwrlevel" "$initial_pwrlevel" -tu
}

# Check firmware
if strings /dev/block/bootdevice/by-name/xbl_config${slot} | grep -q 'led_blink'; then
	ui_print "$_LANG_HOS_FIRMWARE_DETECTED"
	is_hyperos_fw=true
	is_hyperos_fw_with_new_adsp2=false
	if is_mounted /vendor/firmware_mnt && [ -d /vendor/firmware_mnt/image ]; then
		modem_mount_path=/vendor/firmware_mnt
	else
		for blk in /dev/block/by-name/modem${slot} /dev/block/bootdevice/by-name/modem${slot} "$(readlink /dev/block/bootdevice/by-name/modem${slot})"; do
			if mount | grep -qE "^${blk} "; then
				modem_mount_path=$(mount | grep -E "^${blk} " | awk '{print $3}')
				break
			fi
		done
		if [ -z "$modem_mount_path" ]; then
			mkdir ${home}/_modem_mnt
			mount /dev/block/bootdevice/by-name/modem${slot} ${home}/_modem_mnt -o ro || \
				abort "! $_LANG_FAILED_TO_MOUNT modem partition!"
			modem_mount_path=${home}/_modem_mnt
		fi
	fi

	if strings "${modem_mount_path}/image/adsp2.b18" | grep -q 'audiostatus'; then
		ui_print "$_LANG_NEW_ADSP2_FIRMWARE_DETECTED"
		is_hyperos_fw_with_new_adsp2=true
	fi

	if [ -d "${home}/_modem_mnt" ]; then
		umount ${home}/_modem_mnt
		rmdir ${home}/_modem_mnt
	fi

	unset modem_mount_path
else
	ui_print "$_LANG_MIUI14_FIRMWARE_DETECTED"
	is_hyperos_fw=false
fi

# Staging unmodified partition images
mkdir -p ${home}/_orig
cp ${home}/boot.img ${home}/_orig/boot.img

# Check snapshot status
# Technical details: https://blog.xzr.moe/archives/30/
${bin}/snapshotupdater_static dump &>/dev/null
rc=$?
if [ "$rc" != 0 ]; then
	ui_print " "
	ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS rc=$rc."
	if ${BOOTMODE}; then
		ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS_PROMPT_1"
		ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS_PROMPT_2"
		ui_print "$_LANG_FAILED_TO_GET_SNAPSHOT_STATUS_PROMPT_3"
	fi
	abort "$_LANG_ABORTING"
fi
snapshot_status=$(${bin}/snapshotupdater_static dump 2>/dev/null | grep '^Update state:' | awk '{print $3}')
ui_print "${_LANG_CURRENT_SNAPSHOT_STATUS}: $snapshot_status"
if [ "$snapshot_status" != "none" ]; then
	ui_print " "
	ui_print "$_LANG_CURRENT_SNAPSHOT_STATUS_PROMPT_1"
	ui_print "$_LANG_CURRENT_SNAPSHOT_STATUS_PROMPT_2"
	ui_print "$_LANG_CURRENT_SNAPSHOT_STATUS_PROMPT_3"
	abort "$_LANG_ABORTING"
fi
unset rc snapshot_status

# Check rom type
is_miui_rom=false
is_aospa_rom=false
is_oss_kernel_rom=false
if [ -f /system/framework/MiuiBooster.jar ] && keycode_select "$_LANG_GUESS_ROM_MIUI"; then
	is_miui_rom=true
elif cat /system/build.prop | grep -qi 'aospa' && keycode_select "$_LANG_GUESS_ROM_AOSPA"; then
	is_aospa_rom=true
elif keycode_select "$_LANG_GUESS_ROM_OSS_KERNEL"; then
	is_oss_kernel_rom=true
fi

strings ${home}/Image 2>/dev/null | grep -E -m1 'Linux version.*#' > ${home}/vertmp

# Check vendor_dlkm partition status
[ -d /vendor_dlkm ] || mkdir /vendor_dlkm
is_mounted /vendor_dlkm || \
	mount /vendor_dlkm -o ro || mount /dev/block/mapper/vendor_dlkm${slot} /vendor_dlkm -o ro || \
		abort "! $_LANG_FAILED_TO_MOUNT /vendor_dlkm"

do_backup_flag=false
if [ ! -f /vendor_dlkm/lib/modules/vertmp ]; then
	do_backup_flag=true
fi
is_fixed_qbc_driver=false
if [ "$(sha1 /vendor_dlkm/lib/modules/qti_battery_charger.ko)" == "b5aa013e06e545df50030ec7b03216f41306f4d4" ]; then
	is_fixed_qbc_driver=true
fi
$BOOTMODE || umount /vendor_dlkm

# KernelSU
[ -f ${split_img}/ramdisk.cpio ] || abort "! $_LANG_CANNOT_FOUND ramdisk.cpio!"
${bin}/magiskboot cpio ${split_img}/ramdisk.cpio test
magisk_patched=$?
exist_ksu_lkm=false
if ${bin}/magiskboot cpio ${split_img}/ramdisk.cpio "exists kernelsu.ko"; then
	${bin}/magiskboot cpio ${split_img}/ramdisk.cpio "extract kernelsu.ko ${home}/kernelsu.ko" || \
		abort "! $_LANG_FAILED_TO_EXTRACT kernelsu.ko!"
	if strings ${home}/kernelsu.ko | grep -q 'clang version 12.0.5'; then
		exist_ksu_lkm=true
	else
		ui_print "- $_LANG_DETECTED_INCOMPATIBLE_KSU_LKM"
		ui_print "- $_LANG_UNINSTALLING_KSU_LKM"
		# TODO: chomd init
		if ${bin}/magiskboot cpio ${split_img}/ramdisk.cpio \
		    "rm kernelsu.ko" \
		    "rm init" \
		    "mv init.real init"; then
			ui_print "- $_LANG_UNINSTALLING_KSU_LKM_SUCCESS"
			sleep 3
		else
			abort "! $_LANG_UNINSTALLING_KSU_LKM_FAILED"
		fi
	fi
	rm ${home}/kernelsu.ko
fi
if ${exist_ksu_lkm}; then
	ui_print "- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_PROMPT_1"
	ui_print "- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_PROMPT_2"
	if [ "$magisk_patched" -eq 1 ]; then
		ui_print "- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_WITH_MAGISK_PROMPT_1"
		ui_print "- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_WITH_MAGISK_PROMPT_2"
		sleep 3
	fi
fi
unset exist_ksu_lkm
export magisk_patched

# Fix unable to mount image as read-write in recovery
$BOOTMODE || setenforce 0

ui_print " "
ui_print "- $_LANG_UNPACKING_KERNEL_MODULES"
if ${is_hyperos_fw}; then
	modules_pkg=${home}/_modules_hyperos.7z
else
	modules_pkg=${home}/_modules_miui.7z
fi
[ -f $modules_pkg ] || abort "! $_LANG_CANNOT_FOUND ${modules_pkg}!"
${bin}/7za x $modules_pkg -o${home}/ && [ -d ${home}/_vendor_boot_modules ] && [ -d ${home}/_vendor_dlkm_modules ] || \
	abort "! $_LANG_FAILED_TO_UNPACK ${modules_pkg}!"
if ${is_hyperos_fw} && ${is_hyperos_fw_with_new_adsp2}; then
	cp -f ${home}/_alt/NEW-qti_battery_charger_main.ko       ${home}/_vendor_dlkm_modules/qti_battery_charger_main.ko
	cp -f ${home}/_alt/NEW-qti_battery_charger_main-STOCK.ko ${home}/_vendor_boot_modules/qti_battery_charger_main.ko
fi
unset modules_pkg

vendor_dlkm_modules_options_file=${home}/_vendor_dlkm_modules/modules.options
[ -f $vendor_dlkm_modules_options_file ] || touch $vendor_dlkm_modules_options_file

# xiaomi_touch.ko
if ${is_hyperos_fw} && [ -f /vendor/bin/hw/vendor.lineage.touch@* ]; then
	ui_print " "
	ui_print "- $_LANG_DETECTED_OSS_XIAOMI_TOUCH_PROMPT_1"
	ui_print "- $_LANG_DETECTED_OSS_XIAOMI_TOUCH_PROMPT_2"
	cp -f ${home}/_alt/xiaomi_touch_los/* ${home}/_vendor_dlkm_modules/
	sed -i \
	    's/\/vendor\/lib\/modules\/xiaomi_touch\.ko:/\/vendor\/lib\/modules\/xiaomi_touch\.ko:\ \/vendor\/lib\/modules\/panel_event_notifier\.ko/g' \
	    ${home}/_vendor_dlkm_modules/modules.dep
fi

# goodix_core.ko
if keycode_select \
    "$_LANG_SELECT_360HZ" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_360HZ_PROMPT_1" \
    "$_LANG_SELECT_360HZ_PROMPT_2"; then
	echo "options goodix_core force_high_report_rate=y" >> $vendor_dlkm_modules_options_file
fi

# qti_battery_charger.ko / qti_battery_charger_main.ko
if ${is_hyperos_fw}; then
	modname_qti_battery_charger=qti_battery_charger_main
else
	modname_qti_battery_charger=qti_battery_charger
fi

qti_battery_charger_mod_options=""
if keycode_select \
    "$_LANG_SELECT_REAL_BATTERY" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_REAL_BATTERY_PROMPT_1" \
    "$_LANG_SELECT_REAL_BATTERY_PROMPT_2"; then
	qti_battery_charger_mod_options="${qti_battery_charger_mod_options} report_real_capacity=y"
fi

do_fix_battery_usage=false
skip_option_fix_battery_usage=false
if ${is_fixed_qbc_driver} || ${is_oss_kernel_rom}; then
	do_fix_battery_usage=true
	skip_option_fix_battery_usage=true
elif ${is_miui_rom} || ${is_aospa_rom}; then
	skip_option_fix_battery_usage=true
fi
if ! ${skip_option_fix_battery_usage}; then
	if keycode_select \
	    "$_LANG_SELECT_FIX_BATTERY_USAGE" \
	    " " \
	    "$_LANG_NOTES" \
	    "$_LANG_SELECT_FIX_BATTERY_USAGE_PROMPT_1" \
	    "$_LANG_SELECT_FIX_BATTERY_USAGE_PROMPT_2"; then
		do_fix_battery_usage=true
	fi
fi
if ${do_fix_battery_usage}; then
	qti_battery_charger_mod_options="${qti_battery_charger_mod_options} fix_battery_usage=y"
fi
unset do_fix_battery_usage skip_option_fix_battery_usage is_fixed_qbc_driver

if [ -n "${qti_battery_charger_mod_options}" ]; then
	qti_battery_charger_mod_options=$(echo "$qti_battery_charger_mod_options" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	echo "options ${modname_qti_battery_charger} ${qti_battery_charger_mod_options}" >> $vendor_dlkm_modules_options_file
fi
unset modname_qti_battery_charger qti_battery_charger_mod_options

# Alternative wired headset buttons mode
use_wired_btn_altmode=false
skip_option_wired_btn_altmode=false
if ${is_miui_rom}; then
	skip_option_wired_btn_altmode=true
elif ${is_oss_kernel_rom} || ${is_aospa_rom}; then
	use_wired_btn_altmode=true
	skip_option_wired_btn_altmode=true
fi
if ! ${skip_option_wired_btn_altmode}; then
	if keycode_select \
	    "$_LANG_SELECT_WIRED_BTN_ALTMODE" \
	    " " \
	    "$_LANG_NOTES" \
	    "$_LANG_SELECT_WIRED_BTN_ALTMODE_PROMPT_1" \
	    "$_LANG_SELECT_WIRED_BTN_ALTMODE_PROMPT_2" \
	    "$_LANG_SELECT_WIRED_BTN_ALTMODE_PROMPT_3"; then
		use_wired_btn_altmode=true
	fi
fi
if ${use_wired_btn_altmode}; then
	echo "options machine_dlkm waipio_wired_btn_altmode=y" >> $vendor_dlkm_modules_options_file
fi
unset use_wired_btn_altmode skip_option_wired_btn_altmode

# OSS msm_drm.ko
if ${is_hyperos_fw}; then
	use_oss_msm_drm=false
	skip_option_oss_msm_drm=false
	if ${is_oss_kernel_rom} || ${is_aospa_rom} || [ -f /vendor/bin/sensor-notifier ]; then
		use_oss_msm_drm=true
		skip_option_oss_msm_drm=true
	elif ! ${is_miui_rom}; then  # For roms ported from other OS
		skip_option_oss_msm_drm=true
	fi
	if ! ${skip_option_oss_msm_drm}; then
		if keycode_select \
		    "$_LANG_SELECT_OSS_MSM_DRM" \
		    " " \
		    "$_LANG_NOTES" \
		    "$_LANG_SELECT_OSS_MSM_DRM_PROMPT_1"; then
			use_oss_msm_drm=true
		fi
	fi
	if ${use_oss_msm_drm}; then
		cp -f ${home}/_alt/OSS-msm_drm.ko ${home}/_vendor_dlkm_modules/msm_drm.ko
	fi
	unset use_oss_msm_drm skip_option_oss_msm_drm
fi

# OSS ir-spi.ko
if ${is_hyperos_fw}; then
	use_oss_ir_driver=false
	skip_option_oss_ir_driver=false
	if ${is_miui_rom}; then
		skip_option_oss_ir_driver=true
	elif [ -f /vendor/bin/hw/android.hardware.ir@* ]; then
		ui_print " " "- $_LANG_IR_HAL_XIAOMI"
		skip_option_oss_ir_driver=true
	elif [ -f /vendor/bin/hw/android.hardware.ir-service.xiaomi ]; then
		ui_print " " "- $_LANG_IR_HAL_LOS_OSS"
		use_oss_ir_driver=true
		skip_option_oss_ir_driver=true
	fi
	if ! ${skip_option_oss_ir_driver}; then
		if keycode_select \
		    "$_LANG_SELECT_OSS_IR" \
		    " " \
		    "$_LANG_NOTES" \
		    "$_LANG_SELECT_OSS_IR_PROMPT_1" \
		    "$_LANG_SELECT_OSS_IR_PROMPT_2" \
		    "$_LANG_SELECT_OSS_IR_PROMPT_3"; then
			use_oss_ir_driver=true
		fi
	fi
	if ${use_oss_ir_driver}; then
		cp -f ${home}/_alt/OSS-ir-spi.ko ${home}/_vendor_dlkm_modules/ir-spi.ko
	fi
	unset use_oss_ir_driver skip_option_oss_ir_driver
fi

# OSS zram.ko & zsmalloc.ko
if ${is_miui_rom}; then
	if ! keycode_select \
	    "$_LANG_SELECT_OSS_ZRAM" \
	    " " \
	    "$_LANG_NOTES" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_1" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_2" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_3" \
	    "$_LANG_SELECT_OSS_ZRAM_PROMPT_4"; then
		cp -f ${home}/_alt/MI-zram.ko ${home}/_vendor_dlkm_modules/zram.ko
		cp -f ${home}/_alt/MI-zsmalloc.ko ${home}/_vendor_dlkm_modules/zsmalloc.ko
	fi
fi

unset vendor_dlkm_modules_options_file

# Disguised the GPU model as Adreno730v3
disguised_adreno730=false
if keycode_select \
    "$_LANG_SELECT_DISGUISED_ADRENO730" \
    " " \
    "$_LANG_NOTES" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_1" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_2" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_3" \
    "$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_4"; then
	disguised_adreno730=true
fi

# Do not load some Xiaomi special modules in AOSP roms
if ! ${is_miui_rom}; then
	# millet related modules
	for module_name in millet_core millet_binder millet_hs millet_oem_cgroup millet_pkg millet_sig binder_gki; do
		echo "blocklist $module_name" >> ${home}/_vendor_dlkm_modules/modules.blocklist
	done
	# Others
	for module_name in extend_reclaim; do
		echo "blocklist $module_name" >> ${home}/_vendor_boot_modules/modules.blocklist
	done
	for module_name in binder_prio mi_freqwdg miicmpfilter perf_helper; do
		echo "blocklist $module_name" >> ${home}/_vendor_dlkm_modules/modules.blocklist
	done
fi

if ! keycode_select \
    "$_LANG_SELECT_LAST" \
    " " \
    "$_LANG_SELECT_LAST_PROMPT_1" \
    "$_LANG_SELECT_LAST_PROMPT_2"; then
	abort "$_LANG_SELECT_LAST_ABORT"
fi

ui_print " "
if true; then  # I don't want to adjust the indentation of the code block below, so leave it as is.
	do_check_super_device_size=false

	# Dump vendor_dlkm partition image
	dd if=/dev/block/mapper/vendor_dlkm${slot} of=${home}/vendor_dlkm.img
	cp ${home}/vendor_dlkm.img ${home}/_orig/vendor_dlkm.img
	vendor_dlkm_block_size=$(get_size /dev/block/mapper/vendor_dlkm${slot})

	# Backup kernel and vendor_dlkm image
	if ${do_backup_flag}; then
		ui_print "- $_LANG_BACKUP_KERNEL_NOTE"

		if keycode_select "$_LANG_SELECT_BACKUP_KERNEL"; then
			ui_print "- $_LANG_BACKUP_KERNEL_DOING_PROMPT_1"
			ui_print "  $_LANG_BACKUP_KERNEL_DOING_PROMPT_2"

			backup_package=/sdcard/Melt-restore-kernel-$(file_getprop /system/build.prop ro.build.version.incremental)-$(date +"%Y%m%d-%H%M%S").zip

			${bin}/7za a -tzip -bd $backup_package \
				${home}/META-INF ${bin} ${home}/LICENSE ${home}/_restore_anykernel.sh \
				${split_img}/kernel \
				${home}/vendor_dlkm.img \
				/dev/block/bootdevice/by-name/vendor_boot${slot} \
				/dev/block/bootdevice/by-name/dtbo${slot}
			${bin}/7za rn -bd $backup_package kernel Image
			${bin}/7za rn -bd $backup_package _restore_anykernel.sh anykernel.sh
			${bin}/7za rn -bd $backup_package vendor_boot${slot} vendor_boot.img
			${bin}/7za rn -bd $backup_package dtbo${slot} dtbo.img
			sync

			ui_print " "
			ui_print "- $_LANG_BACKUP_KERNEL_DONE_PROMPT_1"
			ui_print "  $_LANG_BACKUP_KERNEL_DONE_PROMPT_2"
			ui_print "  $backup_package"
			ui_print "- $_LANG_BACKUP_KERNEL_DONE_PROMPT_3"
			ui_print "  $_LANG_BACKUP_KERNEL_DONE_PROMPT_4"
			ui_print "  $_LANG_BACKUP_KERNEL_DONE_PROMPT_5"
			ui_print " "
			touch ${home}/do_backup_flag

			if ! $BOOTMODE && [ ! -d /twres ]; then
				ui_print "============================================================"
				ui_print "! Warning: Please transfer the backup file just generated to"
				ui_print "! another device via ADB, as it will be lost after reboot!"
				ui_print "============================================================"
				ui_print " "
				sleep 3
			fi

			unset backup_package
		fi
	fi

	ui_print "- $_LANG_VENDOR_DLKM_UNPACKING"
	extract_vendor_dlkm_dir=${home}/_extract_vendor_dlkm
	mkdir -p $extract_vendor_dlkm_dir
	vendor_dlkm_is_ext4=false
	extract_erofs ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir || vendor_dlkm_is_ext4=true
	sync

	if ${vendor_dlkm_is_ext4}; then
		ui_print "- $_LANG_VENDOR_DLKM_IS_EXT4"
		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o ro -t ext4 || \
			abort "! $_LANG_VENDOR_DLKM_UNSUPPORTED"
		vendor_dlkm_full_space=$(df -B1 | grep -E "[[:space:]]$extract_vendor_dlkm_dir\$" | awk '{print $2}')
		vendor_dlkm_used_space=$(df -B1 | grep -E "[[:space:]]$extract_vendor_dlkm_dir\$" | awk '{print $3}')
		vendor_dlkm_free_space=$(df -B1 | grep -E "[[:space:]]$extract_vendor_dlkm_dir\$" | awk '{print $4}')
		vendor_dlkm_stock_modules_size=$(get_size ${extract_vendor_dlkm_dir}/lib/modules)
		ui_print "- ${_LANG_VENDOR_DLKM_SPACE}:"
		ui_print "  - ${_LANG_VENDOR_DLKM_SPACE_TOTAL}: $(bytes_to_mb $vendor_dlkm_full_space)"
		ui_print "  - ${_LANG_VENDOR_DLKM_SPACE_USED}: $(bytes_to_mb $vendor_dlkm_used_space)"
		ui_print "  - ${_LANG_VENDOR_DLKM_SPACE_FREE}: $(bytes_to_mb $vendor_dlkm_free_space)"
		umount $extract_vendor_dlkm_dir

		vendor_dlkm_new_modules_size=$(get_size ${home}/_vendor_dlkm_modules)
		vendor_dlkm_need_size=$((vendor_dlkm_used_space - vendor_dlkm_stock_modules_size + vendor_dlkm_new_modules_size + 10*1024*1024))
		if [ "$vendor_dlkm_need_size" -ge "$vendor_dlkm_full_space" ]; then
			# Resize vendor_dlkm image
			ui_print "- $_LANG_VENDOR_DLKM_RESIZE_PROMPT_1"
			ui_print "- $_LANG_VENDOR_DLKM_RESIZE_PROMPT_2"

			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img
			vendor_dlkm_resized_size=$(echo $vendor_dlkm_need_size | awk '{printf "%dM", ($1 / 1024 / 1024 + 1)}')
			${bin}/resize2fs ${home}/vendor_dlkm.img $vendor_dlkm_resized_size || \
				abort "! $_LANG_VENDOR_DLKM_RESIZE_FAILED"
			ui_print "- ${_LANG_VENDOR_DLKM_RESIZED}: ${vendor_dlkm_resized_size}."
			# e2fsck again
			${bin}/e2fsck -f -y ${home}/vendor_dlkm.img

			do_check_super_device_size=true
			unset vendor_dlkm_resized_size
		else
			ui_print "- $_LANG_VENDOR_DLKM_RESIZE_NO_NEED"
		fi

		ui_print "- $_LANG_VENDOR_DLKM_MOUNT_RW"
		mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o rw -t ext4 || \
			abort "! $_LANG_VENDOR_DLKM_MOUNT_RW_FAILED"

		unset vendor_dlkm_full_space vendor_dlkm_used_space vendor_dlkm_free_space vendor_dlkm_stock_modules_size vendor_dlkm_new_modules_size vendor_dlkm_need_size
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/lib/modules
	else
		extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/vendor_dlkm/lib/modules
	fi

	ui_print "- $_LANG_VENDOR_DLKM_UPDATEING"
	rm -f ${extract_vendor_dlkm_modules_dir}/*
	cp ${home}/_vendor_dlkm_modules/* ${extract_vendor_dlkm_modules_dir}/ || \
		abort "! $_LANG_VENDOR_DLKM_UPDATE_FAILED"
	cp ${home}/vertmp ${extract_vendor_dlkm_modules_dir}/vertmp
	sync

	if ${vendor_dlkm_is_ext4}; then
		set_perm 0 0 0644 ${extract_vendor_dlkm_modules_dir}/*
		chcon u:object_r:vendor_file:s0 ${extract_vendor_dlkm_modules_dir}/*
		umount $extract_vendor_dlkm_dir
	else
		for f in "${extract_vendor_dlkm_modules_dir}"/*; do
			echo "vendor_dlkm/lib/modules/$(basename $f) 0 0 0644" >> ${extract_vendor_dlkm_dir}/config/vendor_dlkm_fs_config
		done
		echo '/vendor_dlkm/lib/modules/.+ u:object_r:vendor_file:s0' >> ${extract_vendor_dlkm_dir}/config/vendor_dlkm_file_contexts
		ui_print "- $_LANG_VENDOR_DLKM_REPACKING"
		rm -f ${home}/vendor_dlkm.img
		mkfs_erofs ${extract_vendor_dlkm_dir}/vendor_dlkm ${home}/vendor_dlkm.img || \
			abort "! $_LANG_VENDOR_DLKM_REPACK_FAILED"
		rm -rf ${extract_vendor_dlkm_dir}

		if [ "$(get_size ${home}/vendor_dlkm.img)" -gt "$vendor_dlkm_block_size" ]; then
			do_check_super_device_size=true
		else
			# Fill the erofs image file to the same size as the vendor_dlkm partition
			truncate -c -s $vendor_dlkm_block_size ${home}/vendor_dlkm.img
		fi
	fi

	if ${do_check_super_device_size}; then
		ui_print " "
		ui_print "- $_LANG_SUPER_SIZE_NEED_CHECK_PROMPT_1"
		ui_print "- $_LANG_SUPER_SIZE_NEED_CHECK_PROMPT_2"
		check_super_device_size  # If the check here fails, it will be aborted directly.
		ui_print "- $_LANG_SUPER_SIZE_NEED_CHECK_PASS"
	fi

	unset do_check_super_device_size vendor_dlkm_block_size vendor_dlkm_is_ext4 extract_vendor_dlkm_dir extract_vendor_dlkm_modules_dir
fi

unset do_backup_flag

flash_boot # skip ramdisk repack
flash_generic vendor_dlkm

########## FLASH BOOT & VENDOR_DLKM END ##########

# Remove files no longer needed to avoid flashing again.
rm ${home}/Image
rm ${home}/boot.img
rm ${home}/boot-new.img
rm ${home}/vendor_dlkm.img

unset magisk_patched
rm ${home}/magisk_patched

touch ${home}/rollback_if_abort_flag

########## FLASH VENDOR_BOOT START ##########

## vendor_boot shell variables
block=vendor_boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=true

# reset for vendor_boot patching
reset_ak

# Try to fix vendor_ramdisk size and vendor_ramdisk table entry information that was corrupted by old versions of magiskboot.
${bin}/vendor_boot_fix "$block"
case $? in
	0) ui_print " " "- $_LANG_VENDOR_BOOT_FIX_SUCCESS";;
	2) ;;  # The vendor_boot partition is normal and does not need to be repaired.
	*) abort "! $_LANG_VENDOR_BOOT_FIX_FAILED";;
esac

# vendor_boot install
dump_boot

vendor_boot_modules_dir=${ramdisk}/lib/modules
rm ${vendor_boot_modules_dir}/*
cp ${home}/_vendor_boot_modules/* ${vendor_boot_modules_dir}/
set_perm 0 0 0644 ${vendor_boot_modules_dir}/*

${bin}/7za x ${home}/_dtb.7z -o${home}/ || abort "! $_LANG_FAILED_TO_UNPACK _dtb.7z!"

if ${is_oss_kernel_rom}; then
	mv ${home}/dtbo-1.img ${home}/dtbo.img
	rm ${home}/dtbo-0.img
else
	mv ${home}/dtbo-0.img ${home}/dtbo.img
	rm ${home}/dtbo-1.img
fi

mkdir ${home}/_dtbs
cp ${split_img}/dtb ${home}/_dtbs/dtb
dtb_img_splitted=$(${bin}/dtp -i ${home}/_dtbs/dtb | awk '{print $NF}') || abort "! $_LANG_DTB_SPLIT_FAILED"
ukee_dtb=
for dtb_file in $dtb_img_splitted; do
	if [ "$(${bin}/fdtget $dtb_file / model -ts)" == "Qualcomm Technologies, Inc. Ukee SoC" ]; then
		ukee_dtb="$dtb_file"
		break
	fi
done
[ -z "$ukee_dtb" ] && abort "! $_LANG_DTB_NOT_FOUND_UKEE"

if ${disguised_adreno730}; then
	${bin}/fdtput ${home}/dtb "/soc/qcom,kgsl-3d0@3d00000" "qcom,gpu-model" "Adreno730v3" -ts
fi
unset disguised_adreno730

# Copy the gpu frequency and voltage configuration of old dtb to the new dtb
if [ "$(sha1 $ukee_dtb)" != "$(sha1 ${home}/dtb)" ]; then
	copy_gpu_pwrlevels_conf "$ukee_dtb" ${home}/dtb
	sync
fi

rm -rf ${home}/_dtbs

unset dtb_img_splitted ukee_dtb

write_boot  # Since dtbo.img exists in ${home}, the dtbo partition will also be flashed at this time

########## FLASH VENDOR_BOOT END ##########

unset is_hyperos_fw is_miui_rom is_aospa_rom is_oss_kernel_rom is_hyperos_fw_with_new_adsp2

# Patch vbmeta
ui_print " "
for vbmeta_blk in /dev/block/by-name/vbmeta*; do
	ui_print "- $_LANG_PATCHING $(basename $vbmeta_blk) ..."
	${bin}/vbmeta-disable-verification $vbmeta_blk || {
		ui_print "! $_LANG_FAILED_TO_PATCH ${vbmeta_blk}!"
		ui_print "- $_LANG_VBMETA_FAILED_PROMPT_1"
		ui_print "  $_LANG_VBMETA_FAILED_PROMPT_2"
	}
done

## end boot install
