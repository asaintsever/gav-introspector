#!/bin/bash

set -e
set -u

GAVSPECTOR_HOME="$HOME/.gavspector"
GAVSPECTOR_HASH_DIR="$GAVSPECTOR_HOME/hash"
GAVSPECTOR_TMP_DIR="/tmp/gavspector"
JAVA_ARTIFACTS_ROOT_DIR=""
PURGE_HASH_CACHE="N"
FAIL_FAST="N"
UNRESOLVED_EXT=""

gavspector() {
  parse_args "$@"
  check_prerequisites
  extract_gav
}

extract_gav() {
  mkdir -p "$GAVSPECTOR_TMP_DIR"
  mkdir -p "$GAVSPECTOR_HASH_DIR"

  if [ "$PURGE_HASH_CACHE" = "Y" ];then
    rm -rf "$GAVSPECTOR_HASH_DIR"
    mkdir -p "$GAVSPECTOR_HASH_DIR"
  fi

  cd "$JAVA_ARTIFACTS_ROOT_DIR"

  for file in $(find -name "*.jar" | sed "s/^\.\///g"); do
    ISFAIL=false; GROUPID=""; ARTIFACTID=""; VERSION=""; GAVFILE=""; MVNSEARCHRESP=""
    HASH=$(shasum -a 1 $file | cut -d ' ' -f 1)

    # Hash lookup in local cache
    if [ -f "$GAVSPECTOR_HASH_DIR/$HASH" ];then
      GAVFILE=$(cat "$GAVSPECTOR_HASH_DIR/$HASH")
    else
      # Not found: look in artifact's META-INF
      unzip -p - $file META-INF/maven/*/*/pom.properties 2>/dev/null > "$GAVSPECTOR_TMP_DIR/gav.tmp" || true

      GROUPID=$(cat "$GAVSPECTOR_TMP_DIR/gav.tmp" | grep "^groupId" | cut -d '=' -f 2 | sed -e 's/[[:space:]]*$//')

      # If groupId not found or more than one (may be the case if several folders under META-INF/maven/): no need to lose time extracting artifactId and version
      if [ "$GROUPID" != "" ] && [ "$(echo $GROUPID | wc -w)" -eq 1 ];then
        ARTIFACTID=$(cat "$GAVSPECTOR_TMP_DIR/gav.tmp" | grep "^artifactId" | cut -d '=' -f 2 | sed -e 's/[[:space:]]*$//')
        VERSION=$(cat "$GAVSPECTOR_TMP_DIR/gav.tmp" | grep "^version" | cut -d '=' -f 2 | sed -e 's/[[:space:]]*$//')

        # Make sure file begins with "<ARTIFACT ID>-<VERSION>" (it happens Maven metadata do not always reflect the artifact's real identity)
        # Do not perform strict match here as some artifacts may have '-<CLASSIFIER>' after the version
        if [[ $file = "$ARTIFACTID-$VERSION"* ]];then
            GAVFILE=$GROUPID.$file
            # Save GAV in file using hash as filename: build local cache
            echo "$GAVFILE" > "$GAVSPECTOR_HASH_DIR/$HASH"
        fi
      fi

      if [ "$GAVFILE" = "" ];then
        # Not found: Hash lookup using Maven Search API (set 'rows' param >1 to detect resolution issues)
        if MVNSEARCHRESP=$(curl \
                            --connect-timeout 10 \
                            --retry 2 \
                            --retry-delay 1 \
                            -k -s \
                            "https://search.maven.org/solrsearch/select?q=1:%22$HASH%22&rows=5&wt=json" \
                            2>&1);then
          MVNSEARCHRESP_NUM=$(echo "$MVNSEARCHRESP" | jq '.response.docs | length')

          if [ "$MVNSEARCHRESP_NUM" = "0" ];then
              echo "--- Fail to retrieve GAV for $file from Maven Search service"; echo "$MVNSEARCHRESP"; GAVFILE="$file$UNRESOLVED_EXT"; ISFAIL=true
          else
            # Loop and look for entry with artifactId matching $file
            for (( index=0; index<$(($MVNSEARCHRESP_NUM)); index++ )); do
                ARTIFACTID=$(echo $MVNSEARCHRESP | jq -r --argjson resp_indx $index '.response.docs[$resp_indx].a')
                VERSION=$(echo $MVNSEARCHRESP | jq -r --argjson resp_indx $index '.response.docs[$resp_indx].v')

                # Make sure file begins with "<ARTIFACT ID>-<VERSION>"
                # Do not perform strict match here as some artifacts may have '-<CLASSIFIER>' after the version
                if [[ $file = "$ARTIFACTID-$VERSION"* ]];then
                    GROUPID=$(echo $MVNSEARCHRESP | jq -r --argjson resp_indx $index '.response.docs[$resp_indx].g')
                    GAVFILE=$GROUPID.$file
                    break
                fi
            done

            if [ "$GAVFILE" = "" ];then
                echo "Fail to resolve GAV for $file using Maven Search service"; echo "$MVNSEARCHRESP"; GAVFILE="$file$UNRESOLVED_EXT"; ISFAIL=true
            else
              # Save GAV in file using hash as filename: build local cache
              echo "$GAVFILE" > "$GAVSPECTOR_HASH_DIR/$HASH"
            fi
          fi
        else
          echo "--- Fail to retrieve GAV for $file from Maven Search service"; echo "$MVNSEARCHRESP"; GAVFILE="$file$UNRESOLVED_EXT"; ISFAIL=true
        fi
      fi
    fi

    if [ "$file" != "$GAVFILE" ];then
      echo "$file --> $GAVFILE"
      mv $file $GAVFILE
    fi

    if [ "$FAIL_FAST" = "Y" ] && $ISFAIL;then
      exit 1
    fi
  done
}

check_prerequisites() {
  unzip -hh > /dev/null 2>&1 && RES=$? || RES=$?
  if [ $RES -ne 0 ];then
    echo "unzip not installed or not in your path"; exit 1
  fi

  curl --version > /dev/null 2>&1 && RES=$? || RES=$?
  if [ $RES -ne 0 ];then
    echo "curl not installed or not in your path"; exit 1
  fi

  jq --version > /dev/null 2>&1 && RES=$? || RES=$?
  if [ $RES -ne 0 ];then
    echo "jq not installed or not in your path"; exit 1
  fi
}

parse_args() {
  while [ $# -gt 0 ]
  do
    case $1 in
      --fail-fast)
        FAIL_FAST="Y"
        ;;
      --unresolved-ext)
        UNRESOLVED_EXT="$2"
        shift
        ;;
      --purge-cache)
        PURGE_HASH_CACHE="Y"
        ;;
      *)
        JAVA_ARTIFACTS_ROOT_DIR="$1"
        ;;
    esac
    shift
  done

  if [ ! -d "$JAVA_ARTIFACTS_ROOT_DIR" ];then
    echo "Error: path to Java artifacts not specified or invalid"; exit 1
  fi
}

gavspector "$@"
