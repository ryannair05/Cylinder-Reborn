THEOS_DEVICE_IP = 192.168.1.208

FINALPACKAGE = 1

export XCODE_12_SLICE ?= 0

ifeq ($(XCODE_12_SLICE), 1)
	export ARCHS = arm64e
else
	export ARCHS = arm64 arm64e
	export PREFIX = $(THEOS)/toolchain/Xcode.xctoolchain/usr/bin/
endif

ifeq ($(THEOS_CURRENT_ARCH),arm64)
	export TARGET = iphone:clang:13.5:11.0
else
	export TARGET = iphone:clang:13.5:12.0
endif

export ADDITIONAL_CFLAGS = -DTHEOS_LEAN_AND_MEAN -fobjc-arc

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Cylinder
$(TWEAK_NAME)_LIBRARIES += lua5.4
Cylinder_FILES = tweak/tweak.x $(wildcard tweak/*.m)

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += settings
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Cylinder/$(ECHO_END)
	$(ECHO_NOTHING)cp -r scripts/ $(THEOS_STAGING_DIR)/Library/Cylinder/$(ECHO_END)