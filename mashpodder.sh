#!/bin/bash
#
# $Id$
#
# Mashpodder by Chess Griffin <chess.griffin@gmail.com>
# Copyright 2009-2013
# Licensed under the GPLv3
#
# Originally based on BashPodder by Linc Fessenden 12/1/2004

### START USER CONFIGURATION
# Default values can be set here. Command-line flags can override some of
# these but not all of them.

# BASEDIR: Base location of the script and related files.  If you have an
# escaped space in the directory name be sure to keep the double quotes.
# Default is "$HOME/mashpodder".  This is commented out on purpose to start
# with in order to force the user to review this USER CONFIGURATION section
# and set the various options. Uncomment and set to desired path.  Mashpodder
# will not create this directory for you.
#BASEDIR="$HOME/mashpodder"

# PODCASTDIR: Location of podcast directories listed in mp.conf.  If you have
# an escaped space in the directory name be sure to keep the double quotes.
# Default is "$BASEDIR/podcasts".  Thanks to startrek.steve for reporting the
# issues that led to these directory changes.  Mashpodder will create this
# directory if it does not exist.
PODCASTDIR="$BASEDIR/podcasts"

# TMPDIR: Location of temp logs, where files are temporarily downloaded to,
# and other bits.  If you have an escaped space in the directory name be sure
# to keep the double quotes.  Mashpodder will create this directory if it does
# not exist.  Default is "$BASEDIR/tmp".
TMPDIR="$BASEDIR/tmp"

# DATESTRING: Valid date format for date-based archiving.  Can be changed to
# other valid formats.  See man date.  Default is "%Y%m%d".
DATESTRING="%Y%m%d"

# RSSFILE: Location of mp.conf file.  Can be changed to another file name.
# Default is "$BASEDIR/mp.conf".
RSSFILE="$BASEDIR/mp.conf"

# PARSE_ENCLOSURE: Location of parse_enclosure.xsl file.  Default is
# "$BASEDIR/parse_enclosure.xsl".
PARSE_ENCLOSURE="$BASEDIR/parse_enclosure.xsl"

# PODLOG: This is a critical file.  This is the file that saves the name of
# every file downloaded (or checked with the 'update' option in mp.conf.)  If
# you lose this file then mashpodder should be able to automatically recreate
# it during the next run, but it's still a good idea to make sure the file is
# kept in a safe place.  Default is "$BASEDIR/podcast.log".
PODLOG="$BASEDIR/podcast.log"

# PODLOG_BACKUP: Setting this option to "1" will create a date-stamped backup
# of your podcast.log file before new podcast files are downloaded.  The
# filename will be $PODLOG.$DATESTRING (see above variables).  If you enable
# this, you'll want to monitor the number of backups and manually remove old
# copies.  Default is "".
PODLOG_BACKUP=""

# FIRST_ONLY: Default "" means look to mp.conf for whether to download or
# update; "1" will override mp.conf and download the newest episode.
FIRST_ONLY=""

# M3U: Default "" means no m3u playlist created; "1" will create m3u
# playlists in each podcast's directory listing all the files in that
# directory.
M3U=""

# DAILY_PLAYLIST: Default "" means no daily m3u playlist created; "1" will
# create an m3u playlist in $PODCASTDIR listing all newly downloaded shows.
# The m3u filename will have the $DATESTRING prepended to it and additional
# new downloads for that day will be added to the file.  NOTE: $M3U must also
# be set to "1" for this to work.
DAILY_PLAYLIST=""

# UPDATE: Default "" means look to mp.conf on whether to download or update;
# "1" will override mp.conf and cause all feeds to be updated (meaning
# episodes will be marked as downloaded but not actually downloaded).
UPDATE=""

# VERBOSE: Default "" is quiet output; "1" is verbose.
VERBOSE=""

# WGET_QUIET: Default is "-q" for quiet wget output; change to "" for wget
# output.
WGET_QUIET="-q"

