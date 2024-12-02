wget https://raw.githubusercontent.com/Yuhi-Sato/isucon-ready/main/Makefile
if [ ! -e /home/isucon/env.sh ]; then
  # ファイルが存在しない場合、作成
  touch /home/isucon/env.sh
  echo "/home/isucon/env.sh を作成しました。"
else
  # ファイルが存在する場合、何もしない
  echo "/home/isucon/env.sh は既に存在します。"
fi
make setup
make set-as-s1
make get-conf
cat ~/.ssh/id_ed25519.pub
