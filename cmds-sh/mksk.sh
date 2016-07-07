#!/bin/sh
#< mksk.sk - make a shortcut in $HOME/bin
# I have $HOME/bin in my PATH, and I like
BN=`basename "$0"`
TMPDST="$HOME/bin"
echo "$BN: '$0'"
if [ "$#" = "0" ]; then
    echo "$BN: add script name, to create a shortcut in '$TMPDST'"
    exit 1
fi
if [ ! -f "$1" ]; then
    echo "$BN: Can NOT locate script name '$1'! Check name, location..."
    exit 1
fi
if [ ! -x "$1" ]; then
    echo "$BN: Script name '$1' NOT executable! Check name, location..."
    exit 1
fi
TMPPATH=`readlink -e "$1"`
TMPBF=`basename "$1"`
TMPEXT="${TMPBF##*.}"
TMPBN="${TMPBF%.*}"
TMPSK="$TMPDST/$TMPBN"
if [ -f "$TMPSK" ]; then
    echo "$BN: Shortcut '$TMPSK' already exists! Move, rename, delete first..."
    exit 1
fi

echo "$BN: Will generate shortcut '$TMPSK'... "
echo "$BN: To script '$TMPPATH'"

### write_fgfs_script()
### {
cat <<EOT1 > $TMPSK
#!/bin/sh
$TMPPATH $*
EOT1
chmod 755 $TMPSK
echo "$BN: Created $TMPSK"
## }

# eof - mksk.sh

