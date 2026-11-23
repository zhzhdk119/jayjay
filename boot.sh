#!/bin/bash
# Prime 수집 서버 시작 스크립트(R-ADV-1120-2306) — 비밀값 0 · 우리 수집 코드 0.
# 하는 일: 설치 꾸러미(kit.tgz)를 받아 확인값(sha256)을 맞춰 보고 설치를 시작해요. 수집 코드는 등록 승인 뒤 서명한 요청으로만 받아요.
set -euo pipefail
BASE="https://raw.githubusercontent.com/zhzhdk119/jayjay/kit-1800-v1"
[ "$(id -u)" -eq 0 ] || { echo "앞에 sudo 를 붙여 주세요:  curl -fsSL $BASE/boot.sh | sudo bash"; exit 1; }
T=$(mktemp -d)
curl -fsSL "$BASE/kit.tgz" -o "$T/kit.tgz"
WANT="ab6c963f23c82121ba08896a6d55cb5aad3edd385b4f558308755c35a9272af1"
GOT=$(sha256sum "$T/kit.tgz" | cut -d' ' -f1)
[ "$WANT" = "$GOT" ] || { echo "설치 꾸러미 확인값이 달라요 — 멈춥니다"; exit 1; }
mkdir -p /opt/prime-collector
STAGE=$(mktemp -d /opt/prime-collector/kit.stage.XXXXXX)
tar xzf "$T/kit.tgz" -C "$STAGE"
chmod 755 "$STAGE"
if [ -d /opt/prime-collector/kit ]; then mv /opt/prime-collector/kit "/opt/prime-collector/kit.prev.$(date +%s%N)"; fi
mv "$STAGE" /opt/prime-collector/kit
echo "설치 꾸러미 확인 완료 ($WANT 앞 12글자: ${WANT:0:12}) — 설치를 시작해요."
exec bash /opt/prime-collector/kit/install.sh </dev/null