# WGET_TIMEOUT: Default is 30 seconds; can decrease or increase if some files
# are cut short. Thanks to Phil Smith for the bug report.
WGET_TIMEOUT="30"

# SYNC: Sync (via rsync) new downloads with media player: Default "" will not
# sync; "1" will sync - need to also set SYNCDIR.  THIS FEATURE IS STILL IN
# BETA - PLEASE BE CAREFUL AND TEST.  I am thinking about removing this
# feature because I don't think it's really necessary and can be handled in
# a wrapper script.  Please let me know if you use it otherwise I might take
# it out at any time.
SYNC=""

# SYNCDIR: Set mountpoint or path where new episodes should be synced.  Must
# be writable by user executing this script.  Again, use double quotes if
# there is an escaped space.
SYNCDIR="/mnt/device/podcasts"

### END USER CONFIGURATION

### No changes should be necessary below this line

SCRIPT=${0##*/}
REV="$Revision$"
VER=svn_r$(cut -d' ' -f2 <<< "$REV")
CWD=$(pwd)
TEMPLOG="$TMPDIR/temp.log"
SUMMARYLOG="$TMPDIR/summary.log"
TEMPRSSFILE="$TMPDIR/mp.conf.temp"
DAILYPLAYLIST="$PODCASTDIR/$(date +$DATESTRING)_daily_playlist.m3u"
OLDIFS=$IFS
IFS=$'\n'

crunch () {
    echo -e "$@" | tr -s ' ' | fmt -78
}

verbose () {
    if [ "$VERBOSE" = "1" ]; then
        return 0
    else
        return 1
    fi
}

sanity_checks () {
    # Perform some basic checks
    local FEED ARCHIVETYPE DLNUM DATADIR NEWPODLOG

    if [ -z $BASEDIR ]; then
        crunch "\$BASEDIR has not been set.  Please review the USER \
            CONFIGURATION section at the top of mashpodder.sh and set \
            \$BASEDIR and any other applicable options."
        exit 0
    fi

    if [ ! -e $BASEDIR ]; then
        crunch "\$BASEDIR does not exist.  Please re-check the settings \
            at the top of mashpodder.sh and try again."
        exit 0
    fi

    cd $BASEDIR

    # Make podcast directory if necessary
    if [ ! -e $PODCASTDIR ]; then
        if verbose; then
            echo "Creating podcast directory."
        fi
        mkdir -p $PODCASTDIR
    fi

    # Make tmp directory if necessary
    if [ ! -e $TMPDIR ]; then
        if verbose; then
            echo "Creating temporary directory."
        fi
        mkdir -p $TMPDIR
    fi

    rm -f $TEMPRSSFILE
    touch $TEMPRSSFILE

    # Make sure the mp.conf file or the file passed with -c switch exists
    if [ ! -e "$RSSFILE" ]; then
        crunch "The file $RSSFILE cannot be found.  Run $0 -h \
            for usage and check the settings at the top of mashpodder.sh.\
            Exiting."
        exit 0
    fi

    # Check the mp.conf and do some basic error checking
    while read LINE; do
        DLNUM="none"
        FEED=$(echo $LINE | cut -f1 -d ' ')
        ARCHIVETYPE=$(echo $LINE | cut -f2 -d ' ')
        DLNUM=$(echo $LINE | cut -f3 -d ' ')

        # Skip blank lines and lines beginning with '#'
        if echo $LINE | grep -E '^#|^$' > /dev/null
                then
                continue
        fi

        if [[ "$DLNUM" != "none" && "$DLNUM" != "all" && \
            "$DLNUM" != "update" && $DLNUM -lt 1 ]]; then
            crunch "Something is wrong with the download type for $FEED. \
                According to $RSSFILE, it is set to $DLNUM. \
                It should be set to 'none', 'all', 'update', or a number \
                greater than zero.  Please check $RSSFILE.  Exiting"
            exit 0
        fi

        # Check type of archiving for each feed
        if [ "$DLNUM" = "update" ]; then
            DATADIR=$ARCHIVETYPE
        else
            if [ ! "$ARCHIVETYPE" = "date" ]; then
                DATADIR=$ARCHIVETYPE
            elif [ "$ARCHIVETYPE" = "date" ]; then
                DATADIR=$(date +$DATESTRING)
            else
                crunch "Error in archive type for $FEED.  It should be set \
                    to 'date' for date-based archiving, or to a directory \
                    name for directory-based archiving.  Exiting."
                exit 0
            fi
        fi

        if [ "$FIRST_ONLY" = "1" ]; then
            DLNUM="1"
        fi
        if [ "$UPDATE" = "1" ]; then
            DLNUM="update"
        fi
        echo "$FEED $DATADIR $DLNUM" >> $TEMPRSSFILE
    done < $RSSFILE

    # Backup the $PODLOG if $PODLOG_BACKUP=1
    if [ "$PODLOG_BACKUP" = "1" ]; then
        if verbose; then
            echo "Backing up the $PODLOG file."
        fi
        NEWPODLOG="$PODLOG.$(date +$DATESTRING)"
        cp $PODLOG $NEWPODLOG
    fi

    # Check to make sure SYNCDIR exists if SYNC=1
    if [ "$SYNC" = "1" ]; then
        if [ ! -d "$SYNCDIR" ]; then
            crunch "$SYNCDIR does not exist.  Exiting."
            exit 0
        fi
    fi
}

initial_setup () {
    # Get some things ready first

    # Print the date
    if verbose; then
        echo
        echo "################################"
        echo "Starting mashpodder on"
        date
        echo
    fi

    # Delete the temp log:
    rm -f $TEMPLOG
    touch $TEMPLOG

    # Create podcast log if necessary
    if [ ! -e $PODLOG ]; then
        if verbose; then
            echo "Creating $PODLOG file."
        fi
        touch $PODLOG
    fi
}

fix_url () {
    # Take a url embedded in a feed, get the filename, and perform some fixes
    local FIXURL

    FIXURL=$1

    # Get the filename
    FIRSTFILENAME=$(echo $FIXURL|awk -F / '{print $NF}')
    FILENAME=$(echo $FIRSTFILENAME|awk -F "?" '{print $1}')

    # Remove parentheses in filenames
    FILENAME=$(echo $FILENAME | tr -d "()")

    # Replace URL hex sequences in filename (like %20 for ' ' and %2B for '+')
    FILENAME=$(echo "echo $FILENAME" \
        |sed "s/%\(..\)/\$(printf \"\\\\x\\1\")/g" |bash)

    # Replace spaces in filename with underscore
    FILENAME=$(echo $FILENAME | sed -e 's/ /_/g')

    # Fix Podshow.com numbers that keep changing
    FILENAME=$(echo $FILENAME | sed -e 's/_pshow_[0-9]*//')

    # Fix MSNBC podcast names for audio feeds from Brian Reichart
    if echo $FIXURL | grep -q "msnbc.*pd_.*mp3$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(pd_.*mp3$\)/\1/')
        return
    fi
    if echo $FIXURL | grep -q "msnbc.*pdm_.*mp3$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(pdm_.*mp3$\)/\1/')
        return
    fi
    if echo $FIXURL | grep -q "msnbc.*vh-.*mp3$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(vh-.*mp3$\)/\1/')
        return
    fi
    if echo $FIXURL | grep -q "msnbc.*zeit.*m4v$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(a_zeit.*m4v$\)/\1/')
    fi

    # Fix MSNBC podcast names for video feeds
    if echo $FIXURL | grep -q "msnbc.*pdv_.*m4v$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(pdv_.*m4v$\)/\1/')
        return
    fi

    # Remove question marks at end
    FILENAME=$(echo $FILENAME | sed -e 's/?.*$//')
}

check_directory () {
    # Check to see if DATADIR exists and if not, create it
    if [ ! -e $PODCASTDIR/$DATADIR ]; then
        crunch "The directory $PODCASTDIR/$DATADIR for $FEED does not \
            exist.  Creating now..."
        mkdir -p $PODCASTDIR/$DATADIR
    fi
    return 0
}

fetch_podcasts () {
    # This is the main loop
    local LINE FEED DATADIR DLNUM COUNTER FILE URL FILENAME DLURL

    # Read the mp.conf file and wget any url not already in the
    # podcast.log file:
    NEWDL=0
    while read LINE; do
        FEED=$(echo $LINE | cut -f1 -d ' ')
        DATADIR=$(echo $LINE | cut -f2 -d ' ')
        DLNUM=$(echo $LINE | cut -f3 -d ' ')
        COUNTER=0

        if verbose; then
            if [ "$DLNUM" = "all" ]; then
                crunch "Checking $FEED -- all episodes."
            elif [ "$DLNUM" = "none" ]; then
                crunch "No downloads selected for $FEED."
                echo
                continue
            elif [ "$DLNUM" = "update" ]; then
                crunch "Catching $FEED up in logs."
            else
                crunch "Checking $FEED -- last $DLNUM episodes."
            fi
        fi

        FILE=$(wget -q $FEED -O - | \
            xsltproc $PARSE_ENCLOSURE - 2> /dev/null) || \
            # Let's try the diff from turbooster as reported in Issue 13.
            # If it causes problems, uncomment the next line and comment
            # out the one after that (the one with "grep url=" in it.
            #FILE=$(wget -q $FEED -O - | tr '\r' '\n' | tr \' \" | \
            FILE=$(wget -q $FEED -O - | grep url= | \
            sed -n 's/.*url="\([^"]*\)".*/\1/p')

        for URL in $FILE; do
            FILENAME=''
            if [ "$DLNUM" = "$COUNTER" ]; then
                break
            fi
            DLURL=$(curl -s -I -L -w %{url_effective} --url $URL | tail -n 1)
            fix_url $DLURL
            echo $FILENAME >> $TEMPLOG

            if ! grep -x "^$FILENAME" $PODLOG > /dev/null; then
                if [ "$DLNUM" = "update" ]; then
                    if verbose; then
                        crunch "Adding $FILENAME to log."
                        echo "$FILENAME added to log" >> $SUMMARYLOG
                    fi
                    continue
                fi
                check_directory $DATADIR
                if [ ! -e $PODCASTDIR/$DATADIR/"$FILENAME" ]; then
                    if verbose; then
                        crunch "NEW:  Fetching $FILENAME and saving in \
                            directory $DATADIR."
                        echo "$FILENAME downloaded to $DATADIR" >> $SUMMARYLOG
                    fi
                    cd $TMPDIR
                    wget $WGET_QUIET -c -T $WGET_TIMEOUT -O "$FILENAME" \
                        "$DLURL"
                    ((NEWDL=NEWDL+1))
                    mv "$FILENAME" $PODCASTDIR/$DATADIR/"$FILENAME"
                    if [ "$SYNC" = "1" ]; then
                        crunch "Syncing $FILENAME to $SYNCDIR"
                        rsync -az $PODCASTDIR/$DATADIR $SYNCDIR
                    fi
                    cd $BASEDIR
                    if [[ -n "$M3U" && -n "$DAILY_PLAYLIST" ]]; then
                        if verbose; then
                            echo "Adding "$FILENAME" to daily playlist."
                        fi
                        echo $DATADIR/"$FILENAME" >> $DAILYPLAYLIST
                    fi
                fi
            fi
            ((COUNTER=COUNTER+1))
        done
        # Create an m3u playlist:
        #if [[ "$DLNUM" != "update" && $NEWDL -gt 0 ]]; then
        if [[ "$DLNUM" != "update" ]]; then
            if [ -n "$M3U" ]; then
                if verbose; then
                    crunch "Creating $DATADIR m3u playlist."
                fi
                ls $PODCASTDIR/$DATADIR | grep -v m3u > \
                    $PODCASTDIR/$DATADIR/podcast.m3u
                if [ "$SYNC" = "1" ]; then
                    crunch "Syncing $DATADIR m3u playlist to $SYNCDIR"
                    rsync -az $PODCASTDIR/$DATADIR $SYNCDIR
                fi
            fi
        fi
        if verbose; then
            crunch "Done.  Continuing to next feed."
            echo
        fi
    done < $TEMPRSSFILE
    if [ ! -f $TEMPLOG ]; then
        if verbose; then
            crunch "Nothing to download."
        fi
    fi
}

final_cleanup () {
    # Delete temp files, create the log files, and clean up
    if verbose; then
        crunch "Cleaning up."
    fi
    cat $PODLOG >> $TEMPLOG
    sort $TEMPLOG | uniq > $PODLOG
    rm -f $TEMPLOG
    if [ -e $DAILYPLAYLIST ]; then
        cat $DAILYPLAYLIST >> $TEMPLOG
        sort $TEMPLOG | uniq > $DAILYPLAYLIST
        rm -f $TEMPLOG
    fi
    rm -f $TEMPRSSFILE
    if verbose; then
        echo "Total downloads: $NEWDL"
        echo "All done."
        if [ -e $SUMMARYLOG ]; then
            echo
            echo "++SUMMARY++"
            cat $SUMMARYLOG
            rm -f $SUMMARYLOG
        fi
        echo "################################"
    fi
    # These next 2 lines were moved here so if the user kills the program
    # with ctrl-C (see the trap code, below), they will also cd to cwd before
    # exiting.
    cd $CWD
    IFS=$OLDIFS
}

# THIS IS THE ACTUAL START OF SCRIPT
# Here are the command line switches
while getopts ":bc:d:fmsuvh" OPT ;do
    case $OPT in
        b )         PODLOG_BACKUP=1
                    ;;
        c )         RSSFILE="$OPTARG"
                    ;;
        d )         DATESTRING="$OPTARG"
                    ;;
        f )         FIRST_ONLY=1
                    ;;
        m )         M3U=1
                    ;;
        s )         SYNC=1
                    ;;
        u )         UPDATE=1
                    ;;
        v )         VERBOSE=1
                    ;;
        h|* )       cat << EOF
