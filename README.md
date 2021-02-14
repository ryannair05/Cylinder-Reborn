# Cylinder

![](https://github.com/rweichler/cylinder/blob/cb8f000dfb1045b9b7cb872ba9b8c843f7f73ebc/code.png)

## Latest version: 1.0.0

[Here](https://github.com/ryannair05/Cylinder-Reborn/blob/master/packages/com.ryannair05.cylinder_1.0~ryannair05_iphoneos-arm.deb?raw=true)'s the deb.

## what???

This is a jailbreak tweak that lets you animate your icons when you swipe pages on the SpringBoard.

Differences to Barrel:

1. Combining multiple effects
2. Effects are written in [Lua](http://lua.org/about.html)

With Lua, the effects can be modified and created using just
a text editor (scripts are stored in /Library/Cylinder). No knowledge of C or
Objective-C is necessary. A noob-friendly tutorial can be found [here](https://github.com/rweichler/cylinder/wiki/Installing-and-modifying-Lua-scripts).

Custom scripts can be submitted to [/r/cylinder](http://reddit.com/r/cylinder).

If you want to make your own effects, check out [any of the 53 scripts that are bundled with Cylinder](https://github.com/rweichler/cylinder/tree/master/tweak/scripts). If you need more in-depth documentation you can check out
[EXAMPLE.lua](https://github.com/rweichler/cylinder/blob/master/tweak/scripts/EXAMPLE.lua)
as well.
Once you've made your own effect, make a folder with
your name in /Library/Cylinder on your phone (like
/Library/Cylinder/rweichler), drop your scripts in,
and it should appear in settings (no respring required).

Compatible with iOS 11-14.

# How to build/install this

This is for people that would like to contribute to the core (C / Objective-C) framework.
If you would like to create your own scripts, no extra setup is necessary. Just install Cylinder
on Cydia and follow the instructions above.

## Dependencies

* Mac OS X, Linux or jailbroken iOS
* Theos
* Xcode (or, clang/make and a copy of the iPhone SDK &gt;= iOS 13)
* liblua

## Setup

Clone the repository and cd into it

```
git clone https://github.com/ryannair05/Cylinder-Reborn.git
cd cylinder
```

### For those who don't have Xcode installed

Open `config.mk` and edit the line that says `SDK=` to reflect where your copy of the iPhone SDK is.

The theos team has been nice enough to host them for us here: https://github.com/theos/sdks

Just download one of those (must be >= iOS 13), unzip it somewhere, delete the original .tar.gz and paste wherever you unzipped it after the `SDK=` in the config.mk.

## Building

If you just want a .deb, run this:

```
make package
```

If you want it to build and install on your device, run this:
```
make do IPHONE_IP=iphone_wifi_ip_here
```
You need OpenSSH installed in order for the installation to work.

## License

[MIT](https://github.com/rweichler/cylinder/blob/master/LICENSE)
