# source this file from your bash/zsh

echo -n "Username: "
read LTSB_USERNAME

echo -n "Password: "
read -s LTSB_PASSWD
echo

echo -n "Memorable info: "
read -s LTSB_MEMORABLE
echo

export LTSB_USERNAME LTSB_PASSWD LTSB_MEMORABLE
