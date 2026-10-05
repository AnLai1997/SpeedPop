TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CarSpeedBubblePrefs
CarSpeedBubblePrefs_FILES = SPPRootListController.m
CarSpeedBubblePrefs_INSTALL_PATH = /Library/PreferenceBundles
CarSpeedBubblePrefs_FRAMEWORKS = UIKit
CarSpeedBubblePrefs_PRIVATE_FRAMEWORKS = Preferences
CarSpeedBubblePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
