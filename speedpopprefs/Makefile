TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SpeedPopPrefs
SpeedPopPrefs_FILES = SPPRootListController.m
SpeedPopPrefs_INSTALL_PATH = /Library/PreferenceBundles
SpeedPopPrefs_FRAMEWORKS = UIKit
SpeedPopPrefs_PRIVATE_FRAMEWORKS = Preferences
SpeedPopPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
