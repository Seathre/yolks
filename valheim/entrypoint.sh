#!/bin/bash
cd /home/container

# Make internal Docker IP address available to processes.
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

## just in case someone removed the defaults.
if [ "${STEAM_USER}" == "" ]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
else
    echo -e "user set to ${STEAM_USER}"
fi

## if auto_update is not set or to 1 update
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    # Update Source Server
    if [ ! -z ${SRCDS_APPID} ]; then
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) $( [[ -z ${VALIDATE} ]] || printf %s "validate" ) +quit
    else
        echo -e "No appid set. Starting Server"
    fi
else
    echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

# Setup NSS Wrapper for use ($NSS_WRAPPER_PASSWD and $NSS_WRAPPER_GROUP have been set by the Dockerfile)
export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
envsubst < /passwd.template > ${NSS_WRAPPER_PASSWD}

export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libnss_wrapper.so

# Valheim Thunderstore Mod Auto Updater
mod_list="/home/container/BepInEx/mods.txt"
tmp_dir="/home/container/.tmp"
bepinex="/home/container/BepInEx"
plugins="$bepinex/plugins"

echo " "
echo "-------------------------------------------------------"
echo "---                   ---------------------------------"
echo "---   Updating Mods   ---------------------------------"
echo "---                   ---------------------------------"
echo "-------------------------------------------------------"
echo " "

if [ "${MODS_AUTO}" == "0" ]; then
	echo "Mods Auto Update set to false; Skipping..."
else
	if  [ -s "$mod_list" ]; then
		echo "Mod List found: $mod_list"
		# For each URL in the mods.txt, get the author_name and mod_name.
		while read -r url; do
		# Get the values from the URL
		author_name=$(echo "$url" | cut -d/ -f5)
		mod_name=$(echo "$url" | cut -d/ -f6)

		# Query the Thunderstore API for download_url and version_number
		api_response=$(curl -s "https://valheim.thunderstore.io/api/experimental/package/$author_name/$mod_name/")
		download_url=$(echo "$api_response" | jq -r '.latest.download_url')
		mod_version=$(echo "$api_response" | jq -r '.latest.version_number')

		# Create directories
		download_dir="$tmp_dir/$author_name"
		extract_dir="$download_dir/$mod_name"
		zip="$download_dir/$mod_name-$mod_version.zip"
		mkdir -p "$download_dir"
		mkdir -p "$extract_dir"
		mkdir -p "$plugins/$author_name/$mod_name"

		# Download the mod zip and extract
		curl -L -o "$zip" "$download_url"
		unzip -o "$zip" -d "$extract_dir"
		
		# HookGenPatcher should sync to the respective Bepinex directories
		if [ "$mod_name" == "HookGenPatcher" ]; then
			for directory in config patchers; do
				rsync -r "$extract_dir/$directory/" "$bepinex/$directory/"
				# Deleting any .dll files here to avoid problems later
				find "$extract_dir/$directory/" -name "*.dll" -delete
			done
		else
			# Jotunn's zip contains a plugins directory, so sync contents to the appropriate directory
			if [ "$mod_name" == "Jotunn" ]; then
				rsync -r "$extract_dir/plugins/" "$bepinex/plugins/$author_name/$mod_name"
				# Deleting any .dll files here to avoid problems later
				find "$extract_dir" -name "*.dll" -delete
			else
				# Search the extract directory for .dll files and move them to the plugins directory in BepInEx
				find "$extract_dir" -name "*.dll" -exec mv -f {} "$bepinex/plugins/$author_name/$mod_name" \;
			fi
		fi
		done < "$mod_list"
	else
		echo "Mod List file is empty; Skipping..."
	fi
fi

echo " "
echo "-------------------------------------------------------"
echo "---                      ------------------------------"
echo "--- Mods Update Complete ------------------------------"
echo "---                      ------------------------------"
echo "-------------------------------------------------------"
echo " "
# End Mod Update

# Replace Startup Variables
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval ${MODIFIED_STARTUP}

