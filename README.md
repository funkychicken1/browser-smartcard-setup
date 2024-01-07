## Browser smartcard setup for Chrome/Chromium on Linux

### Description
For initial installs, simple run the script utilizing the -a option to install all components (required packages, dod certificates, and smartcard PKCS11 module).

### Usage
```
bash ./browser-smartcard-setup.sh [-a] [-c] [-r]
You must select ONE option. In most cases, you will want the -a option if this is a first run to install all the things. This will not work with chrome/chromium installed via snap/flatpak (https://github.com/flatpak/flatpak/issues/4723). 

	 -a installs all requirements and configurations.
	 -c install CAC module only.
	 -r remove CAC module only.

```

- The -c and -r options come in handy if for some reason your nssdb becomes corrupted or for troubleshooting.