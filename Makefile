ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OBDelevenUpdateBypass
OBDelevenUpdateBypass_FILES = Tweak.m
OBDelevenUpdateBypass_CFLAGS = -fvisibility=hidden -fobjc-arc
OBDelevenUpdateBypass_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
