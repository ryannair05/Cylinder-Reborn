# Thanks to opa334 for this
# plipo: patched up version of lipo by Matchstic (see: https://github.com/theos/theos/issues/563#issuecomment-759609420)
# Put it into /usr/local/bin and run sudo chmod +x /usr/local/bin/plipo

PLIPO_TMP="./plipo_tmp"

populatePlipoTmp () {
	fileOutput=$(file $1)
	if [[ $fileOutput == *"dynamically linked shared library"* ]]; then
		if [[ $1 != *"/arm64e/"* ]]; then
			plipo_tmp_file=./$PLIPO_TMP/$(basename $1)
			cp $1 $plipo_tmp_file
		fi
	fi
}

consumePlipoTmp () {
	fileOutput=$(file $1)
	if [[ $fileOutput == *"dynamically linked shared library"* ]]; then
		if [[ $1 != *"/arm64e/"* ]] && [[ $1 != *"/arm64/"* ]]; then
			plipo_tmp_file=./$PLIPO_TMP/$(basename $1)
			plipo $1 $plipo_tmp_file -output $1 -create
		fi
	fi
}

make clean
echo "Building Xcode 12 slice..."
make FINALPACKAGE=1 XCODE_12_SLICE=1
mkdir $PLIPO_TMP

find ./.theos/obj -print0 | while IFS= read -r -d '' file; do populatePlipoTmp "$file"; done

make clean
echo "Building other slices..."
make FINALPACKAGE=1 XCODE_12_SLICE=0

echo "Combining..."
find ./.theos/obj -print0 | while IFS= read -r -d '' file; do consumePlipoTmp "$file"; done

rm -rf plipo_tmp
echo "Packaging..."

# just running make package works because theos detects that the dylib
# already exists so it just uses that to package instead of recompiling

if [ "$1" == "install" ] || [ "$1" == "do" ]; then
make package FINALPACKAGE=1 install
else
make package FINALPACKAGE=1
fi