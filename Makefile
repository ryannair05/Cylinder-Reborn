THEOS_DEVICE_IP = 10.169.121.44

FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Rootless packages cover iOS 15 and later. `make package ROOTFUL=1` builds for iOS 11 through 14.
ifeq ($(ROOTFUL),1)
# iOS 12 and 13 only load arm64e code built with the arm64e ABI that predates iOS 14, which only
# Xcode 11's compiler produces (theos.dev/docs/arm64e-deployment);
# Command Line Tools for Xcode 11.5 provide that toolchain, unpacked to $(THEOS)/toolchain/Xcode.xctoolchain,
# You can remove PREFIX if you want to build for iOS 14+
export PREFIX = $(THEOS)/toolchain/Xcode.xctoolchain/usr/bin/
ifeq ($(THEOS_CURRENT_ARCH),arm64)
export TARGET = iphone:clang:13.7:11.0
else
export TARGET = iphone:clang:13.7:12.0
endif
else
export TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
endif

export ADDITIONAL_CFLAGS = -DTHEOS_LEAN_AND_MEAN -fobjc-arc -DLUA_USE_IOS

ifneq ($(ROOTFUL),1)
export ADDITIONAL_CFLAGS += -fno-ptrauth-objc-class-ro
endif

ifneq ($(CYLINDER_SIMJECT),)
export ADDITIONAL_CFLAGS += -DCYLINDER_SIMJECT=1
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Cylinder
Cylinder_FILES = tweak/tweak.x $(filter-out tweak/CylinderSimHarness.m,$(wildcard tweak/*.m)) lua/onelua.c
# MAKE_LIB leaves out the standalone interpreter's main().
lua/onelua.c_CFLAGS = -DMAKE_LIB -O2

ifneq ($(CYLINDER_SIMJECT),)
Cylinder_FILES += tweak/CylinderSimHarness.m
endif

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += settings
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Cylinder/$(ECHO_END)
	$(ECHO_NOTHING)rsync -a --exclude .DS_Store --exclude run-simject.sh scripts/ $(THEOS_STAGING_DIR)/Library/Cylinder/$(ECHO_END)

.PHONY: simject
simject:
	./scripts/run-simject.sh

