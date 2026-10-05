# Dopamine (rootless) - iOS 15.0 -> 16.6.1, SDK 16.5
TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

# "CarPlay" la ten process cua com.apple.CarPlayApp; "Runner" la process cua Vietmap Live (Flutter); "GOFA" = com.lumi.GOFA
INSTALL_TARGET_PROCESSES = SpringBoard CarPlay Runner GOFA

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CarSpeedBubble
CarSpeedBubble_FILES = $(wildcard src/hooks/*.xm) $(wildcard src/*.mm)
CarSpeedBubble_CFLAGS = -fobjc-arc -Isrc
CarSpeedBubble_FRAMEWORKS = UIKit QuartzCore CoreLocation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += carspeedbubbleprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# entry.plist cho PreferenceLoader -> /var/jb/Library/PreferenceLoader/Preferences/
after-stage::
	mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	cp carspeedbubbleprefs/entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CarSpeedBubblePrefs.plist"
	find "$(THEOS_STAGING_DIR)" -type f | sort