$SCRIPT $VER
Usage: $0 [OPTIONS] <arguments>
Options are:

-b              Create a date-stamped backup of the podcast.log file.

-c <filename>   Use a different config file other than mp.conf.

-d <date>       Valid date string for date-based archiving.  See man date.

-f              Override mp.conf and download the first new episode.

-h              Display this help message.

-m              Create m3u playlists.

-s              Sync with media player (must set SYNCDIR in script).

-u              Override mp.conf and only update (mark downloaded).

-v              Display verbose messages.

mp.conf is the standard configuration file.  Please see the sample mp.conf for
how this file is to be configured.

Some -- but not all -- of the default settings can be set permanently at the
top of the script in the 'USER CONFIGURATION' section or temporarily by passing
a command line switch.  The 'USER CONFIGURATION' section also has additional
things you can set that do not have compatible command-line switches.

Therefore, reading mashpodder.sh is recommended.

EOF
                    exit 0
                    ;;
    esac
done

# End of option parsing

shift $(($OPTIND - 1))

# Trap ctrl-C's and other interrupts, clean up temp files, and exit cleanly.
# Thanks to mr.gaga for the report.
for sig in INT TERM HUP; do
    trap "
    echo
    echo signal $sig recived
    final_cleanup
    exit 0" $sig;
done

sanity_checks
initial_setup
fetch_podcasts
final_cleanup

exit 0
