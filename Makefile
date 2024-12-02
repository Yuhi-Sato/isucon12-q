ifneq ("$(wildcard /home/isucon/env.sh)","")
    include /home/isucon/env.sh
endif

# SERVER_ID: env.sh内で定義

# 問題によって変わる変数
USER:=isucon
BIN_NAME:=app
BUILD_DIR:=./go
SERVICE_NAME:=isu-go

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx

DB_SLOW_LOG:=/var/log/mysql/mysql-slow.log
NGINX_LOG:=/var/log/nginx/access.log

NOTIFY_SLACK_TMPFILE:=tmp/notify-slack.txt

# メインで使うコマンド ------------------------

# サーバーの環境構築　ツールのインストール、gitまわりのセットアップ
.PHONY: setup
setup: install-tools dir-setup git-setup

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-envsh

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-envsh

# ベンチマークを走らせる直前に実行する
.PHONY: bench
bench:
	git pull 
	make check-server-id 
	make build
	make rm-logs
	make deploy-conf
	make restart

# notify_slack系をまとめて通知する
.PHONY: ns
ns: notify-slack-alp notify-slack-slow-query

# slow queryを確認する
.PHONY: slow-query
slow-query: 
	sudo pt-query-digest $(DB_SLOW_LOG)

# notify_slackでslow-queryを通知する
.PHONY: notify-slack-slow-query
notify-slack-slow-query: 
	$(eval when := $(shell date "+%Y-%m-%d-%H:%M:%S"))
	make refresh-notify-slack-tmp
	make slow-query >> $(NOTIFY_SLACK_TMPFILE)
	cat $(NOTIFY_SLACK_TMPFILE) | notify_slack -c tool-config/slow-query/notify-slack.toml -snippet -filename=$(when).txt

# alpでアクセスログを確認する
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGINX_LOG) --config=tool-config/alp/config.yml

# notify_slackでalpの結果を通知する
.PHONY: notify-slack-alp
notify-slack-alp:
	$(eval when := $(shell date "+%Y-%m-%d-%H:%M:%S"))
	make refresh-notify-slack-tmp
	make alp >> $(NOTIFY_SLACK_TMPFILE)
	cat $(NOTIFY_SLACK_TMPFILE) | notify_slack -c tool-config/alp/notify-slack.toml -snippet -filename=$(when).txt

# pprofで記録する
.PHONY: pprof-record
pprof-record: 
	go tool pprof http://localhost:6060/debug/pprof/profile

# pprofで確認する
.PHONY: pprof-check
pprof-check: 
	$(eval latest := $(shell ls -rt ~/pprof/ | tail -n 1))
	go tool pprof -http=localhost:8090 ~/pprof/$(latest)

# SQLクエリをmain.goから抽出する
.PHONY: extract-sql
extract-sql: extract-select extract-insert extract-update extract-delete

# アプリケーションのログを確認する
.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f

.PHONY: extract-queries
extract-queries: extract-select extract-insert extract-update extract-delete

# 主要コマンドの構成要素 ------------------------

.PHONY: install-tools
install-tools:
	sudo apt update

	sudo apt install -y percona-toolkit dstat git unzip snapd graphviz tree

	# alpのインストール
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.9/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo install alp /usr/local/bin/alp
	rm alp_linux_amd64.zip alp

	# notify_slackのインストール
	wget https://github.com/catatsuy/notify_slack/releases/download/v0.5.1/notify_slack-linux-amd64.tar.gz
	tar -xvf notify_slack-linux-amd64.tar.gz
	sudo install notify_slack /usr/local/bin/notify_slack
	rm notify_slack-linux-amd64.tar.gz notify_slack LICENSE CHANGELOG.md README.md

.PHONY: dir-setup
dir-setup:
	mkdir -p tool-config/alp tool-config/slow-query queries
	touch tool-config/alp/.keep tool-config/slow-query/.keep queries/.keep

.PHONY: git-setup
git-setup:
	# git用の設定は適宜変更して良い
	git config --global user.email "yuhi120101@gmail.com"
	git config --global user.name "Yuhi-Sato"

	# deploykeyの作成
	ssh-keygen -t ed25519

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	mkdir -p s1/etc/mysql s1/etc/nginx
	cp -R /home/isucon/env.sh s1/env.sh
	echo "SERVER_ID=s1" >> s1/env.sh
	echo "SERVER_ID=s1" >> ~/env.sh

