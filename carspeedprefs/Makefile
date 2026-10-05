TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CarSpeedPrefs
CarSpeedPrefs_FILES = SPPRootListController.m
CarSpeedPrefs_INSTALL_PATH = /Library/PreferenceBundles
CarSpeedPrefs_FRAMEWORKS = UIKit
CarSpeedPrefs_PRIVATE_FRAMEWORKS = Preferences
CarSpeedPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
