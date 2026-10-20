# Cylinder

![](https://github.com/rweichler/cylinder/blob/cb8f000dfb1045b9b7cb872ba9b8c843f7f73ebc/code.png)

## Download

Grab the latest `.deb` from the [Releases page](https://github.com/ryannair05/Cylinder-Reborn/releases/latest):

* `iphoneos-arm64`: rootless (iOS 15 and later)
* `iphoneos-arm`: rootful (iOS 11-14)

## what???

This is a jailbreak tweak that lets you animate your icons when you swipe pages on the SpringBoard.

Differences to Barrel:

1. Combining multiple effects
2. Effects are written in [Lua](http://lua.org/about.html)

With Lua, the effects can be modified and created using just
a text editor (scripts are stored in /Library/Cylinder). No knowledge of C or
Objective-C is necessary. A noob-friendly tutorial can be found [here](https://github.com/rweichler/cylinder/wiki/Installing-and-modifying-Lua-scripts).

Custom scripts can be submitted to [/r/cylinder](http://reddit.com/r/cylinder).

If you want to make your own effects, check out [any of the 53 scripts that are bundled with Cylinder](https://github.com/ryannair05/Cylinder-Reborn/tree/master/scripts).
If you need more in-depth documentation you can check out [EXAMPLE.lua](https://github.com/ryannair05/Cylinder-Reborn/blob/master/scripts/EXAMPLE.lua) as well.
Once you've made your own effect, make a folder with
your name in /Library/Cylinder on your phone (like
/Library/Cylinder/rweichler), drop your scripts in,
and it should appear in settings (no respring required).

Compatible with iOS 11-27.

# How to build/install this

This is for people that would like to contribute to the core (C / Objective-C) framework.
If you would like to create your own scripts, no extra setup is necessary. Just install Cylinder Reborn
on Cydia or Sileo and follow the instructions above.

## Dependencies

* macOS with Xcode
* [Theos](https://theos.dev/docs/installation)
* `iPhoneOS16.5.sdk` in `$THEOS/sdks`, from [theos/sdks](https://github.com/theos/sdks). The settings bundle builds against it.
* For rootful packages (iOS 11-14) only:
  * `iPhoneOS13.7.sdk` in `$THEOS/sdks`
  * The toolchain from Command Line Tools for Xcode 11.5, unpacked to `$THEOS/toolchain/Xcode.xctoolchain`.
    iOS 12 and 13 only load arm64e code built by Xcode 11's compiler, so newer toolchains cannot build this package.

Lua is included as a git submodule and built with the tweak, so it does not need to be installed separately.
Theos links [libroot](https://github.com/opa334/libroot) automatically, which finds the jailbreak root on rootful,
rootless and roothide jailbreaks.

## Setup

Clone the repository with its Lua submodule and cd into it

```
git clone --recursive https://github.com/ryannair05/Cylinder-Reborn.git
cd Cylinder-Reborn
```

If you already cloned it without `--recursive`, run `git submodule update --init`.

## Building

For a rootless .deb (iOS 15 and later):

```
make package
```

For a rootful .deb (iOS 11-14):

```
make package ROOTFUL=1
```

Packages are written to `packages/`. To build and install on your device over SSH, run this:

```
make do THEOS_DEVICE_IP=iphone_wifi_ip_here
```

Your device needs OpenSSH installed for the installation to work.