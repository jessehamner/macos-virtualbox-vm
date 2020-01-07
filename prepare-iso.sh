#!/usr/bin/env bash
#
# This script will create a bootable ISO image from the installer app for:
#
#   - Yosemite (10.10)
#   - El Capitan (10.11)
#   - Sierra (10.12)
#   - High Sierra (10.13)
#   - Mojave (10.14)
#   - Catalina (10.15.1 but no higher)

set -e
volapp="/Volumes/install_app"
volbuild="/Volumes/install_build"

if [ "$(whoami)" == "root" ] ; then
  echo "User is root; this script can continue."
else
  echo "User must be root in order to run -asr-. Exiting now."
  exit
fi


if [[ -e "/tmp/Mojave.sparseimage" ]] ; then 
  rm /tmp/Mojave.sparseimage
fi

if [[ -d "${volapp}" ]] ; then
  hdiutil detach ${volapp}
  hdiutil eject ${volapp}
fi

if [[ -d "${volbuild}" ]] ; then
  hdiutil detach ${volbuild}
  hdiutil eject ${volbuild}
fi

if [[ -d "/Volumes/macOS Base System" ]] ; then
  hdiutil eject "/Volumes/macOS Base System"
fi
#
# createISO
#
# This function creates the ISO image for the user.
# Inputs:  $1 = The name of the installer - located in your Applications folder or in your local folder/PATH.
#          $2 = The Name of the ISO you want created.
function createISO()
{
  if [ $# -eq 2 ] ; then
    local installerAppName=${1}
    local isoName=${2}
    local error=0

    echo Debug: installerAppName = ${installerAppName} , isoName = ${isoName}

    echo
    echo Mount the installer image
    echo -----------------------------------------------------------

    if [ -e "${installerAppName}" ] ; then
      echo $ hdiutil attach "${installerAppName}/Contents/SharedSupport/InstallESD.dmg" -noverify -nobrowse -mountpoint ${volapp}
      hdiutil attach "${installerAppName}/Contents/SharedSupport/InstallESD.dmg" -noverify -nobrowse -mountpoint ${volapp}
      error=$?
    elif [ -e "/Applications/${installerAppName}" ] ; then
      echo $ hdiutil attach "/Applications/${installerAppName}/Contents/SharedSupport/InstallESD.dmg" -noverify -nobrowse -mountpoint ${volapp}
      hdiutil attach "/Applications/${installerAppName}/Contents/SharedSupport/InstallESD.dmg" -noverify -nobrowse -mountpoint ${volapp}
      error=$?
      installerAppName="/Applications/${installerAppName}"
    else
      echo Installer Not found!
      error=1
    fi

    if [ ${error} -ne 0 ] ; then
      echo "Failed to mount the InstallESD.dmg from the installer at ${installerAppName}.  Exiting. (${error})"
      return ${error}
    fi

    echo
    echo Create ${isoName} blank ISO image with a Single Partition - Apple Partition Map
    echo --------------------------------------------------------------------------
    echo $ hdiutil create -o /tmp/${isoName} -size 12g -layout SPUD -fs HFS+J -type SPARSE
    hdiutil create -o /tmp/${isoName} -size 12g -layout SPUD -fs HFS+J -type SPARSE

    echo
    echo Mount the sparse bundle for package addition
    echo --------------------------------------------------------------------------
    echo $ hdiutil attach /tmp/${isoName}.sparseimage -noverify -nobrowse -mountpoint ${volbuild}
    hdiutil attach /tmp/${isoName}.sparseimage -noverify -nobrowse -mountpoint ${volbuild}

    basesystem="/Volumes/OS X Base System"
    # the mount point is no longer "OS X Base System" for Catalina and 
    # Mojave -- now it is "macOS Base System"
    if [ "${isoName}" == "Catalina" ] || [ "${isoName}" == "Mojave" ] ; then
      basesystem="/Volumes/macOS Base System"
    fi

    echo
    echo Restore the Base System into the ${isoName} ISO image
    echo --------------------------------------------------------------------------
    if [ "${isoName}" == "HighSierra" ] || [ "${isoName}" == "Mojave" ] || [ "${isoName}" == "Catalina" ] ; then
      echo $ asr restore -source "${installerAppName}/Contents/SharedSupport/BaseSystem.dmg" -target ${volbuild} -noprompt -noverify -erase
      asr restore -source "${installerAppName}/Contents/SharedSupport/BaseSystem.dmg" -target ${volbuild} -noprompt -noverify -erase  || true
      # Here's where we get the "asr: Couldn't personalize volume /Volumes/macOS Base System - Operation not permitted" error, possibly related to the T2 chip.
      echo "Finished with asr restore command."
    else
      echo "Not running High Sierra, Mojave, or Catalina:"
      echo $ asr restore -source /Volumes/install_app/BaseSystem.dmg -target ${volbuild} -noprompt -noverify -erase
      asr restore -source /Volumes/install_app/BaseSystem.dmg -target ${volbuild} -noprompt -noverify -erase
    fi

    echo
    echo Remove Package link and replace with actual files
    echo --------------------------------------------------------------------------
    if [ "${isoName}" == "HighSierra" ] || [ "${isoName}" == "Mojave" ] || [ "${isoName}" == "Catalina" ] ; then
      echo $ ditto -V /Volumes/install_app/Packages "${basesystem}/System/Installation/"
      ditto -V /Volumes/install_app/Packages "${basesystem}/System/Installation/"
    else
      echo $ rm "${basesystem}/System/Installation/Packages"
      rm "${basesystem}/System/Installation/Packages"
      echo $ cp -rp /Volumes/install_app/Packages "${basesystem}/System/Installation/"
      cp -rp /Volumes/install_app/Packages "${basesystem}/System/Installation/"
    fi

    echo
    echo Copy macOS ${isoName} installer dependencies
    echo --------------------------------------------------------------------------
    if [ "${isoName}" == "HighSierra" ] || [ "${isoName}" == "Mojave" ] || [ "${isoName}" == "Catalina" ] ; then
      echo $ ditto -V "${installerAppName}/Contents/SharedSupport/BaseSystem.chunklist" "${basesystem}/BaseSystem.chunklist"
      ditto -V "${installerAppName}/Contents/SharedSupport/BaseSystem.chunklist" "${basesystem}/BaseSystem.chunklist"
      echo $ ditto -V "${installerAppName}/Contents/SharedSupport/BaseSystem.dmg" "${basesystem}/BaseSystem.dmg"
      ditto -V "${installerAppName}/Contents/SharedSupport/BaseSystem.dmg" "${basesystem}/BaseSystem.dmg"
    else
      echo $ cp -rp /Volumes/install_app/BaseSystem.chunklist "${basesystem}/BaseSystem.chunklist"
      cp -rp /Volumes/install_app/BaseSystem.chunklist "${basesystem}/BaseSystem.chunklist"
      echo $ cp -rp /Volumes/install_app/BaseSystem.dmg "${basesystem}/BaseSystem.dmg"
      cp -rp /Volumes/install_app/BaseSystem.dmg "${basesystem}/BaseSystem.dmg"
    fi

    echo
    echo Unmount the installer image
    echo --------------------------------------------------------------------------
    echo $ hdiutil detach ${volapp}
    hdiutil detach -force ${volapp}

    echo
    echo Unmount the sparse bundle
    echo --------------------------------------------------------------------------
    sleep 1
    echo $ hdiutil detach "${basesystem}"
    hdiutil detach -force "${basesystem}"

    echo
    echo Resize the partition in the sparse bundle to remove any free space
    echo --------------------------------------------------------------------------
    sleep 1
    echo $ hdiutil resize -size `hdiutil resize -limits /tmp/${isoName}.sparseimage | tail -n 1 | awk '{ print $1 }'`b /tmp/${isoName}.sparseimage
    hdiutil resize -size `hdiutil resize -limits /tmp/${isoName}.sparseimage | tail -n 1 | awk '{ print $1 }'`b /tmp/${isoName}.sparseimage

    echo
    echo Convert the ${isoName} sparse bundle to ISO/CD master
    echo --------------------------------------------------------------------------
    sleep 1
    echo $ hdiutil convert /tmp/${isoName}.sparseimage -format UDTO -o /tmp/${isoName}
    hdiutil convert /tmp/${isoName}.sparseimage -format UDTO -o /tmp/${isoName}

    echo
    echo Remove the sparse bundle
    echo --------------------------------------------------------------------------
    sleep 1
    echo $ rm /tmp/${isoName}.sparseimage
    rm /tmp/${isoName}.sparseimage

    echo
    echo Rename the ISO and move it to the desktop
    echo --------------------------------------------------------------------------
    echo $ mv /tmp/${isoName}.cdr ~/Desktop/${isoName}.iso
    mv /tmp/${isoName}.cdr ~/Desktop/${isoName}.iso
  fi
}

#
# installerExists
#
# Returns 0 if the installer was found either locally or in the /Applications directory.  1 if not.
#
function installerExists()
{
  local installerAppName=$1
  local result=1
  if [ -e "${installerAppName}" ] ; then
    result=0
  elif [ -e "/Applications/${installerAppName}" ] ; then
    result=0
  fi
  return ${result}
}

#
# Main script code
#
# Eject installer disk in case it was opened after download from App Store
for disk in $(hdiutil info | grep /dev/disk | grep partition | cut -f 1); do
  hdiutil detach -force ${disk}
done

# See if we can find an eligible installer.
# If successful, then create the iso file from the installer.

#installerExists "Install macOS Catalina.app"
#result=$?
#if [ ${result} -eq 0 ] ; then
#  createISO "Install macOS Catalina.app" "Catalina"
#else
#  echo "Could not find installer for Catalina (10.15)"
#fi

installerExists "Install macOS Mojave.app"
result=$?
if [ ${result} -eq 0 ] ; then
  createISO "Install macOS Mojave.app" "Mojave"
else
  installerExists "Install macOS High Sierra.app"
  result=$?
  if [ ${result} -eq 0 ] ; then
    createISO "Install macOS High Sierra.app" "HighSierra"
  else
    installerExists "Install macOS Sierra.app"
    result=$?
    if [ ${result} -eq 0 ] ; then
      createISO "Install macOS Sierra.app" "Sierra"
    else
      installerExists "Install OS X El Capitan.app"
      result=$?
      if [ ${result} -eq 0 ] ; then
        createISO "Install OS X El Capitan.app" "ElCapitan"
      else
        installerExists "Install OS X Yosemite.app"
        result=$?
        if [ ${result} -eq 0 ] ; then
          createISO "Install OS X Yosemite.app" "Yosemite"
        else
          echo "Could not find installer for Yosemite (10.10), El Capitan (10.11), Sierra (10.12), High Sierra (10.13) or Mojave (10.14)."
        fi
      fi
    fi
  fi
fi
