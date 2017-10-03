#!/bin/sh
# Common boilerplate bootstrap script for all Oblong projects.
# Currently for internal Oblong use only.
# Installs latest versions of oblong-bau and oblong-obs,
# installs bld/pre-commit (if present) as .git/hooks/pre-commit,
# and installs oblong-spruce (if the git hooks refer to it).

usage() {
    cat <<_EOF_
Prepare this machine and source tree for building with bau.
By default, just tells you what it would do.

Options:
-f       actually do it
-u       get latest obs and bau even if they seem up to date
_EOF_
}

set -e

# Required versions (capital to match spelling in bau and obs)
# If this project needs a newer version of obs or bau, just update these
# to match the output of --version from the latest versions of obs and bau.
# (FIXME: should we just query the server for the latest every time?)
OBS_VERSIONOID=91
BAU_VERSIONOID=46

is_ubuntu() {
    grep -i ubuntu /etc/issue > /dev/null 2>&1
}

is_mac() {
    test "$(uname)" = Darwin
}

is_win() {
    test "$OS" = Windows_NT
}

doit() {
    didit=true
    if "$dryrun"
    then
        echo "dry-run, so not doing: $*" >&2
    else
        echo "doing: $*" >&2
        "$@"
    fi
}

apt_update() {
    if $updated
    then
        return
    fi
    if ! doit sudo apt-get update > apt.log
    then
        echo "apt update failed"; cat apt.log; exit 1
    fi
    rm apt.log
    updated=true
}

# Get access to the oblong and/or brew repository we need, if any
bs_install_repo_if_needed() {
    if is_mac
    then
        if ! echo "$PATH" | grep /usr/local/bin > /dev/null
        then
            # osx 10.11 systemd doesn't put /usr/local/bin on path
            PATH=/usr/local/bin:$PATH
        fi

        if ! brew --version > /dev/null
        then
            doit /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
        fi
    elif is_ubuntu
    then
        # Be even more careful to not install oblong-repo if user already has it some other way
        if ! test -s /etc/apt/sources.list.d/oblong.list && ! grep buildhost4 /etc/apt/sources.list.d/*.list > /dev/null
        then
            doit rm -f oblong-repo_1.7_all.deb
            doit wget http://buildhost4.oblong.com/oblong-repo/oblong-repo_1.7_all.deb
            doit sudo dpkg -i oblong-repo_1.7_all.deb
            doit rm -f oblong-repo_1.7_all.deb
        fi
    fi
}

# Return true if obs exists and is up to date
bs_check_obs() {
    # make sure latest supported g-speak has right versions
    obs --version > /dev/null 2>&1 &&
     test "$(obs --version | awk '/obs versionoid/ {print $3}')" -ge "$OBS_VERSIONOID"
}

bs_install_obs() {
    if is_mac
    then
        doit brew tap oblong/tools
        doit brew upgrade obs || doit brew install obs
    elif is_win
    then
        doit rm -rf obs-git
        doit git clone git@gitlab.oblong.com:platform/obs.git obs-git
        doit cd obs-git
        doit make install
        doit cd ..
        doit rm -rf obs-git
    elif is_ubuntu
    then
        apt_update
        doit sudo apt-get -y install oblong-obs
    else
        echo "baugen.sh: what os is this?"
        exit 1
    fi
    if ! "$dryrun" && ! bs_check_obs
    then
        echo "baugen.sh: Could not bootstrap an up-to-date oblong-obs"
        exit 1
    fi
}

# Return true if bau exists and is up to date
bs_check_bau() {
    bau --version > /dev/null &&
     test "$(bau --version | awk '/bau versionoid/ {print $3}')" -ge "$BAU_VERSIONOID"
}

bs_install_bau() {
    if is_mac
    then
        doit obs install oblong-bau
    elif is_win
    then
        doit rm -rf ob-repobot-git
        doit git clone git@gitlab.oblong.com:platform/ob-repobot.git ob-repobot-git
        doit cd ob-repobot-git
        doit make install
        doit cd ..
        doit rm -rf ob-repobot-git
    else
        apt_update
        doit sudo apt-get install -y oblong-bau
    fi
    if ! "$dryrun" && ! bs_check_bau
    then
        echo "baugen.sh: Could not bootstrap an up-to-date oblong-bau"
        exit 1
    fi
}

bs_install_hooks_if_needed() {
    for hook in $git_hooks
    do
        if test -f "bld/$hook" && ! test -f "$githook_dir/$hook"
        then
            doit ln -fs "../../bld/$hook" "$githook_dir"
        fi
    done
}

bs_install_spruce_if_needed() {
    if ! grep -q spruce "$githook_dir"/*
    then
        # This project doesn't use spruce in any git hooks
        return 0
    fi

    if spruce --help > /dev/null 2>&1
    then
        # Already have spruce
        return 0
    fi

    if is_mac
    then
        doit brew upgrade spruce || doit brew install spruce
        # Install clang-format if needed
        doit spruce check /dev/null
    elif is_ubuntu
    then
        apt_update
        doit sudo apt-get install -y oblong-spruce
    elif is_win
    then
        echo "TODO: install spruce on windows here; ping platform team if you want it."
    fi
}

didit=false
updated=false

# Git hooks we'll install (if this project has them in the bld subdirectory)
git_hooks="pre-commit"

srcdir="$(cd "$(dirname "$0")" && pwd)"
githook_dir=$srcdir/.git/hooks

dryrun=true
forceupdate=false
while test "$1" != ""
do
    case $1 in
    -f) dryrun=false;;
    -u) forceupdate=true;;
    -h|--help) usage; exit 0;;
    *) usage; exit 1;;
    esac
    shift
done

bs_install_repo_if_needed

if $forceupdate || ! bs_check_obs
then
    bs_install_obs
fi

if $forceupdate || ! bs_check_bau
then
    bs_install_bau
fi

bs_install_hooks_if_needed

bs_install_spruce_if_needed

if $dryrun && $didit
then
    echo "Some action was required.  Re-run as '$0 -f' to actually do the above actions."
    exit 1
fi

if ! git describe > /dev/null
then
    echo "bau prefers to build projects checked out from git, with at least one heavyweight tag like dev-0.0 or rel-0.0 (e.g. 'git tag -a -m dev-0.0 dev-0.0')"
    exit 1
fi

# If this is a debian-ish system like ubuntu, obs uses debuild's convention.
if grep -qi debian /etc/*release 2> /dev/null
then
   BTMP=obj-$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)
else
   BTMP=btmp
fi

cat <<_EOF_
This project is now ready to build.  Quick start:

   $ bau all

_EOF_

if test -f "$srcdir/CMakeLists.txt"
then
    echo "For interactive development, you can then cd $BTMP and run 'ninja' as usual."
    echo ""
fi

cat <<_EOF_
For more help about supported build steps and options for this project
on this platform, see

   https://gitlab.oblong.com/platform/docs/wikis/howto-build-packages

and/or

   $ bau help

and/or

   $ man bau
_EOF_