.PHONY: set-as-s2
set-as-s2:
	mkdir -p s2/etc/mysql s2/etc/nginx
	cp -R /home/isucon/env.sh s2/env.sh
	echo "SERVER_ID=s2" >> s2/env.sh
	echo "SERVER_ID=s2" >> ~/env.sh

.PHONY: set-as-s3
set-as-s3:
	mkdir -p s3/etc/mysql s3/etc/nginx
	cp -R /home/isucon/env.sh s3/env.sh
	echo "SERVER_ID=s3" >> s3/env.sh
	echo "SERVER_ID=s3" >> ~/env.sh

.PHONY: get-db-conf
get-db-conf:
	sudo cp -R $(DB_PATH)/* $(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R $(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo cp -R $(NGINX_PATH)/* $(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R $(SERVER_ID)/etc/nginx

.PHONY: get-envsh
get-envsh:
	cp ~/env.sh $(SERVER_ID)/env.sh

.PHONY: deploy-db-conf
deploy-db-conf: 
	sudo cp -R $(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf: 
	sudo cp -R $(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-envsh
deploy-envsh:
	cp $(SERVER_ID)/env.sh ~/env.sh

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart mysql
	sudo systemctl restart nginx

.PHONY: rm-logs
rm-logs:
	sudo rm -f $(NGINX_LOG)
	sudo rm -f $(DB_SLOW_LOG)

.PHONY: refresh-notify-slack-tmp
refresh-notify-slack-tmp:
	rm -f $(NOTIFY_SLACK_TMPFILE)
	mkdir -p tmp
	touch $(NOTIFY_SLACK_TMPFILE)

.PHONY: extract-select
extract-select:
	find $(BUILD_DIR) -name "*.go" | xargs grep "\"SELECT" | sed -E 's/.*"(SELECT .* FROM.*)".*/\1/' > queries/select.sql
	echo >> queries/select.sql
	echo ----------------------------------------- back quote queries ----------------------------------------- >> queries/select.sql
	find $(BUILD_DIR) -name "*.go" | xargs awk '/`/ { back_quote += gsub(/`/, "`") } \
		back_quote % 2 == 1 && /SELECT/ { select_flag = 1 } \
		select_flag && back_quote % 2 == 1 { print } \
		back_quote % 2 == 0 && select_flag { select_flag = 0 }' >> queries/select.sql

.PHONY: extract-insert
extract-insert:
	find $(BUILD_DIR) -name "*.go" | xargs grep "\"INSERT" | sed -E 's/.*"(INSERT INTO .*)".*/\1/' > queries/insert.sql
	echo >> queries/insert.sql
	echo ----------------------------------------- back quote queries ----------------------------------------- >> queries/insert.sql
	find $(BUILD_DIR) -name "*.go" | xargs awk '/`/ { back_quote += gsub(/`/, "`") } \
		back_quote % 2 == 1 && /INSERT/ { insert_flag = 1 } \
		insert_flag && back_quote % 2 == 1 { print } \
		back_quote % 2 == 0 && insert_flag { insert_flag = 0 }' >> queries/insert.sql

.PHONY: extract-update
extract-update:
	find $(BUILD_DIR) -name "*.go" | xargs grep "\"UPDATE" | sed -E 's/.*"(UPDATE .*)".*/\1/' > queries/update.sql
	echo >> queries/update.sql
	echo ----------------------------------------- back quote queries ----------------------------------------- >> queries/update.sql
	find $(BUILD_DIR) -name "*.go" | xargs awk '/`/ { back_quote += gsub(/`/, "`") } \
		back_quote % 2 == 1 && /UPDATE/ { update_flag = 1 } \
		update_flag && back_quote % 2 == 1 { print } \
		back_quote % 2 == 0 && update_flag { update_flag = 0 }' >> queries/update.sql

.PHONY: extract-delete
extract-delete:
	find $(BUILD_DIR) -name "*.go" | xargs grep "\"DELETE" | sed -E 's/.*"(DELETE .*)".*/\1/' > queries/delete.sql
	echo >> queries/delete.sql
	echo ----------------------------------------- back quote queries ----------------------------------------- >> queries/delete.sql
	find $(BUILD_DIR) -name "*.go" | xargs awk '/`/ { back_quote += gsub(/`/, "`") } \
		back_quote % 2 == 1 && /DELETE/ { delete_flag = 1 } \
		delete_flag && back_quote % 2 == 1 { print } \
		back_quote % 2 == 0 && delete_flag { delete_flag = 0 }' >> queries/delete.sql
