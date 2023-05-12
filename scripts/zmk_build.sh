#!/usr/bin/env bash

# Parse input arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        # needed when user isn't in docker group
        -s|--su)
            SUDO="sudo"
            ;;

        -l|--local)
            RUNWITH_DOCKER="false"
            ;;

        -c|--clear-cache)
            CLEAR_CACHE="true"
            ;;

        # comma or space separated list of boards (use quotes if space separated)
        # if ommitted, will compile list of boards in build.yaml
        -b|--board)
            BOARDS="$2"
            shift
            ;;

        -v|--version)
            ZEPHYR_VERSION="$2"
            shift
            ;;

        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift
            ;;

        --log-dir)
            LOG_DIR="$2"
            shift
            ;;

        --host-config-dir)
            HOST_CONFIG_DIR="$2"
            shift
            ;;

        --host-zmk-dir)
            HOST_ZMK_DIR="$2"
            shift
            ;;

        --docker-config-dir)
            DOCKER_CONFIG_DIR="$2"
            shift
            ;;

        --docker-zmk-dir)
            DOCKER_ZMK_DIR="$2"
            shift
            ;;

        --)
            WEST_OPTS="${@:2}"
            break
            ;;

        *)
            echo "Unknown option $1"
            exit 1
            ;;

    esac
    shift
done

# Set defaults
[[ -z $ZEPHYR_VERSION ]] && ZEPHYR_VERSION="3.2"
[[ -z $RUNWITH_DOCKER ]] && RUNWITH_DOCKER="true"

[[ -z $OUTPUT_DIR ]] && OUTPUT_DIR="$WINHOME/Downloads"
[[ -z $LOG_DIR ]] && LOG_DIR="/tmp"

[[ -z $HOST_ZMK_DIR ]] && HOST_ZMK_DIR="$HOME/zmk"
[[ -z $HOST_CONFIG_DIR ]] && HOST_CONFIG_DIR="$HOME/zmk-config"

[[ -z $DOCKER_ZMK_DIR ]] && DOCKER_ZMK_DIR="/workspace/zmk"
[[ -z $DOCKER_CONFIG_DIR ]] && DOCKER_CONFIG_DIR="/workspace/zmk-config"

[[ -z $BOARDS ]] && BOARDS="$(grep '^[[:space:]]*\-[[:space:]]*board:' $HOST_CONFIG_DIR/build.yaml | sed 's/^.*: *//')"

[[ -z $CLEAR_CACHE ]] && CLEAR_CACHE="false"

DOCKER_IMG="zmkfirmware/zmk-dev-arm:$ZEPHYR_VERSION"
DOCKER_BIN="$SUDO podman"

# +-------------------------+
# | AUTOMATE CONFIG OPTIONS |
# +-------------------------+

cd "$HOST_CONFIG_DIR"

