THEOS_DEVICE_IP = 192.168.1.245

FINALPACKAGE = 1

export PREFIX = $(THEOS)/toolchain/Xcode.xctoolchain/usr/bin/

ifeq ($(THEOS_CURRENT_ARCH),arm64)
	export TARGET = iphone:clang:13.5:11.0
else
	export TARGET = iphone:clang:13.5:12.0
endif

export ADDITIONAL_CFLAGS = -DTHEOS_LEAN_AND_MEAN -fobjc-arc

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Cylinder
Cylinder_FILES = tweak/tweak.x $(wildcard tweak/*.m) lua/onelua.c

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += settings
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Cylinder/$(ECHO_END)
	$(ECHO_NOTHING)rsync -a --exclude .DS_Store scripts/ $(THEOS_STAGING_DIR)/Library/Cylinder/$(ECHO_END)