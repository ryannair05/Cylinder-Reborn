ifeq ($(ROOTFUL),1)
# Built with the parent Makefile's Xcode 11 toolchain, for the same reason as the tweak.
ifeq ($(THEOS_CURRENT_ARCH),arm64)
TARGET := iphone:clang:13.7:11.0
else
TARGET := iphone:clang:13.7:12.0
endif
else
TARGET := iphone:clang:16.5:15.0
endif

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CylinderSettings
CylinderSettings_FILES = CLAlignedTableViewCell.m CLDonateController.m CLEffect.m CLEffectsController.m CLFormulasController.m CLTwitterCell.m CylinderSettings.m
CylinderSettings_INSTALL_PATH = /Library/PreferenceBundles

CylinderSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Cylinder.plist$(ECHO_END)