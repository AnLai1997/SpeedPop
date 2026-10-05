TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LimitBubblePrefs
LimitBubblePrefs_FILES = SPPRootListController.m
LimitBubblePrefs_INSTALL_PATH = /Library/PreferenceBundles
LimitBubblePrefs_FRAMEWORKS = UIKit
LimitBubblePrefs_PRIVATE_FRAMEWORKS = Preferences
LimitBubblePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
