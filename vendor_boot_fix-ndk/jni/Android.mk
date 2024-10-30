APP_PLATFORM := android-16
APP_PIE := true
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE            := vendor_boot_fix
LOCAL_MODULE_FILENAME   := vendor_boot_fix
LOCAL_SRC_FILES         := ../vendor_boot_fix.c
LOCAL_C_INCLUDES        := $(LOCAL_PATH)/..
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/..
LOCAL_CFLAGS            := -Os
LOCAL_LDFLAGS           := -static
include $(BUILD_EXECUTABLE)
