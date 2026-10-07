TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CarSpeedPrefs
CarSpeedPrefs_FILES = SPPRootListController.m
CarSpeedPrefs_INSTALL_PATH = /Library/PreferenceBundles
CarSpeedPrefs_FRAMEWORKS = UIKit
CarSpeedPrefs_PRIVATE_FRAMEWORKS = Preferences
# Version shown in the footer card (TWEAK_VERSION), read from ../control
SPP_VERSION := $(shell grep -m1 '^Version:' ../control | cut -d' ' -f2 | tr -d '\r')
CarSpeedPrefs_CFLAGS = -fobjc-arc -DTWEAK_VERSION='"$(SPP_VERSION)"'

include $(THEOS_MAKE_PATH)/bundle.mk
