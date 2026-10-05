TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CSBubblePrefs
CSBubblePrefs_FILES = SPPRootListController.m
CSBubblePrefs_INSTALL_PATH = /Library/PreferenceBundles
CSBubblePrefs_FRAMEWORKS = UIKit
CSBubblePrefs_PRIVATE_FRAMEWORKS = Preferences
CSBubblePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
