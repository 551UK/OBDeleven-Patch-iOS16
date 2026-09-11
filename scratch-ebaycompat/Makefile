ARCHS = arm64 arm64e
TARGET = iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = eBayCompat14
eBayCompat14_FILES = Tweak.xm
eBayCompat14_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
eBayCompat14_FRAMEWORKS = Foundation UIKit CoreFoundation WebKit

include $(THEOS_MAKE_PATH)/tweak.mk
