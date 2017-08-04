#!/bin/bash

readonly PROGNAME=$(basename "$0")
readonly CACHE_PATH=./.cache

DEBUG_OUTPUT="false"
CONTINUE="false"
EVAL_CONTRACTS="true"
FETCH_CONTRACTS="true"
POROSITY_TIMEOUT="10"
JSON_RPC="false"
TOUCH_CONTRACTS="true"

clear_cache() {
  rm -rf $CACHE_PATH
  echo "Local cache cleared"
}

configure_rpc() {
  echo "FATAL: JSON RPC not yet implemented"
  exit 1
}

eval_contracts() {
  for path in $CACHE_PATH/0x*; do
    address=${path##*/}
    bytecode=$(cat $CACHE_PATH/${address}/bytecode)
    abi=""
    if [ -f $CACHE_PATH/${address}/abi ]; then
      abi=$(cat $CACHE_PATH/${address}/abi)
    fi
    eval_contract $address $bytecode $abi
  done
}

eval_contract() {
  address=$1
  bytecode=$2
  abi=$3

  if [ -z "$bytecode" ]; then
    echo "WARNING: Skipping evaluation of contract at ${address}; no bytecode resolved"
    return -1
  fi

  if [ "$DEBUG_OUTPUT" == "true" ]; then
    echo "DEBUG: Using porosity timeout value of ${POROSITY_TIMEOUT}"

    printf -- "-----------------------------------------------"
    printf -- "Contract ${address}:"
    printf -- "-----------------------------------------------\n"
    printf -- "Bytecode:"
    printf -- "-----------------------------------------------"
    printf -- "${bytecode}"
    printf -- "-----------------------------------------------\n"
    printf -- "ABI:"
    printf -- "-----------------------------------------------"
    printf -- "${abi}"
    printf -- "-----------------------------------------------\n"
  fi

  interface=-1
  disassembler=-1
  decompiler=-1

  if [ -z "$abi" ]; then
    echo "WARNING: Evaluating contract at ${address} without ABI"
    interface=$(timeout --signal KILL $POROSITY_TIMEOUT porosity --code $bytecode --list >> $CACHE_PATH/${address}/interface)
  else
    if [ "$DEBUG_OUTPUT" == "true" ]; then
      echo "DEBUG: Evaluating contract at ${address} with ABI ${abi}"
    fi
    interface=$(timeout --signal KILL $POROSITY_TIMEOUT porosity --abi $abi --code $bytecode --list > $CACHE_PATH/${address}/interface)
  fi

  if [ $? -eq 124 ]; then  # timed out exit status
    echo "WARNING: Evaluation of contract at ${address} has failed; timed out after ${porosity_timeout} seconds"
    return -1
  else
    if [ -z "$abi" ]; then
      disassembler=$(timeout --signal KILL $POROSITY_TIMEOUT porosity --code $bytecode --disassm > $CACHE_PATH/${address}/opcodes)
      decompiler=$(timeout --signal KILL $POROSITY_TIMEOUT porosity --code $bytecode --decompile > $CACHE_PATH/${address}/decompiled_source)
    else
      disassembler=$(timeout --signal KILL $POROSITY_TIMEOUT porosity --abi $abi --code $bytecode--disassm > $CACHE_PATH/${address}/opcodes)
      decompiler=$(timeout --signal KILL $POROSITY_TIMEOUT porosity --abi $abi --code $bytecode --decompile > $CACHE_PATH/${address}/decompiled_source)
    fi

    printf -- "-----------------------------------------------\n"
    printf -- "Finished scanning contract ${address}:\n"
    printf -- "-----------------------------------------------\n\n"
  fi

  return 0
}

fetch_etherscan_contract() {
  address=$1

  echo "Fetching Ethereum contract address from etherscan: ${address}"
  response=$(curl --silent https://etherscan.io/address/${address} | sed 's/<br>/\n&/g' | sed 's/<br\/>/\n&/g' | sed "s/<pre class='wordwrap'(.*)>/\\n&/gI")

  bytecode=$(echo "$response" | grep -iv 'ace.js' \
                              | grep -iv 'js-sourcecopyarea' \
                              | grep -iv 'js-copytextarea' \
                              | grep -iv 'constructor arguments' \
                              | grep -iv 'bzzr://' \
                              | grep -iv '12pc' \
                              | egrep '<pre|verifiedbytecode|15pc' \
                              | sed "s/<div id='verifiedbytecode2'/&\\n/gI" \
                              | awk -v pattern='>(.*)[<\\/pre>|<\\/div>]$' '{ while (match($0, pattern)) { printf("%s\n", substr($0, RSTART + 1, RLENGTH - 7)); $0=substr($0, RSTART + RLENGTH) } }' \
                              | sed 's/<\/div>$//g')

  abi=$(echo "$response" | sed 's/<br>/\n&/g' \
                         | grep '<pre' \
                         | grep -i 'contract abi' \
                         | egrep 'js-copytextarea2|12pc' \
                         | sed 's/&nbsp;<pre/\n&/g' \
                         | grep '<pre' \
                         | awk -v pattern='>(.*)[<\\/pre>|<\\/div>]$' '{ while (match($0, pattern)) { printf("%s\n", substr($0, RSTART + 1, RLENGTH - 7)); $0=substr($0, RSTART + RLENGTH) } }')

  if [ "$DEBUG_OUTPUT" == "true" ]; then
    echo "DEBUG: Retrieved bytecode ${bytecode} for contract at address: ${address}"
    echo "DEBUG: Retrieved abi ${abi} for contract at address: ${address}"
  fi

  echo "${bytecode}" > $CACHE_PATH/${address}/bytecode

  if [ ! -z "$abi" ]; then
    echo "${abi}" > $CACHE_PATH/${address}/abi
  fi
}

fetch_rpc_contract() {
  address=$1
  echo "FATAL: JSON RPC not yet implemented"
  exit 1
}

fetch_contracts() {
  for path in $CACHE_PATH/0x*; do
    address=${path##*/}

    if [ "$JSON_RPC" == "false" ]; then
      fetch_etherscan_contract $address
    elif [ "$JSON_RPC" == "true" ]; then
      fetch_rpc_contract $address
    fi
  done
}

touch_contract() {
  mkdir -p $CACHE_PATH/${address}
}

touch_etherscan_contracts() {
  page=1
  max_page=400
  while [ $page -le $max_page ]
  do
    echo "Fetching Ethereum contract addresses via Etherscan (${page}/${max_page})"
    curl --silent https://etherscan.io/accounts/c/${page} | sed 's/<\/a[^>]*>/\n&/g' | awk -v pattern='>0x(.*)$' '{ while (match($0, pattern)) { printf("%s\n", substr($0, RSTART + 1, RLENGTH)); $0=substr($0, RSTART + RLENGTH) } }' | while read address; do
      touch_contract $address
    done

    page=$((page + 1))
  done
}

touch_rpc_contracts() {
  echo "FATAL: JSON RPC not yet implemented"
  exit 1
}

touch_contracts() {
  echo "Starting scan of Ethereum network for contracts"

  if [ "$JSON_RPC" == "false" ]; then
    touch_etherscan_contracts
  elif [ "$JSON_RPC" == "true" ]; then
    touch_rpc_contracts
  fi
}

cleanup() {
  echo "${PROGNAME} exiting"
}

main() {
  mkdir -p $CACHE_PATH

  trap cleanup EXIT INT TERM

  if [ "$CONTINUE" == "false" ]; then
    touch $CACHE_PATH/.params
    echo "$@" > $CACHE_PATH/.params

    if [ "$TOUCH_CONTRACTS" == "true" ]; then
      touch_contracts
    fi

    if [ "$FETCH_CONTRACTS" == "true" ]; then
      fetch_contracts
    fi

    if [ "$EVAL_CONTRACTS" == "true" ]; then
      eval_contracts
    fi
  else
    params=$(cat $CACHE_PATH/.params)
    echo "WARNING: --continue is not yet implemented; params: ${params}"
  fi
}

usage() {
  cat <<EOF
Usage:
  $PROGNAME [options]
Description:
  Scan the Ethereum network using etherscan.io (or JSON-RPC if --rpc is specified).
  This has only been tested on Ubuntu 16.04.2 LTS.
Options
  -c, --continue              resume scan of Ethereum network (WIP)
  -e, --eval-only             only evaluate previously cached contract addresses-- does not resolve contract addresses
  -f, --fetch-only            only fetches and caches bytecode and ABI for previously touched contract addresses-- does not invoke porosity
  -r, --rpc                   scan Ethereum network using JSON RPC
  -t, --touch-only            only caches contract addresses found by scanning Ethereum network-- does not invoke porosity
  -h, --help                  display this help and exit
  -v, --verbose               enable verbose output (not yet implemented)
  -d, --debug                 debug output
  --clear-cache               clear local contracts cache
  --porosity-timeout SECONDS  number of seconds to wait for porosity to evaluate a single contract (not yet supported; defaults to 10 seconds)
Example:
  $PROGNAME --clear-cache
  $PROGNAME --continue

EOF
  exit 2;
}

OPTS=$(getopt --options cdefhrtv --long clear-cache,continue,debug,eval-only,fetch-only,help,porosity-timeout:,rpc,touch-only,verbose -n "${PROGNAME}" -- "$@")
eval set -- "$OPTS"
while true ; do
  case "$1" in
    --clear-cache) clear_cache ; shift ;;
    # TODO: --porosity-timeout) ; shift ;;
    -t|--touch-only) EVAL_CONTRACTS="false" && FETCH_CONTRACTS="false" ; shift ;;
    -c|--continue) CONTINUE="true" ; shift ;;
    -e|--eval-only) FETCH_CONTRACTS="false" && TOUCH_CONTRACTS="false" ; shift ;;
    -f|--fetch-only) EVAL_CONTRACTS="false" && TOUCH_CONTRACTS="false" ; shift ;;
    -r|--rpc) JSON_RPC="true" && configure_rpc ; shift ;;
    -h|--help) usage ; shift ;;
    -d|--debug) DEBUG_OUTPUT="true" ; shift ;;
    -v|--verbose) echo "WARNING: --verbose not yet implemented" && VERBOSE_OUTPUT="true" ; shift ;;
    --) main ; shift ; break ;;
    *) echo "Invalid usage of ${PROGNAME}; see ${PROGNAME} --help" ; exit 1 ;;
  esac
done
