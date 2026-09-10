ARCHS = arm64
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OBDelevenUpdateBypassPrefs

OBDelevenUpdateBypassPrefs_FILES = OBDUBRootListController.m
OBDelevenUpdateBypassPrefs_FRAMEWORKS = UIKit CoreFoundation
OBDelevenUpdateBypassPrefs_PRIVATE_FRAMEWORKS = Preferences
OBDelevenUpdateBypassPrefs_INSTALL_PATH = /Library/PreferenceBundles
OBDelevenUpdateBypassPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
