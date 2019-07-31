#!/bin/bash -
#title           Safebrowse scan for WHM/cpanel servers
#description     This script will locally run a list of domains against Google's Safebrowsing API (v4).
#author		       Austin B <austin@codebeard.com>
#date            20190731
#version         0.1
#bash_version    version 4.2.46(2)-release
#license         GNU General Public License
#requirements    GO version 1.10+ & sblookup - https://github.com/google/safebrowsing
#==============================================================================

# A POSIX variable
OPTIND=1 # Reset in case getopts has been used previously in the shell.

# API Key from https://console.cloud.google.com/apis/credentials passed as -k option
API_KEY=""

# Default path to the safebrowsing database.  This is auto-created and auto-updated by sblookup
DB_PATH=`eval echo "~/safebrowsing.db"`

# Default path to the sblookup binary
SBLOOKUP_PATH=`eval echo "~/go/bin/sblookup"`

# Rather than relying on the sblookup exit code we grep for the following string for unsafe urls
UNSAFE_URL="Unsafe URL:"

# Check to make sure we have a database file. Saves on api calls.
if [[ ! -f "$DB_PATH" ]]; then
  echo "Browsesafe database file missing at $DB_PATH.  Creating..."
  `touch $DB_PATH`
fi

# Current verion of this script
VERSION=0.1

HELP_TEXT="
Usage: $(basename "$0") [-h -i] [-f d s k]

About:
This script uses Google's sblookup to check if any domains on this WHM/cPanel server are on the safebrowsing list, as in they have been flagged for malware and have probably been compromised.  You can read more on how to install and use sblookup at https://github.com/google/safebrowsing

Options:
    Required:
    -k [api_key]            You must get an api key from Google at https://console.cloud.google.com/apis/credentials that can access Google's \"Safe Browsing API\"

    Optional:
    -h                      Show this help message
    -i                      Show GO and sblookup installation information (CentOS 7)
    -f                      Only return sites that fail, ignore clean sites
    -s [/path/to/sblookup]  The full path to sblookup if it does not exist in this users home directory. Default $SBLOOKUP_PATH
    -d                      Show debug messages from sblookup output.  Warning this option will make the output very noisy
"

INSTALL_TEXT="
CentOS 7 Installation Instructions:

# Install GO latest (1.12.x):
# This will install GO system wide
# Note: this is a 3rd party repository that is not maintained by CentOS
rpm --import https://mirror.go-repo.io/centos/RPM-GPG-KEY-GO-REPO
curl -s https://mirror.go-repo.io/centos/go-repo.repo | tee /etc/yum.repos.d/go-repo.repo
sudo yum install -y golang

# Install safebrowsing and sblookup:
# This will install safebrowsing and the sblookup command into the user that runs the command (i.e. /root/go/...)
go get github.com/google/safebrowsing
go get github.com/google/safebrowsing/cmd/sblookup
"

# Option defaults
DEBUG=0
QUIET=0

# Handle options
while getopts ":hifds:k:" opt; do
  case $opt in
    d)
      echo "Will dump command output as well as normal output!"
      DEBUG=1
      ;;
    f)
      echo "Will only output unsafe url results!"
      QUIET=1
      ;;
    s)
      SBLOOKUP_PATH=$OPTARG
      echo "Set sblookup binary to '$SBLOOKUP_PATH'!"
      ;;
    k)
      API_KEY=$OPTARG
      echo "Google API Key to '$API_KEY'!"
      ;;
    h)
      echo "$HELP_TEXT"
      exit
      ;;
    i)
      echo "$INSTALL_TEXT"
      exit
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Use -h for help." >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# API key defined?
if [[ -z "$API_KEY" ]]; then
  echo "API key is not set.  You must pass an API key using the -k option"
  exit 1
fi

# Access to sblookup binary?
if [[ ! -f "$SBLOOKUP_PATH" ]]; then
  echo "Unable to locate sblookup binary at '$SBLOOKUP_PATH'. You must pass the full path to the sblookup binary using the -s option. See install instructions using the -i option."
  exit 1
fi

shift $((OPTIND-1))

echo "Using sblookup at '$SBLOOKUP_PATH' with safebrowsing database '$DB_PATH'!"

while read domain user; do
  # Trim the extra : off the end of the domain
  domain=${domain::-1}

  # Check if $domain is really a domain.  Does it contain at least one "."?
  if [ -z "${domain//[^.]/}" ]; then
    if [[ $QUIET -eq "0" ]]; then
      echo "Skipping the domain '$domain' as it is probably invalid."
    fi
    continue
  fi

  if [[ $QUIET -eq "0" ]]; then
    echo "Checking $domain..."
  fi

  # Offload to sblookup and get the result
  result=`echo "$domain" | $SBLOOKUP_PATH -apikey $API_KEY -db $DB_PATH 2>&1`

  # Strip some command output info
  if [[ $DEBUG -eq "0" ]]; then
    result=`echo "$result" | grep -v "safebrowsing: *"`
  fi

  # Did we fail?
  failed=`echo "$result" | grep -w "$UNSAFE_URL"`

  # We failed.  Do something I suppose...
  if [[ -n "$failed" ]]; then
    echo "$result"
  elif [[ $QUIET -eq "0" ]]; then
    echo "$result"
    echo "URL OK!"
  fi

  #echo "$result"
done < /etc/userdomains

echo "Finished"