if [[ -f config/combos.dtsi ]]
    # update maximum combos per key
    then
    count=$( \
        tail -n +10 config/combos.dtsi | \
        grep -Eo '[LR][TMBH][0-9]' | \
        sort | uniq -c | sort -nr | \
        awk 'NR==1{print $1}' \
    )
    sed -Ei "/CONFIG_ZMK_COMBO_MAX_COMBOS_PER_KEY/s/=.+/=$count/" config/*.conf
    echo "Setting MAX_COMBOS_PER_KEY to $count"

    # update maximum keys per combo
    count=$( \
        tail -n +10 config/combos.dtsi | \
        grep -o -n '[LR][TMBH][0-9]' | \
        cut -d : -f 1 | uniq -c | sort -nr | \
        awk 'NR==1{print $1}' \
    )
    sed -Ei "/CONFIG_ZMK_COMBO_MAX_KEYS_PER_COMBO/s/=.+/=$count/" config/*.conf
    echo "Setting MAX_KEYS_PER_COMBO to $count"
fi

# +--------------------+
# | BUILD THE FIRMWARE |
# +--------------------+

if [[ $RUNWITH_DOCKER = true ]]
then
    echo "Build mode: docker"
    DOCKER_CMD="$DOCKER_BIN run --name zmk-$ZEPHYR_VERSION --rm \
        --mount type=bind,source=$HOST_ZMK_DIR,target=$DOCKER_ZMK_DIR \
        --mount type=bind,source=$HOST_CONFIG_DIR,target=$DOCKER_CONFIG_DIR,readonly \
        --mount type=volume,source=zmk-root-user-$ZEPHYR_VERSION,target=/root \
        --mount type=volume,source=zmk-zephyr-$ZEPHYR_VERSION,target=$DOCKER_ZMK_DIR/zephyr \
        --mount type=volume,source=zmk-zephyr-modules-$ZEPHYR_VERSION,target=$DOCKER_ZMK_DIR/modules \
        --mount type=volume,source=zmk-zephyr-tools-$ZEPHYR_VERSION,target=$DOCKER_ZMK_DIR/tools"

    # Reset volumes
    if [[ $CLEAR_CACHE = true ]]
    then
        $DOCKER_BIN volume rm $($DOCKER_BIN volume ls -q | grep "^zmk-.*-$ZEPHYR_VERSION$")
    fi

    # Update west if needed
    OLD_WEST="/root/west.yml.old"
    $DOCKER_CMD -w "$DOCKER_ZMK_DIR" "$DOCKER_IMG" /bin/bash -c " \
        if [[ ! -f .west/config ]]; then west init -l app/; fi \
        && if [[ -f $OLD_WEST ]]; then md5_old=\$(md5sum $OLD_WEST | cut -d' ' -f1); fi \
        && [[ \$md5_old != \$(md5sum app/west.yml | cut -d' ' -f1) ]] \
        && west update \
        && cp app/west.yml $OLD_WEST"

    # Build parameters
    DOCKER_PREFIX="$DOCKER_CMD -w $DOCKER_ZMK_DIR/app $DOCKER_IMG"
    SUFFIX="${ZEPHYR_VERSION}_docker"
    CONFIG_DIR="$DOCKER_CONFIG_DIR/config"

else
    echo "Build mode: local"
    SUFFIX="${ZEPHYR_VERSION}"
    CONFIG_DIR="$HOST_CONFIG_DIR/config"
    cd "$HOST_ZMK_DIR/app"
fi

# usage: compile_board board
compile_board () {
    echo -en "\n$(tput setaf 2)Building $1... $(tput sgr0)"
    BUILD_DIR="${1}_$SUFFIX"
    LOGFILE="$LOG_DIR/zmk_build_$1.log"
    $DOCKER_PREFIX west build -d "build/$BUILD_DIR" -b $1 $WEST_OPTS \
        -- -DZMK_CONFIG="$CONFIG_DIR" -Wno-dev > "$LOGFILE" 2>&1
    if [[ $? -eq 0 ]]
    then
        # echo "$(tput setaf 4)Success: $1 done$(tput sgr0)"
        echo "$(tput setaf 2)done$(tput sgr0)"
        echo "Build log saved to \"$LOGFILE\"."
        if [[ -f $HOST_ZMK_DIR/app/build/$BUILD_DIR/zephyr/zmk.uf2 ]]
        then
            TYPE="uf2"
        else
            TYPE="bin"
        fi
        OUTPUT="$OUTPUT_DIR/$1-zmk.$TYPE"
        [[ -f $OUTPUT ]] && [[ ! -L $OUTPUT ]] && mv "$OUTPUT" "$OUTPUT.bak"
        cp "$HOST_ZMK_DIR/app/build/$BUILD_DIR/zephyr/zmk.$TYPE" "$OUTPUT"
    else
        echo
        cat "$LOGFILE"
        echo "$(tput setaf 1)Error: $1 failed$(tput sgr0)"
    fi
}

cd "$HOST_ZMK_DIR/app"
for board in $(echo $BOARDS | sed 's/,/ /g')
do
    compile_board $board
done

