#!/usr/bin/env bash
# 
# Attempts to install required binaries and configure chrome/chromium via Network Security Services. It 
# installs the PKCS11 module and DOD certificates to access .mil sites. This particular script makes use
# of the onepin-opensc-pkcs11.so library for CAC module setup, however, if you prefer a different PKCS11 
# library such as coolkey, you will need to manually adjust for that.
###

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
NSSDB="$HOME/.pki/nssdb"

SUDO=""
if [[ $EUID != 0 ]]; then
  SUDO="sudo"
fi

# source dist release info
source /etc/os-release

help_menu() {
  echo -e "bash ./$(basename "$0") [-a] [-c] [-r]"
  echo -ne "You must select ONE option. In most cases, you will want the -a option if this is a first run to install all the things. "
  echo -e "This will not work with chrome/chromium installed via snap/flatpak (ref. https://github.com/flatpak/flatpak/issues/4723).\n"
  echo -e "\t-a installs all requirements and configurations."
  echo -e "\t-c install CAC module only."
  echo -e "\t-r remove CAC module only."
  echo ""
  exit 0
}

if [[ $# -ne 1 ]]; then
  help_menu
fi

# check if chrome is running; just say it, don't kill it
isrunning=$(pgrep -u $USER chrome)
if [[ ! -z $isrunning ]]; then
  echo -e "${RED}Please close down chrome/chromium and re-run the script.${NC}"
  exit 1
fi

install_binaries() {
  echo -e "${GREEN}Installing required binaries...${NC}"
  case $ID_LIKE in
    *rhel*)
      $SUDO dnf install nss-tools pcsc-lite perl-pcsc pcsc-tools ccid opensc -y
      ;;
    *debian*)
      $SUDO apt install libnss3-tools pcsc-tools libpcsc-perl libccid opensc -y
      ;;
    *) 
      echo -e "${RED}Linux Distribution not currently supported [$ID_LIKE].${NC}" && exit 1
      ;;
  esac
}

nssdb_exists() {
  if [[ ! -d "$NSSDB" ]]; then
    return $(false)
  fi
  return $(true)
}

nssdb_create() {
  if [[ ! nssdb_exists ]]; then
    echo -e "${GREEN}Creating new nssdb...${NC}"
    certutil -d sql:$NSSDB -N --empty-password
  else 
    backup="${NSSDB}.BKUP.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}Looks like you already have a nssdb setup. Backing up to ${backup}...${NC}"
    cp -r $NSSDB $backup
  fi
}

nssdb_removecerts() {
  certs=$(certutil -L -d sql:$NSSDB | grep -i dod | awk '{print $1}')
  if [[ ! -z $certs ]]; then
    echo -e "${RED}Deleting existing DoD certificates:${NC}"
    for cert in $certs;do 
      echo -e "\t${RED}$cert${NC}"
      certutil -D -d sql:$NSSDB -n "$cert"
    done
  fi
}

add_cacmodule() {
  nothing=$(modutil -dbdir sql:$NSSDB -list "CAC Module" 2>/dev/null)
  added=$?
  if [[ $added != 0 && $added != 32 ]]; then 
    echo -e "${YELLOW}Adding PKCS11 module to nssdb${NC}"
    lib="$(find /usr -name "onepin-opensc-pkcs11.so" 2>/dev/null | head -1)"
    if [[ -z $lib ]]; then
      echo -e "${RED}Required PKCS11 library not found. Unable to add CAC module.${NC}"
      exit 1
    else
      echo "" | modutil -dbdir sql:$NSSDB -add "CAC Module" -force -libfile $lib
    fi
  fi
}

remove_cacmodule() {
  nothing=$(modutil -dbdir sql:$NSSDB -list "CAC Module" 2>/dev/null)
  added=$?
  if [[ $added == 0 || $added == 32 ]]; then
    echo -e "${YELLOW}Removing PKCS11 module from nssdb${NC}"
    modutil -dbdir sql:$NSSDB -force -delete "CAC Module"
  fi
}

download_certs() {
  ROOT_CERTS_URL="https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip"
  CA_CERTS_URL="https://crl.gds.disa.mil"
  mkdir -pv certs
  echo -e "${GREEN}Downloading CA certificates...${NC}"
  wget -q "$ROOT_CERTS_URL" -O ca-certs.zip
  unzip -d certs ca-certs.zip
  # move p7b files to root of certs directory
  for f in $(find certs -name "*.p7b" -type f); do
    mv $f certs/ 
  done

  echo -e "${GREEN}Getting latest list of current CA Certificates...${NC}"
  cacerts=$(curl -sL "$CA_CERTS_URL" | grep -E "<option.*(DOD SW|DOD EMAIL|DOD ID)" | grep -Po '(?<=\>)DOD.*(?=\<)' | sed 's/ /_/g')

  echo -e "${GREEN}Downloading DOD EMAIL, SW, and ID CA Certificates...${NC}"
  for cacert in $cacerts;do
    fname="${cacert}.crt"
    uri="$(echo $cacert | sed 's/_/+/g')"
    echo -e "\t${GREEN}${fname}${NC}"
    wget -q "${CA_CERTS_URL}/getsign?${uri}" -O "certs/${fname}"
  done
}

install_certs() {
  echo -e "${GREEN}Installing certificates into NSSDB...${NC}"
  for path in $(ls certs/*.{p7b,crt}); do 
    name=$(basename $path | sed 's/\.crt//g')
    echo -e "${GREEN}Adding $name${NC}"
    certutil -d sql:$NSSDB -A -t TC -n $name -i $path    
  done
}

while getopts :acr opt; do
  case ${opt} in
    a)
      install_binaries
      nssdb_create
      nssdb_removecerts
      add_cacmodule
      download_certs
      install_certs
      # list what we have loaded
      certutil -d sql:$NSSDB -L
      echo "Removing downloaded content."
      rm -rf certs ca-certs.zip
      ;;
    c)
      install_binaries
      # add module for reader - make sure chrom(e|ium) instances are closed
      # Checking to see if the PKCS11 module has already been added to nssdb 
      add_cacmodule
      ;;
    r)
      install_binaries
      remove_cacmodule
      ;;
    *)
      help_menu
      ;;
  esac
done

